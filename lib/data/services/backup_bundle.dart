import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/error_codes.dart';
import '../../domain/repositories/backup_repository.dart';
import '../repositories/backup_repository_impl.dart';

/// MCRB0001 + manifest 길이(u32 BE) + manifest + 순서대로 연결한 파일.
/// 압축/추출 없이 스트림을 검증하므로 경로를 통해 앱 자료를 덮어쓰지 않는다.
class BackupBundle {
  static const magic = 'MCRB0001';
  static const maxManifestBytes = 8 * 1024 * 1024;
  static const maxBytes =
      BackupRepositoryImpl.maxTotalBytes + maxManifestBytes + 12;

  Future<BackupSummary> pack(
    Directory snapshot,
    File destination,
    BackupRepository repository,
  ) async {
    final summary = await repository.verify(snapshot.path);
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const AppException(ErrorCode.conflict);
    }
    final manifestFile = File('${snapshot.path}/manifest.json');
    if (await manifestFile.length() > maxManifestBytes) _invalid();
    final manifest = await manifestFile.readAsBytes();
    final rows = _entries(manifest);
    final header = ByteData(12)
      ..buffer.asUint8List().setRange(0, 8, ascii.encode(magic));
    header.setUint32(8, manifest.length);
    final out = await destination.open(mode: FileMode.write);
    var complete = false;
    try {
      await out.writeFrom(header.buffer.asUint8List());
      await out.writeFrom(manifest);
      for (final row in rows) {
        final source = File('${snapshot.path}/files/${row.path}');
        await for (final chunk in source.openRead()) {
          await out.writeFrom(chunk);
        }
      }
      await out.flush();
      await out.close();
      await inspect(destination);
      complete = true;
      return summary;
    } finally {
      try {
        await out.close();
      } on Object {
        /* 이미 닫힌 핸들. */
      }
      if (!complete && await destination.exists()) await destination.delete();
    }
  }

  /// 검증된 페이로드를 새 전용 디렉토리에만 추출한다. 기존 경로는 거절한다.
  Future<BackupSummary> extract(File file, Directory destination) async {
    final summary = await inspect(file);
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const AppException(ErrorCode.conflict);
    }
    final input = await file.open();
    var created = false;
    try {
      final header = await input.read(12);
      final length = ByteData.sublistView(header).getUint32(8);
      if (length == 0 || length > maxManifestBytes) _invalid();
      final rows = _entries(await input.read(length));
      await destination.create();
      created = true;
      for (final row in rows) {
        final target = File('${destination.path}/${row.path}');
        await target.parent.create(recursive: true);
        final output = await target.open(mode: FileMode.write);
        try {
          var remaining = row.size;
          while (remaining > 0) {
            final chunk = await input.read(remaining.clamp(1, 64 * 1024));
            if (chunk.isEmpty) _invalid();
            await output.writeFrom(chunk);
            remaining -= chunk.length;
          }
          await output.flush();
        } finally {
          await output.close();
        }
        if ((await sha256.bind(target.openRead()).first).toString() !=
            row.digest) {
          _invalid();
        }
      }
      if (await input.position() != await input.length()) _invalid();
      return summary;
    } on Object {
      if (created && await destination.exists()) {
        await destination.delete(recursive: true);
      }
      rethrow;
    } finally {
      await input.close();
    }
  }

  Future<BackupSummary> inspect(File file) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      _invalid();
    }
    final size = await file.length();
    if (size < 12 || size > maxBytes) _invalid();
    final input = await file.open();
    try {
      final header = await input.read(12);
      if (header.length != 12 ||
          ascii.decode(header.sublist(0, 8), allowInvalid: true) != magic) {
        _invalid();
      }
      final length = ByteData.sublistView(header).getUint32(8);
      if (length == 0 || length > maxManifestBytes || length > size - 12) {
        _invalid();
      }
      final manifest = await input.read(length);
      if (manifest.length != length) _invalid();
      final rows = _entries(manifest);
      var position = 12 + length;
      final total = rows.fold<int>(0, (sum, row) => sum + row.size);
      if (position + total != size) _invalid();
      for (final row in rows) {
        final digest = await sha256
            .bind(file.openRead(position, position + row.size))
            .first;
        if (digest.toString() != row.digest) _invalid();
        position += row.size;
      }
      if (await file.length() != size) _invalid();
      return BackupSummary(fileCount: rows.length, totalBytes: total);
    } finally {
      await input.close();
    }
  }

  List<_BundleEntry> _entries(List<int> bytes) {
    if (bytes.length > maxManifestBytes) _invalid();
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map ||
          raw['format'] != 'mychild-reading-directory-backup' ||
          raw['version'] != 1 ||
          raw['createdAt'] is! String ||
          DateTime.tryParse(raw['createdAt']) == null ||
          raw['files'] is! List) {
        _invalid();
      }
      final files = raw['files'] as List;
      if (files.length > BackupRepositoryImpl.maxFiles) _invalid();
      final seen = <String>{};
      var total = 0;
      final entries = files.map((row) {
        if (row is! Map ||
            row['path'] is! String ||
            row['size'] is! int ||
            row['sha256'] is! String) {
          _invalid();
        }
        final path = row['path'] as String;
        final parts = path.split('/');
        if (path.length > 1024 ||
            parts.length < 2 ||
            parts.length > BackupRepositoryImpl.maxDepth ||
            !{
              'library',
              'index',
              'drafts',
              'reading_positions',
            }.contains(parts.first) ||
            parts.any(
              (part) =>
                  !RegExp(r'^[a-zA-Z0-9_-][a-zA-Z0-9_.-]*$').hasMatch(part),
            ) ||
            !seen.add(path.toLowerCase()) ||
            row['size'] < 0 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['sha256'])) {
          _invalid();
        }
        total += row['size'] as int;
        if (total > BackupRepositoryImpl.maxTotalBytes) _invalid();
        return _BundleEntry(path, row['size'], row['sha256']);
      }).toList();
      for (final path in seen) {
        final parts = path.split('/');
        for (var i = 1; i < parts.length; i++) {
          if (seen.contains(parts.take(i).join('/'))) _invalid();
        }
      }
      return entries;
    } on FormatException {
      _invalid();
    }
  }

  Never _invalid() => throw const AppException(ErrorCode.backupInvalid);
}

class _BundleEntry {
  const _BundleEntry(this.path, this.size, this.digest);
  final String path;
  final int size;
  final String digest;
}

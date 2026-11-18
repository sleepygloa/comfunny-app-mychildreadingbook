import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/error_codes.dart';
import '../../domain/repositories/backup_repository.dart';
import '../local/app_paths.dart';

/// 무압축 디렉토리 스냅샷. 앱 데이터 밖의 키/캐시/로그는 수집하지 않는다.
/// 손상된 JSON도 원문 보존한다. 의미 검증 및 활성 데이터 교체는 후속 단계다.
class BackupRepositoryImpl implements BackupRepository {
  BackupRepositoryImpl(this.baseDir);
  final Directory baseDir;
  Future<void> _pending = Future<void>.value();

  static const _roots = {
    AppPaths.libraryDir,
    AppPaths.indexDir,
    AppPaths.draftsDir,
    AppPaths.readingPositionsDir,
  };
  static const maxFiles = 20000;
  static const maxEntries = 40000;
  static const maxDepth = 16;
  static const maxTotalBytes = 20 * 1024 * 1024 * 1024;
  static const _maxManifestBytes = 8 * 1024 * 1024;

  Future<T> _run<T>(Future<T> Function() action) {
    final task = _pending.then((_) async {
      try {
        return await action();
      } on FileSystemException {
        throw const AppException(ErrorCode.storageFailure);
      } on FormatException {
        throw const AppException(ErrorCode.backupInvalid);
      }
    });
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  @override
  Future<BackupSummary> create(String destinationPath) => _run(() async {
    // FLOW 1: 앱 데이터 하위/상위에 백업을 만들면 자신을 수집할 수 있다.
    final source = await _existingDirectory(baseDir.path);
    final target = await _newDirectory(destinationPath);
    _separate(source.path, target.path);
    final entries = await _scan(source);
    final staging = await target.parent.createTemp('.mcr-backup-');
    try {
      // FLOW 2: 파일을 스트리밍 복사하고 원본 지문과 대조한다.
      final payload = await Directory('${staging.path}/files').create();
      await _copy(source, payload, entries);
      // FLOW 3: 복사 중 추가·삭제·수정은 성공으로 발표하지 않는다.
      if (!_same(entries, await _scan(source))) {
        throw const AppException(ErrorCode.backupChanged);
      }
      await File('${staging.path}/manifest.json').writeAsString(
        jsonEncode({
          'format': 'mychild-reading-directory-backup',
          'version': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'files': entries.map((entry) => entry.toJson()).toList(),
        }),
        flush: true,
      );
      await _verify(staging);
      // FLOW 9: 검증 완료 디렉토리만 최종 이름으로 공개한다.
      await _publish(staging, target);
      return _summary(entries);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  });

  @override
  Future<BackupSummary> verify(String backupPath) => _run(() async {
    return _summary(await _verify(await _existingDirectory(backupPath)));
  });

  @override
  Future<BackupSummary> restoreToNewDirectory(
    String backupPath,
    String destinationPath,
  ) => _run(() async {
    // FLOW 1: 존재하는 경로는 비어 있어도 교체하지 않는다.
    final backup = await _existingDirectory(backupPath);
    final target = await _newDirectory(destinationPath);
    final active = await _existingDirectory(baseDir.path);
    _separate(backup.path, target.path);
    _separate(active.path, target.path);
    final entries = await _verify(backup);
    final staging = await target.parent.createTemp('.mcr-restore-');
    try {
      // FLOW 2: 활성 책장이 아닌 격리 경로에 복사·대조한다.
      await _copy(Directory('${backup.path}/files'), staging, entries);
      if (!_same(entries, await _scan(staging))) {
        throw const AppException(ErrorCode.backupInvalid);
      }
      // FLOW 9: 실패/중단 시 기존 앱 데이터와 백업은 그대로 남는다.
      await _publish(staging, target);
      return _summary(entries);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  });

  Future<List<_Entry>> _verify(Directory backup) async {
    final manifest = await _safeFile(backup, 'manifest.json');
    if (await manifest.length() > _maxManifestBytes) _invalid();
    // 길이 검사 직후 커지는 manifest도 메모리 상한을 넘겨 읽지 않는다.
    final bytes = await manifest
        .openRead(0, _maxManifestBytes + 1)
        .fold<List<int>>(<int>[], (buffer, chunk) => buffer..addAll(chunk));
    if (bytes.length > _maxManifestBytes) _invalid();
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map ||
        raw['format'] != 'mychild-reading-directory-backup' ||
        raw['version'] != 1 ||
        raw['createdAt'] is! String ||
        DateTime.tryParse(raw['createdAt'] as String) == null ||
        raw['files'] is! List) {
      _invalid();
    }
    final files = raw['files'] as List;
    if (files.length > maxFiles) _invalid();
    final entries = <_Entry>[];
    final seen = <String>{};
    var total = 0;
    for (final value in files) {
      if (value is! Map ||
          value['path'] is! String ||
          value['size'] is! int ||
          value['sha256'] is! String) {
        _invalid();
      }
      final path = value['path'] as String;
      _validatePath(path);
      // 이동 대상 파일시스템의 대소문자 규칙 차이도 충돌로 취급한다.
      if (!seen.add(path.toLowerCase())) _invalid();
      final size = value['size'] as int;
      final digest = value['sha256'] as String;
      if (size < 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) _invalid();
      total += size;
      if (total > maxTotalBytes) _invalid();
      entries.add(_Entry(path, size, digest));
    }
    entries.sort((a, b) => a.path.compareTo(b.path));
    final payload = await _existingDirectory('${backup.path}/files');
    // manifest에 없는 데이터도 거부한다. 누락된 파일을 정상으로 간주하지 않는다.
    final actual = await _scan(payload, strictRoot: true);
    if (!_same(entries, actual)) _invalid();
    return entries;
  }

  Future<List<_Entry>> _scan(Directory root, {bool strictRoot = false}) async {
    final entries = <_Entry>[];
    final seen = <String>{};
    var total = 0;
    var visited = 0;
    Future<void> visit(Directory dir, String prefix) async {
      await for (final entity in dir.list(followLinks: false)) {
        if (++visited > maxEntries) _invalid();
        final name = entity.path.split(Platform.pathSeparator).last;
        final path = prefix.isEmpty ? name : '$prefix/$name';
        if (prefix.isEmpty && !_roots.contains(name)) {
          if (strictRoot) _invalid();
          continue;
        }
        // 임시 쓰기 잔재는 조용히 제외하지 않는다. 저장 중/오류 상태를 알린다.
        if (name.endsWith('.tmp')) {
          throw const AppException(ErrorCode.backupChanged);
        }
        if (entity is Directory) {
          _validatePath(path, isDirectory: true);
          await visit(entity, path);
        } else if (entity is File) {
          _validatePath(path);
          if (!seen.add(path.toLowerCase()) || entries.length >= maxFiles) {
            _invalid();
          }
          final file = await _safeFile(root, path);
          final size = await file.length();
          total += size;
          if (total > maxTotalBytes) _invalid();
          final digest = await sha256.bind(file.openRead(0, size)).first;
          if (await file.length() != size) {
            throw const AppException(ErrorCode.backupChanged);
          }
          entries.add(_Entry(path, size, digest.toString()));
        } else {
          // 링크를 따라 앱 경계 밖의 개인정보를 수집하지 않는다.
          _invalid();
        }
      }
    }

    await visit(root, '');
    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Future<void> _copy(
    Directory source,
    Directory target,
    List<_Entry> entries,
  ) async {
    for (final entry in entries) {
      final from = await _safeFile(source, entry.path);
      final to = File('${target.path}/${entry.path}');
      await to.parent.create(recursive: true);
      // 파일 단위 읽기 상한: 읽는 중 커지는 파일이 디스크를 채우지 않게 한다.
      final input = await from.open();
      try {
        // 출력 open 실패도 입력 핸들을 닫는다. close 실패도 서로 전파하지 않는다.
        final output = await to.open(mode: FileMode.write);
        try {
          var remaining = entry.size;
          while (remaining > 0) {
            final chunk = await input.read(
              remaining > 65536 ? 65536 : remaining,
            );
            if (chunk.isEmpty) _invalid();
            await output.writeFrom(chunk);
            remaining -= chunk.length;
          }
          if ((await input.read(1)).isNotEmpty) _invalid();
          await output.flush();
        } finally {
          await output.close();
        }
      } finally {
        await input.close();
      }
      if ((await sha256.bind(to.openRead()).first).toString() != entry.digest) {
        _invalid();
      }
    }
  }

  void _validatePath(String path, {bool isDirectory = false}) {
    final parts = path.split('/');
    if (path.length > 1024 ||
        parts.length < (isDirectory ? 1 : 2) ||
        parts.length > maxDepth ||
        !_roots.contains(parts.first) ||
        parts.any(
          (part) => !RegExp(r'^[a-zA-Z0-9_-][a-zA-Z0-9_.-]*$').hasMatch(part),
        ) ||
        path.contains('\\')) {
      _invalid();
    }
  }

  Future<File> _safeFile(Directory root, String relative) async {
    var path = root.path;
    final parts = relative.split('/');
    for (var i = 0; i < parts.length; i++) {
      path = '$path/${parts[i]}';
      final kind = await FileSystemEntity.type(path, followLinks: false);
      if (kind !=
          (i == parts.length - 1
              ? FileSystemEntityType.file
              : FileSystemEntityType.directory)) {
        _invalid();
      }
    }
    return File(path);
  }

  Future<Directory> _existingDirectory(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      _invalid();
    }
    return Directory(await Directory(path).resolveSymbolicLinks());
  }

  Future<Directory> _newDirectory(String path) async {
    final dir = Directory(path).absolute;
    final name = dir.path.split(Platform.pathSeparator).last;
    if (!RegExp(r'^[a-zA-Z0-9_-][a-zA-Z0-9_.-]*$').hasMatch(name)) _invalid();
    final parent = await _existingDirectory(dir.parent.path);
    final target = Directory('${parent.path}/$name');
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const AppException(ErrorCode.conflict);
    }
    return target;
  }

  void _separate(String a, String b) {
    if (a == b || a.startsWith('$b/') || b.startsWith('$a/')) _invalid();
  }

  Future<void> _publish(Directory staging, Directory target) async {
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const AppException(ErrorCode.conflict);
    }
    await staging.rename(target.path);
  }

  bool _same(List<_Entry> a, List<_Entry> b) =>
      a.length == b.length &&
      List.generate(
        a.length,
        (i) =>
            a[i].path == b[i].path &&
            a[i].size == b[i].size &&
            a[i].digest == b[i].digest,
      ).every((value) => value);

  BackupSummary _summary(List<_Entry> entries) => BackupSummary(
    fileCount: entries.length,
    totalBytes: entries.fold(0, (sum, entry) => sum + entry.size),
  );

  Never _invalid() => throw const AppException(ErrorCode.backupInvalid);
}

class _Entry {
  const _Entry(this.path, this.size, this.digest);
  final String path;
  final int size;
  final String digest;
  Map<String, Object> toJson() => {
    'path': path,
    'size': size,
    'sha256': digest,
  };
}

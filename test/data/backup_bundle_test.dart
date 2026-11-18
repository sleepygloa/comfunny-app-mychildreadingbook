import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/repositories/backup_repository_impl.dart';
import 'package:mychild_reading/data/services/backup_bundle.dart';

void main() {
  late Directory temp;
  late Directory source;
  late File bundle;
  final service = BackupBundle();
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bundle-test-');
    source = await Directory('${temp.path}/source').create();
    bundle = File('${temp.path}/library.mcrb');
  });
  tearDown(() async => temp.delete(recursive: true));

  Future<void> pack() async {
    final repository = BackupRepositoryImpl(source);
    final snapshot = Directory('${temp.path}/snapshot');
    await repository.create(snapshot.path);
    await service.pack(snapshot, bundle, repository);
  }

  Future<void> forged(List<String> paths) async {
    final manifest = utf8.encode(
      jsonEncode({
        'format': 'mychild-reading-directory-backup',
        'version': 1,
        'createdAt': '2026-09-22T00:00:00Z',
        'files': paths
            .map(
              (path) => {
                'path': path,
                'size': 0,
                'sha256': sha256.convert([]).toString(),
              },
            )
            .toList(),
      }),
    );
    final header = ByteData(12)..setUint32(8, manifest.length);
    header.buffer.asUint8List().setRange(
      0,
      8,
      ascii.encode(BackupBundle.magic),
    );
    await bundle.writeAsBytes([...header.buffer.asUint8List(), ...manifest]);
  }

  test(
    'binary media and empty files survive streamed packing and inspection',
    () async {
      final media = File('${source.path}/library/book/pages/page.png');
      await media.parent.create(recursive: true);
      final bytes = List<int>.generate(150000, (i) => i % 256);
      await media.writeAsBytes(bytes);
      final empty = File('${source.path}/index/empty.json');
      await empty.parent.create();
      await empty.writeAsBytes([]);
      await pack();
      final summary = await service.inspect(bundle);
      expect(summary.fileCount, 2);
      expect(summary.totalBytes, bytes.length);
      expect(await media.readAsBytes(), bytes);
      expect(await source.list().length, 2);
    },
  );
  test('empty library produces valid portable file', () async {
    await pack();
    expect((await service.inspect(bundle)).fileCount, 0);
  });
  test('existing destination is never overwritten', () async {
    await pack();
    final before = await bundle.readAsBytes();
    await expectLater(
      service.pack(
        Directory('${temp.path}/snapshot'),
        bundle,
        BackupRepositoryImpl(source),
      ),
      throwsA(isA<AppException>()),
    );
    expect(await bundle.readAsBytes(), before);
  });
  for (final mode in [
    'payload',
    'truncated',
    'trailing',
    'version',
    'manifest',
  ]) {
    test('rejects $mode corruption without touching source', () async {
      final file = File('${source.path}/index/data.json');
      await file.parent.create();
      await file.writeAsString('{"sample":true}');
      await pack();
      var bytes = await bundle.readAsBytes();
      switch (mode) {
        case 'payload':
          bytes[bytes.length - 1] ^= 1;
        case 'truncated':
          bytes = bytes.sublist(0, bytes.length - 1);
        case 'trailing':
          bytes = Uint8List.fromList([...bytes, 0]);
        case 'version':
          bytes[7] = 50;
        case 'manifest':
          ByteData.sublistView(bytes).setUint32(8, 0xffffffff);
      }
      await bundle.writeAsBytes(bytes);
      await expectLater(service.inspect(bundle), throwsA(isA<AppException>()));
      expect(await file.readAsString(), '{"sample":true}');
    });
  }
  for (final paths in [
    ['library/../escape'],
    ['other/data'],
    ['library/a', 'library/A'],
    ['library/a', 'library/a/b'],
    ['library/a\\b'],
  ]) {
    test('rejects unsafe manifest paths $paths', () async {
      await forged(paths);
      await expectLater(service.inspect(bundle), throwsA(isA<AppException>()));
      expect(await source.list().isEmpty, isTrue);
    });
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/data/services/restore_transaction.dart';

void main() {
  late Directory temp;
  late Directory base;
  late Directory ready;
  Future<void> write(Directory dir, String path, String value) async {
    final file = File('${dir.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('restore-transaction-');
    base = await Directory('${temp.path}/base').create();
    ready = await Directory('${base.path}/staging').create();
    await write(base, 'library/old/data.json', 'old library');
    await write(base, 'index/old.json', 'old index');
    await write(base, 'unrelated/value', 'untouched');
    await write(ready, 'library/new/data.json', 'new library');
    await write(ready, 'drafts/new/data.json', 'new draft');
  });
  tearDown(() async => temp.delete(recursive: true));
  Future<void> expectOld() async {
    expect(
      await File('${base.path}/library/old/data.json').readAsString(),
      'old library',
    );
    expect(
      await File('${base.path}/index/old.json').readAsString(),
      'old index',
    );
    expect(await Directory('${base.path}/drafts').exists(), false);
    expect(
      await File('${base.path}/unrelated/value').readAsString(),
      'untouched',
    );
  }

  test('교체 후 재조회 성공시에만 확정하고 다른 디렉토리는 유지한다', () async {
    await RestoreTransaction(base).apply(ready, () async {
      expect(
        await File('${base.path}/library/new/data.json').readAsString(),
        'new library',
      );
      expect(
        await File(
          '${base.path}/.restore-transaction/old/library/old/data.json',
        ).exists(),
        true,
      );
    });
    expect(await Directory('${base.path}/index').exists(), false);
    expect(
      await Directory('${base.path}/.restore-transaction').exists(),
      false,
    );
    expect(
      await File('${base.path}/unrelated/value').readAsString(),
      'untouched',
    );
  });
  for (final step in [
    'journal',
    'old-library',
    'new-library',
    'old-index',
    'new-index',
    'old-drafts',
    'new-drafts',
    'old-reading_positions',
    'new-reading_positions',
    'reloaded',
  ]) {
    test('$step 오류는 원본을 복구하고 재조회한다', () async {
      var reloads = 0;
      await expectLater(
        RestoreTransaction(
          base,
          checkpoint: (value) async {
            if (value == step) throw const FileSystemException('injected');
          },
        ).apply(ready, () async {
          reloads++;
        }),
        throwsA(isA<FileSystemException>()),
      );
      await expectOld();
      expect(reloads, greaterThanOrEqualTo(1));
      await RestoreTransaction(base).recover();
      await expectOld();
    });
  }
  test('새 자료 재조회 실패도 기존 자료로 돌아간다', () async {
    var reloads = 0;
    await expectLater(
      RestoreTransaction(base).apply(ready, () async {
        reloads++;
        if (reloads == 1) throw StateError('injected reload');
      }),
      throwsStateError,
    );
    expect(reloads, 2);
    await expectOld();
  });
  test('롤백 후에도 재조회할 수 없으면 보호 상태를 요구한다', () async {
    await expectLater(
      RestoreTransaction(base).apply(ready, () async {
        throw StateError('persistent reload failure');
      }),
      throwsA(isA<RestoreRecoveryFailure>()),
    );
    await expectOld();
  });
  test('일부 롤백 후 종료된 저널을 다시 처리해도 복구한 루트를 지우지 않는다', () async {
    final tx = RestoreTransaction(base);
    await Directory('${tx.work.path}/old').create(recursive: true);
    await Directory('${base.path}/index').rename('${tx.work.path}/old/index');
    await write(base, 'index/new.json', 'new');
    await write(base, 'drafts/new/data.json', 'new draft');
    await tx.journal.writeAsString(
      jsonEncode({
        'version': 1,
        'phase': 'pending',
        'oldRoots': ['library', 'index'],
      }),
    );
    await tx.recover();
    await tx.recover();
    await expectOld();
  });
  for (final step in [
    'journal',
    'old-library',
    'new-library',
    'new-index',
    'new-drafts',
    'reloaded',
    'committed',
  ]) {
    test('별도 Dart 프로세스 $step 강제 종료 후 startup recovery', () async {
      final uri = File('lib/data/services/restore_transaction.dart')
          .absolute
          .uri;
      final child = File('${temp.path}/crash.dart');
      await child.writeAsString(
        "import 'dart:io';\nimport '$uri';\nFuture<void> main(List<String> args) async { await RestoreTransaction(Directory(args[0]), checkpoint: (s) async { if (s == args[2]) exit(73); }).apply(Directory(args[1]), () async {}); }\n",
      );
      final result = await Process.run('dart', [
        child.path,
        base.path,
        ready.path,
        step,
      ]);
      expect(result.exitCode, 73, reason: '${result.stderr}');
      await RestoreTransaction(base).recover();
      await RestoreTransaction(base).recover();
      if (step == 'committed') {
        expect(
          await File('${base.path}/library/new/data.json').readAsString(),
          'new library',
        );
        expect(
          await File('${base.path}/library/old/data.json').exists(),
          false,
        );
      } else {
        await expectOld();
      }
    });
  }
}

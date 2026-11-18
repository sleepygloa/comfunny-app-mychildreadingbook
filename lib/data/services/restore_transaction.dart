import 'dart:convert';
import 'dart:io';

import '../../core/error_codes.dart';

/// 네 루트 교체의 저널. 미확정 작업은 앱 시작 전에 멱등 롤백한다.
/// 앱 저장소와 같은 볼륨의 rename만 사용하며 원본은 commit 전까지 보관한다.
class RestoreTransaction {
  RestoreTransaction(this.base, {this.checkpoint});
  final Directory base;
  final Future<void> Function(String)? checkpoint;
  static const roots = ['library', 'index', 'drafts', 'reading_positions'];
  Directory get work => Directory('${base.path}/.restore-transaction');
  File get journal => File('${work.path}/journal.json');

  Future<void> _plain(String path, {bool directory = true}) async {
    final kind = await FileSystemEntity.type(path, followLinks: false);
    if (kind != FileSystemEntityType.notFound &&
        kind !=
            (directory
                ? FileSystemEntityType.directory
                : FileSystemEntityType.file)) {
      throw const AppException(ErrorCode.storageFailure);
    }
  }

  Future<void> _record(Map<String, Object?> value) async {
    final tmp = File('${journal.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(journal.path);
  }

  Future<void> recover() async {
    await _plain(work.path);
    if (!await work.exists()) return;
    await _plain(journal.path, directory: false);
    if (!await journal.exists()) {
      // 저널 작성 전에는 원본 루트를 이동하지 않는다.
      await work.delete(recursive: true);
      return;
    }
    if (await journal.length() > 4096) {
      throw const AppException(ErrorCode.storageFailure);
    }
    final raw = jsonDecode(await journal.readAsString());
    if (raw is! Map ||
        raw['version'] != 1 ||
        !['pending', 'committed'].contains(raw['phase']) ||
        raw['oldRoots'] is! List ||
        (raw['oldRoots'] as List).any((v) => !roots.contains(v))) {
      throw const AppException(ErrorCode.storageFailure);
    }
    if (raw['phase'] == 'pending') {
      for (final root in roots) {
        final old = Directory('${work.path}/old/$root');
        final current = Directory('${base.path}/$root');
        await _plain('${work.path}/old');
        await _plain(old.path);
        await _plain(current.path);
        if (await old.exists()) {
          if (await current.exists()) await current.delete(recursive: true);
          await old.rename(current.path);
        } else if (!(raw['oldRoots'] as List).contains(root)) {
          if (await current.exists()) await current.delete(recursive: true);
        }
      }
    }
    // journal을 마지막에 지워야 정리 중 종료돼도 rollback/commit 판정이 남는다.
    for (final name in ['old', 'incoming']) {
      final dir = Directory('${work.path}/$name');
      await _plain(dir.path);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    await journal.delete();
    await work.delete(recursive: true);
  }

  Future<void> apply(Directory ready, Future<void> Function() reload) async {
    try { await recover(); } on Object { throw const RestoreRecoveryFailure(); }
    await _plain(ready.path);
    final oldRoots = <String>[];
    for (final root in roots) {
      await _plain('${base.path}/$root');
      if (await Directory('${base.path}/$root').exists()) oldRoots.add(root);
    }
    await work.create();
    final state = <String, Object?>{
      'version': 1,
      'phase': 'pending',
      'oldRoots': oldRoots,
    };
    var committed = false;
    try {
      // FLOW 1: 추출/검증 완료 자료만 같은 볼륨의 트랜잭션 안으로 이동한다.
      await ready.rename('${work.path}/incoming');
      await Directory('${work.path}/old').create();
      await _record(state);
      await checkpoint?.call('journal');
      // FLOW 2: 기존 루트를 보관하고 새 루트를 배치한다.
      for (final root in roots) {
        final current = Directory('${base.path}/$root');
        if (oldRoots.contains(root)) {
          await current.rename('${work.path}/old/$root');
        }
        await checkpoint?.call('old-$root');
        final incoming = Directory('${work.path}/incoming/$root');
        if (await incoming.exists()) await incoming.rename(current.path);
        await checkpoint?.call('new-$root');
      }
      // FLOW 3: 화면/OS 큐가 새 자료를 읽은 뒤에만 확정한다.
      await reload();
      await checkpoint?.call('reloaded');
      await _record({...state, 'phase': 'committed'});
      committed = true;
    } on Object {
      try {
        await recover();
        await reload();
      } on Object {
        throw const RestoreRecoveryFailure();
      }
      rethrow;
    }
    // FLOW 9: 확정 이후 정리 실패는 성공한 복원을 실패로 되돌리지 않는다.
    if (committed) {
      await checkpoint?.call('committed');
      try {
        await recover();
      } on Object {
        /* 다음 시작 때 다시 정리한다. */
      }
    }
  }
}

class RestoreRecoveryFailure implements Exception {
  const RestoreRecoveryFailure();
}

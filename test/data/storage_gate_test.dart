import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/local/json_store.dart';
import 'package:mychild_reading/data/local/storage_gate.dart';

void main() {
  test('freeze는 기존 중첩 저장 완료를 기다리고 새로운 쓰기를 거절한다', () async {
    final gate = StorageGate();
    final release = Completer<void>();
    var done = false;
    final old = gate.write(() async {
      await release.future;
      await gate.write(() async {
        done = true;
      });
    });
    final frozen = gate.freeze();
    expect(gate.isBlocked, true);
    await expectLater(gate.write(() async {}), throwsA(isA<AppException>()));
    expect(done, false);
    release.complete();
    await old;
    await frozen;
    expect(done, true);
    gate.thaw();
    await gate.write(() async {});
  });
  test('기존 쓰기 실패도 freeze를 영구 대기시키지 않는다', () async {
    final gate = StorageGate();
    final release = Completer<void>();
    final failed = gate.write(() async {
      await release.future;
      throw StateError('injected');
    });
    final assertion = expectLater(failed, throwsStateError);
    final freeze = gate.freeze();
    release.complete();
    await assertion;
    await freeze;
    gate.thaw();
    await gate.freeze();
    gate.thaw();
  });
  test('JSON map/list 저장과 삭제 모두 동결 중에 원본을 유지한다', () async {
    final temp = await Directory.systemTemp.createTemp('gate-json-');
    try {
      final store = JsonStore(temp);
      await store.writeMap('data.json', {'value': 'old'});
      await store.gate.freeze();
      for (final action in [
        () => store.writeMap('data.json', {'value': 'new'}),
        () => store.writeList('data.json', []),
        () => store.delete('data.json'),
        () => store.deleteDirectory('.'),
      ]) {
        await expectLater(action(), throwsA(isA<AppException>()));
      }
      expect((await store.readMap('data.json'))!['value'], 'old');
    } finally {
      await temp.delete(recursive: true);
    }
  });
}

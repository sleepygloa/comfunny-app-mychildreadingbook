import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:mychild_reading/data/local/json_store.dart';
import 'package:mychild_reading/data/repositories/backup_repository_impl.dart';
import 'package:mychild_reading/data/repositories/content_repository_impl.dart';
import 'package:mychild_reading/data/repositories/recent_playback_repository_impl.dart';
import 'package:mychild_reading/domain/repositories/repositories.dart';
import 'package:mychild_reading/domain/repositories/recent_playback_repository.dart';

import 'music_navigation_test.dart' as fixtures;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/data/services/backup_bundle.dart';
import 'package:mychild_reading/presentation/player/playback_queue.dart';
import 'package:mychild_reading/presentation/settings/backup_view_model.dart';
import 'package:mychild_reading/service_locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mychild_reading/backup_files');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late Directory cache;
  late PlaybackQueue queue;
  late BackupViewModel vm;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('backup-vm-');
    cache = await Directory('${temp.path}/cache').create();
    await registerWith(await Directory('${temp.path}/data').create());
    queue = PlaybackQueue(createPlayer: (_) => throw StateError('unused'));
    vm = BackupViewModel(queue);
    messenger.setMockMethodCallHandler(paths, (_) async => cache.path);
  });
  tearDown(() async {
    vm.dispose();
    queue.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(paths, null);
    await resetLocator();
    await temp.delete(recursive: true);
  });
  test('export validates real bundle, blocks playback, prevents duplicate, cleans job', () async {
    final selected = Completer<void>();
    final finish = Completer<bool>();
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'exportBackup');
      await BackupBundle().inspect(File(call.arguments['path'] as String));
      selected.complete();
      return finish.future;
    });
    final running = vm.run(true);
    await selected.future;
    expect(vm.busy, isTrue);
    expect(queue.canPlay, isFalse);
    await vm.run(true);
    expect(calls, 1);
    finish.complete(true);
    await running;
    expect(vm.message, contains('저장했어요'));
    expect(vm.busy, isFalse);
    expect(queue.canPlay, isTrue);
    expect(
      await Directory('${cache.path}/backup-transfer').list().isEmpty,
      isTrue,
    );
  });
  for (final fail in [false, true]) {
    test(
      'picker ${fail ? 'activity interruption' : 'cancel'} unlocks playback',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async {
          if (fail) throw PlatformException(code: 'activity_closed');
          return null;
        });
        await vm.run(false);
        expect(vm.busy, isFalse);
        expect(queue.canPlay, isTrue);
        expect(vm.message, contains(fail ? '완료하지 못했어요' : '취소했어요'));
      },
    );
  }
  test(
    'inspection rejects corrupt private copy and deletes only copy',
    () async {
      final root = await Directory('${cache.path}/backup-transfer').create();
      final copy = await File('${root.path}/import-test.mcrb')
          .writeAsString('broken');
      final original = await File('${temp.path}/original.mcrb')
          .writeAsString('broken');
      messenger.setMockMethodCallHandler(channel, (_) async => copy.path);
      await vm.run(false);
      expect(vm.message, contains('완료하지 못했어요'));
      expect(await copy.exists(), isFalse);
      expect(await original.readAsString(), 'broken');
      expect(queue.canPlay, isTrue);
    },
  );
  test('unexpected path never deletes user file', () async {
    await Directory('${cache.path}/backup-transfer').create();
    final original = await File('${temp.path}/original.mcrb')
        .writeAsString('private');
    messenger.setMockMethodCallHandler(channel, (_) async => original.path);
    await vm.run(false);
    expect(await original.readAsString(), 'private');
    expect(vm.message, contains('완료하지 못했어요'));
  });
  Future<File> restoreBundle({bool brokenMedia = false}) async {
    final source = await Directory('${temp.path}/restore-source').create();
    final book = fixtures.book('restored');
    await ContentRepositoryImpl(JsonStore(source)).save(book);
    if (!brokenMedia) {
      await File('${source.path}/library/restored/page.jpg')
          .writeAsBytes([1, 2, 3]);
    }
    await RecentPlaybackRepositoryImpl(JsonStore(source))
        .save(RecentPlayback(bookIds: ['restored'], currentId: 'restored'));
    final repo = BackupRepositoryImpl(source);
    final snapshot = Directory('${temp.path}/restore-snapshot');
    await repo.create(snapshot.path);
    final root = await Directory('${cache.path}/backup-transfer')
        .create(recursive: true);
    final output = File('${root.path}/import-restore.mcrb');
    await BackupBundle().pack(snapshot, output, repo);
    return output;
  }

  for (final accept in [false, true]) {
    test('복원 ${accept ? '확인' : '취소'}는 책장과 OS 큐를 일관되게 유지한다', () async {
      final old = fixtures.book('original');
      await sl<ContentRepository>().save(old);
      final imported = await restoreBundle();
      var reloads = 0;
      vm.dispose();
      queue.dispose();
      queue = PlaybackQueue(
        createPlayer: (_) => throw StateError('must not autoplay'),
        resolveBook: (id) => sl<ContentRepository>().getById(id),
        recentRepository: sl<RecentPlaybackRepository>(),
      );
      vm = BackupViewModel(
        queue,
        reloadViews: () async {
          reloads++;
        },
      );
      messenger.setMockMethodCallHandler(channel, (_) async => imported.path);
      await vm.restore((preview) async {
        expect(preview.books, 1);
        expect((await sl<ContentRepository>().getAll()).single.id, 'original');
        expect(queue.canPlay, false);
        return accept;
      });
      expect(
        (await sl<ContentRepository>().getAll()).single.id,
        accept ? 'restored' : 'original',
      );
      expect(reloads, accept ? 1 : 0);
      expect(queue.items.map((b) => b.id), accept ? ['restored'] : []);
      expect(queue.player, isNull);
      expect(queue.canPlay, true);
      expect(sl<JsonStore>().gate.isBlocked, false);
      expect(await imported.exists(), false);
      expect(vm.message, contains(accept ? '복원했어요' : '취소했어요'));
    });
  }
  test('누락 미디어는 사용자 교체 확인 전에 거절한다', () async {
    await sl<ContentRepository>().save(fixtures.book('original'));
    final imported = await restoreBundle(brokenMedia: true);
    messenger.setMockMethodCallHandler(channel, (_) async => imported.path);
    await vm.restore((_) async {
      fail('invalid bundle must not reach confirmation');
    });
    expect((await sl<ContentRepository>().getAll()).single.id, 'original');
    expect(vm.message, contains('복원하지 못했어요'));
    expect(queue.canPlay, true);
  });
  test('새 화면 재조회 실패는 롤백하고 복구 실패는 변경을 잠근다', () async {
    await sl<ContentRepository>().save(fixtures.book('original'));
    final imported = await restoreBundle();
    vm.dispose();
    vm = BackupViewModel(
      queue,
      reloadViews: () async {
        throw StateError('injected');
      },
    );
    messenger.setMockMethodCallHandler(channel, (_) async => imported.path);
    await vm.restore((_) async => true);
    expect((await sl<ContentRepository>().getAll()).single.id, 'original');
    expect(vm.requiresRestart, true);
    expect(sl<JsonStore>().gate.isBlocked, true);
    expect(queue.canPlay, false);
  });
  test('복원 중 OS stop은 새 최근재생목록을 덮어쓰지 않는다', () async {
    final imported = await restoreBundle();
    vm.dispose();
    queue.dispose();
    queue = PlaybackQueue(
      createPlayer: (_) => throw StateError('unused'),
      resolveBook: (id) => sl<ContentRepository>().getById(id),
      recentRepository: sl<RecentPlaybackRepository>(),
    );
    vm = BackupViewModel(
      queue,
      reloadViews: () async {
        await queue.stop();
        await queue.clear();
        expect(sl<JsonStore>().gate.isBlocked, true);
      },
    );
    messenger.setMockMethodCallHandler(channel, (_) async => imported.path);
    await vm.restore((_) async => true);
    expect((await sl<RecentPlaybackRepository>().load()).bookIds, ['restored']);
    expect(queue.items.single.id, 'restored');
    final raw = jsonDecode(
      await File('${temp.path}/data/index/recent_playback.json').readAsString(),
    );
    expect(raw['data']['currentId'], 'restored');
  });
  test('손상된 현재 최근재생목록도 유효한 백업으로 복구할 수 있다', () async {
    final imported = await restoreBundle();
    final current = File('${temp.path}/data/index/recent_playback.json');
    await current.parent.create(recursive: true);
    await current.writeAsString('{broken');
    vm.dispose();
    queue.dispose();
    queue = PlaybackQueue(
      createPlayer: (_) => throw StateError('unused'),
      resolveBook: (id) => sl<ContentRepository>().getById(id),
      recentRepository: sl<RecentPlaybackRepository>(),
    );
    vm = BackupViewModel(queue);
    messenger.setMockMethodCallHandler(channel, (_) async => imported.path);
    await vm.restore((_) async => true);
    expect(vm.requiresRestart, false);
    expect(vm.message, contains('복원했어요'));
    expect((await sl<RecentPlaybackRepository>().load()).bookIds, ['restored']);
    expect(queue.canPlay, true);
  });
}

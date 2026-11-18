import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/app/playback_runtime.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/local/json_store.dart';
import 'package:mychild_reading/data/local/media_storage.dart';
import 'package:mychild_reading/data/repositories/recent_playback_repository_impl.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/repositories/recent_playback_repository.dart';
import 'package:mychild_reading/presentation/player/playback_queue.dart';
import 'package:mychild_reading/presentation/player/player_view_model.dart';

import 'music_navigation_test.dart' show FakeAudio, Events, book, drain;

void main() {
  late Directory dir;
  late List<FakeAudio> engines;
  late PlaybackQueue q;
  late ReadingAudioHandler handler;
  late RecentPlaybackRepositoryImpl recent;
  Completer<Content?>? delayed;
  var released = 0;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('background-reading-');
    engines = [];
    delayed = null;
    released = 0;
    recent = RecentPlaybackRepositoryImpl(JsonStore(dir));
    q = PlaybackQueue(
      recentRepository: recent,
      resolveBook: (id) async =>
          delayed != null ? await delayed!.future : book(id),
      releaseAudio: () async {
        released++;
      },
      createPlayer: (content) {
        final audio = FakeAudio();
        engines.add(audio);
        return PlayerViewModel(
          content: content,
          audioPlayer: audio,
          mediaStorage: MediaStorage(dir),
          readingEventRepository: Events(),
        );
      },
    )..backgroundEnabled = true;
    handler = ReadingAudioHandler(q);
  });
  tearDown(() async {
    handler.detach();
    q.dispose();
    await drain();
    await dir.delete(recursive: true);
  });

  test('백그라운드에서 다음 책까지 이어지고 OS 재생 상태가 같은 큐를 반영한다', () async {
    await q.playAll([book('a'), book('b')]);
    q.setForeground(false);
    expect(q.player!.isPlaying, isTrue);
    engines.first.finish();
    await drain();
    expect(q.currentId, 'b');
    expect(handler.mediaItem.value!.id, 'b');
    expect(handler.playbackState.value.playing, isTrue);
    engines.last.finish();
    await drain();
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
    expect(released, greaterThan(0));
  });

  test('OS 재생 일시정지 건너뛰기 종료가 큐와 일치하며 종료해도 목록은 남는다', () async {
    await q.playAll([book('a'), book('b')]);
    await handler.pause();
    expect(q.player!.isPlaying, isFalse);
    expect(released, 1);
    await handler.play();
    expect(q.player!.isPlaying, isTrue);
    await handler.skipToNext();
    expect(q.currentId, 'b');
    await handler.skipToPrevious();
    expect(q.currentId, 'a');
    await handler.skipToQueueItem(-1);
    expect(q.currentId, 'a');
    await handler.stop();
    expect(q.player, isNull);
    expect(q.items.length, 2);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('늦은 최신본 조회가 OS 일시정지를 무시하고 재개하지 않는다', () async {
    await q.playAll([book('a')]);
    await handler.pause();
    delayed = Completer<Content?>();
    final play = handler.play();
    await drain();
    await handler.pause();
    delayed!.complete(book('a', updated: DateTime(2027)));
    await play;
    expect(q.player!.isPlaying, isFalse);
    expect(engines.length, 1);
    expect(engines.single.calls.length, 1);
  });

  test('중복 OS play는 일시정지로 뒤집히지 않는다', () async {
    await q.playAll([book('a')]);
    await q.pause();
    delayed = Completer<Content?>();
    final first = handler.play();
    final second = handler.play();
    delayed!.complete(book('a'));
    await Future.wait([first, second]);
    expect(q.player!.isPlaying, isTrue);
  });

  test('일시정지 포커스 반환 중 OS play는 반환 완료 뒤에 재생한다', () async {
    final released = Completer<void>();
    final entered = Completer<void>();
    final custom = PlaybackQueue(
      releaseAudio: () {
        entered.complete();
        return released.future;
      },
      createPlayer: (b) => PlayerViewModel(
        content: b,
        audioPlayer: FakeAudio(),
        mediaStorage: MediaStorage(dir),
        readingEventRepository: Events(),
      ),
    )..backgroundEnabled = true;
    await custom.playAll([book('a')]);
    final pausing = custom.pause();
    await entered.future;
    final playing = custom.play();
    await drain();
    expect(custom.player!.isPlaying, isFalse);
    released.complete();
    await Future.wait([pausing, playing]);
    expect(custom.player!.isPlaying, isTrue);
    custom.dispose();
  });

  for (final isNext in [true, false]) {
    test('포커스 반환 중 ${isNext ? '다음' : '이전'} 페이지는 반환 뒤에 시작한다', () async {
      final released = Completer<void>();
      final entered = Completer<void>();
      final page = book('a').pages.single;
      final twoPages = book('a').copyWith(
        pages: [
          page,
          page.copyWith(id: 'second', orderIndex: 1),
        ],
      );
      final custom = PlaybackQueue(
        releaseAudio: () {
          entered.complete();
          return released.future;
        },
        createPlayer: (b) => PlayerViewModel(
          content: b,
          audioPlayer: FakeAudio(),
          mediaStorage: MediaStorage(dir),
          readingEventRepository: Events(),
        ),
      )..backgroundEnabled = true;
      await custom.playAll([twoPages]);
      if (!isNext) await custom.nextPage();
      final initialIndex = custom.player!.index;
      final pausing = custom.pause();
      await entered.future;
      final changing = isNext ? custom.nextPage() : custom.previousPage();
      await drain();
      expect(custom.player!.index, initialIndex);
      expect(custom.player!.isPlaying, isFalse);
      released.complete();
      await Future.wait([pausing, changing]);
      expect(custom.player!.index, isNext ? 1 : 0);
      expect(custom.player!.isPlaying, isTrue);
      custom.dispose();
    });
  }

  test('편집 중에는 OS play 다음책 목록선택이 소리를 시작하지 않는다', () async {
    await q.playAll([book('a'), book('b')]);
    q.setEditing(true);
    await drain();
    await handler.play();
    await handler.skipToNext();
    await handler.skipToQueueItem(1);
    expect(q.currentId, 'a');
    expect(q.player!.isPlaying, isFalse);
    expect(engines.length, 1);
    q.setEditing(false);
    expect(q.player!.isPlaying, isFalse);
    await handler.play();
    expect(q.player!.isPlaying, isTrue);
  });

  test('UI 일시정지도 오디오 포커스를 반환한다', () async {
    await q.playAll([book('a')]);
    await q.toggle();
    expect(q.player!.isPlaying, isFalse);
    expect(released, 1);
  });

  test('최근 목록과 순서를 디스크에서 복원하지만 자동 재생하지 않는다', () async {
    await q.playAll([book('a'), book('b')]);
    await q.reorder(1, 0);
    final saved = await recent.load();
    expect(saved.bookIds, ['b', 'a']);
    expect(saved.currentId, 'a');
    final restored = PlaybackQueue(
      recentRepository: RecentPlaybackRepositoryImpl(JsonStore(dir)),
      resolveBook: (id) async => book(id),
      createPlayer: (_) => throw StateError('복원만으로 오디오 생성 금지'),
    );
    await restored.restoreRecent();
    await restored.restoreRecent();
    expect(restored.items.map((b) => b.id), ['b', 'a']);
    expect(restored.currentId, 'a');
    expect(restored.player, isNull);
    restored.dispose();
  });

  test('최근 목록에서 삭제된 책을 제외하고 최신 제목을 사용한다', () async {
    await recent.save(
      RecentPlayback(bookIds: ['missing', 'a'], currentId: 'missing'),
    );
    final restored = PlaybackQueue(
      recentRepository: recent,
      resolveBook: (id) async =>
          id == 'missing' ? null : book(id).copyWith(title: '새 제목'),
      createPlayer: (_) => throw StateError('오디오 생성 금지'),
    );
    await restored.restoreRecent();
    expect(restored.items.single.title, '새 제목');
    expect(restored.currentId, isNull);
    restored.dispose();
  });

  for (final json in [
    '{broken',
    '{"schemaVersion":999,"data":{}}',
    '{"bookIds":["../outside"]}',
    '{"bookIds":["a","a"]}',
  ]) {
    test('손상 최근 목록은 덮어쓰지 않는다 $json', () async {
      final f = File('${dir.path}/${RecentPlaybackRepositoryImpl.path}');
      await f.parent.create();
      await f.writeAsString(json);
      await expectLater(
        recent.save(RecentPlayback(bookIds: ['a'])),
        throwsA(isA<AppException>()),
      );
      expect(await f.readAsString(), json);
    });
  }
}

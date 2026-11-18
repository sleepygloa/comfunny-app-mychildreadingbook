import 'dart:async';
import 'package:mychild_reading/domain/entities/reading_position.dart';
import 'package:mychild_reading/domain/repositories/reading_workspace_repositories.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/data/local/media_storage.dart';
import 'package:mychild_reading/data/services/page_audio_player.dart';
import 'package:mychild_reading/domain/entities/audio_track.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/reading_event.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/domain/repositories/repositories.dart';
import 'package:mychild_reading/presentation/player/player_view_model.dart';

/// [PlayerViewModel] 검증.
///
/// **fake 오디오 엔진**으로 갈아끼워 플러그인 없이 돈다. 이게 가능한 이유는
/// [PageAudioPlayer] 를 인터페이스로 뺐기 때문이다 — `audioplayers`·`flutter_tts` 는
/// 플랫폼 채널이라 위젯 테스트에서 쓸 수 없다.
class _FakeAudioPlayer implements PageAudioPlayer {
  @override
  void Function()? onComplete;
  @override
  void Function(String message)? onError;

  bool _playing = false;
  @override
  bool get isPlaying => _playing;

  /// 무엇을 어떤 순서로 재생했나. 검증의 핵심 기록이다.
  final List<String> calls = [];

  @override
  Future<void> playFile(String absolutePath) async {
    calls.add('file:$absolutePath');
    _playing = true;
  }

  @override
  Future<void> speak(String text) async {
    calls.add('tts:$text');
    _playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _playing = false;
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    _playing = true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _playing = false;
  }

  @override
  Future<void> dispose() async => calls.add('dispose');

  /// 오디오가 끝난 것을 흉내낸다 — 자동 넘김의 방아쇠.
  void finish() {
    _playing = false;
    onComplete?.call();
  }

  void fail(String message) {
    _playing = false;
    onError?.call(message);
  }
}

class _FakeReadingEventRepository implements ReadingEventRepository {
  final List<ReadingEvent> saved = [];

  @override
  Future<List<ReadingEvent>> query({
    DateTime? from,
    DateTime? to,
    String? childId,
  }) async =>
      saved;

  @override
  Future<void> save(ReadingEvent event) async {
    // 업서트 흉내 — 같은 id 면 교체
    saved
      ..removeWhere((e) => e.id == event.id)
      ..add(event);
  }
}

class _DelayedPosition implements ReadingPositionRepository {
  final pending = Completer<ReadingPosition?>();
  final saving = Completer<void>();
  bool delaySave = false;
  @override Future<ReadingPosition?> getById(String id) => pending.future;
  @override Future<void> save(ReadingPosition position) async { if(delaySave) await saving.future; }
  @override Future<void> delete(String id) async {}
}

void main() {
  late Directory tmp;
  late MediaStorage media;
  late _FakeAudioPlayer audio;
  late _FakeReadingEventRepository events;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mcr_player_');
    media = MediaStorage(tmp);
    audio = _FakeAudioPlayer();
    events = _FakeReadingEventRepository();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  AudioTrack recording(String path) => AudioTrack(
        id: 'rec-$path',
        source: AudioSource.parentRecording,
        path: path,
        createdAt: DateTime.utc(2026, 9, 1),
      );

  BookPage page(
    int order, {
    String? text,
    List<AudioTrack> tracks = const [],
  }) =>
      BookPage(
        id: 'p$order',
        orderIndex: order,
        imagePath: 'pages/page_00$order.jpg',
        text: text,
        tracks: tracks,
      );

  Content book(List<BookPage> pages) => Content(
        id: 'c1',
        type: ContentType.pagedBook,
        title: '테스트 책',
        pages: pages,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

  PlayerViewModel vmOf(
    Content content, {
    String? childId,
    DateTime Function()? now,
  }) =>
      PlayerViewModel(
        content: content,
        audioPlayer: audio,
        mediaStorage: media,
        readingEventRepository: events,
        childId: childId,
        now: now,
      );

  test('위치 조회 중 일시정지하면 뒤늦게 재생하지 않는다', () async {
    final positions = _DelayedPosition();
    final vm=PlayerViewModel(content:book([page(0,text:'안녕')]),audioPlayer:audio,
      mediaStorage:media,readingEventRepository:events,positionRepository:positions);
    final started=vm.start(); await vm.pause(); positions.pending.complete(null);
    await started; expect(audio.calls.where((c)=>c.startsWith('tts:')),isEmpty); vm.dispose();
  });
  test('위치 저장 중 화면을 닫으면 뒤늦게 재생하지 않는다', () async {
    final positions=_DelayedPosition()..delaySave=true;
    positions.pending.complete(null);
    final vm=PlayerViewModel(content:book([page(0,text:'안녕')]),audioPlayer:audio,
      mediaStorage:media,readingEventRepository:events,positionRepository:positions);
    final started=vm.start(); await Future<void>.delayed(Duration.zero);
    await vm.leave(); vm.dispose(); positions.saving.complete(); await started;
    expect(audio.calls.where((c)=>c.startsWith('tts:')),isEmpty);
  });

  group('페이지 순서', () {
    test('저장 순서가 아니라 orderIndex 로 정렬한다', () {
      // 일부러 역순으로 넣는다 — 리오더 도중 앱이 죽으면 실제로 이런 상태가 된다.
      final vm = vmOf(book([page(2), page(0), page(1)]));
      expect(vm.pages.map((p) => p.orderIndex), [0, 1, 2]);
    });
  });

  group('start — 재생 시작', () {
    test('파일 트랙이 있으면 파일을 재생한다', () async {
      final vm = vmOf(book([page(0, tracks: [recording('audio/p0.m4a')])]));
      await vm.start();

      expect(audio.calls.single, endsWith('audio/p0.m4a'));
      expect(audio.calls.single, startsWith('file:'));
      expect(vm.isPlaying, isTrue);
    });

    test('파일이 없고 텍스트만 있으면 기기 TTS 로 읽는다', () async {
      final vm = vmOf(book([page(0, text: '옛날 옛적에')]));
      await vm.start();

      // 트랙 객체가 없어도 텍스트만 있으면 읽을 수 있다 — 최후의 폴백.
      expect(audio.calls.single, 'tts:옛날 옛적에');
      expect(vm.isPlaying, isTrue);
    });

    test('부모 녹음이 기기 TTS 보다 우선한다', () async {
      final vm = vmOf(book([
        page(0, text: '텍스트도 있다', tracks: [recording('audio/p0.m4a')]),
      ]));
      await vm.start();

      // 이 앱의 본질은 부모 목소리다.
      expect(audio.calls.single, startsWith('file:'));
    });

    test('텍스트도 트랙도 없으면 재생하지 않고 멈춰 있는다', () async {
      final vm = vmOf(book([page(0)]));
      await vm.start();

      // 그림만 보는 페이지일 수 있다. 사용자가 직접 넘기게 둔다.
      expect(audio.calls, isEmpty);
      expect(vm.isPlaying, isFalse);
    });

    test('페이지가 없으면 안내하고 재생하지 않는다', () async {
      final vm = vmOf(book(const []));
      await vm.start();

      expect(vm.errorMessage, contains('읽을 페이지가 없습니다'));
      expect(audio.calls, isEmpty);
    });
  });

  group('자동 넘김 — 오디오 완료가 방아쇠', () {
    test('완료되면 다음 페이지를 읽는다', () async {
      final vm = vmOf(book([page(0, text: '첫장'), page(1, text: '둘째장')]));
      await vm.start();
      expect(vm.index, 0);

      audio.finish();
      await Future<void>.delayed(Duration.zero);

      expect(vm.index, 1);
      expect(audio.calls.last, 'tts:둘째장');
    });

    test('마지막 페이지가 끝나면 완독으로 마친다', () async {
      final vm = vmOf(book([page(0, text: '끝')]));
      await vm.start();

      audio.finish();
      await Future<void>.delayed(Duration.zero);

      expect(vm.isFinished, isTrue);
      expect(vm.isPlaying, isFalse);
    });

    test('책 반복이면 처음으로 돌아간다', () async {
      final vm = vmOf(book([page(0, text: 'A'), page(1, text: 'B')]))
        ..setRepeatMode(PlayerRepeatMode.book);
      await vm.start();

      audio.finish(); // → 1
      await Future<void>.delayed(Duration.zero);
      audio.finish(); // 마지막 → 0 으로
      await Future<void>.delayed(Duration.zero);

      expect(vm.index, 0);
      expect(vm.isFinished, isFalse);
    });

    test('한 장 반복이면 같은 페이지를 다시 읽는다', () async {
      final vm = vmOf(book([page(0, text: 'A'), page(1, text: 'B')]))
        ..setRepeatMode(PlayerRepeatMode.page);
      await vm.start();

      audio.finish();
      await Future<void>.delayed(Duration.zero);

      // 아이가 특정 장면을 계속 보고 싶어할 때.
      expect(vm.index, 0);
      expect(audio.calls.where((c) => c == 'tts:A').length, 2);
    });
  });

  group('수동 조작', () {
    test('next / previous 로 이동한다', () async {
      final vm = vmOf(book([page(0, text: 'A'), page(1, text: 'B')]));
      await vm.start();

      await vm.next();
      expect(vm.index, 1);
      expect(vm.hasNext, isFalse);

      await vm.previous();
      expect(vm.index, 0);
      expect(vm.hasPrevious, isFalse);
    });

    test('경계를 넘지 않는다', () async {
      final vm = vmOf(book([page(0, text: 'A')]));
      await vm.start();

      await vm.previous();
      await vm.next();
      expect(vm.index, 0);
    });

    test('jumpTo 로 특정 페이지로 간다 — 범위 밖은 무시', () async {
      final vm = vmOf(book([page(0, text: 'A'), page(1, text: 'B'), page(2, text: 'C')]));
      await vm.start();

      await vm.jumpTo(2);
      expect(vm.index, 2);

      await vm.jumpTo(99);
      await vm.jumpTo(-1);
      expect(vm.index, 2);
    });

    test('pause 로 멈춘다', () async {
      final vm = vmOf(book([page(0, text: 'A')]));
      await vm.start();

      await vm.pause();
      expect(vm.isPlaying, isFalse);
      expect(audio.calls.last, 'pause');
    });

    test('TTS 페이지는 resume 이 처음부터 다시 읽는다', () async {
      final vm = vmOf(book([page(0, text: 'A')]));
      await vm.start();
      await vm.pause();

      await vm.resume();

      // 기기 TTS 는 이어재생이 없다 — 다시 읽는 편이 예측 가능하다.
      expect(audio.calls.last, 'tts:A');
    });

    test('파일 페이지는 resume 이 이어재생한다', () async {
      final vm = vmOf(book([page(0, tracks: [recording('audio/p0.m4a')])]));
      await vm.start();
      await vm.pause();

      await vm.resume();
      expect(audio.calls.last, 'resume');
    });
  });

  group('진행률', () {
    test('페이지 수에 따라 계산된다', () async {
      final vm = vmOf(book([page(0, text: 'A'), page(1, text: 'B')]));
      await vm.start();

      expect(vm.progress, 0.5);
      await vm.next();
      expect(vm.progress, 1.0);
    });

    test('페이지가 없으면 0', () {
      expect(vmOf(book(const [])).progress, 0);
    });
  });

  group('트랙 전환', () {
    test('선택 가능한 종류를 모은다', () async {
      final vm = vmOf(book([
        page(0, text: '텍스트', tracks: [recording('audio/p0.m4a')]),
        page(1, tracks: [
          AudioTrack(
            id: 'ai',
            source: AudioSource.aiClonedVoice,
            path: 'audio/p1_ai.mp3',
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ]),
      ]));

      expect(
        vm.availableSources,
        containsAll([
          AudioSource.parentRecording,
          AudioSource.aiClonedVoice,
          AudioSource.deviceTts, // 텍스트가 있으므로 항상 가능
        ]),
      );
    });

    test('파일 없는 트랙은 선택지에 넣지 않는다', () {
      final vm = vmOf(book([
        page(0, tracks: [
          AudioTrack(
            id: 'broken',
            source: AudioSource.parentRecording,
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        ]),
      ]));

      // 파일이 없으면 재생해도 무음이다.
      expect(vm.availableSources, isEmpty);
    });

    test('선택하면 즉시 현재 페이지를 새 목소리로 다시 읽는다', () async {
      final vm = vmOf(book([
        page(0, text: '텍스트', tracks: [recording('audio/p0.m4a')]),
      ]));
      await vm.start();
      expect(audio.calls.last, startsWith('file:'));

      await vm.selectSource(AudioSource.deviceTts);

      // "바꿨는데 다음 페이지부터 적용" 은 기대와 다르다.
      expect(audio.calls.last, 'tts:텍스트');
      expect(vm.preferredSource, AudioSource.deviceTts);
    });

    test('같은 종류를 다시 선택하면 아무 일도 하지 않는다', () async {
      final vm = vmOf(book([page(0, text: 'A')]));
      await vm.start();
      final before = audio.calls.length;

      await vm.selectSource(null);
      expect(audio.calls.length, before);
    });
  });

  group('오디오 오류', () {
    test('오류를 사용자 문구로 보여주고 멈춘다', () async {
      final vm = vmOf(book([page(0, text: 'A')]));
      await vm.start();

      audio.fail('소리를 재생할 수 없습니다.');

      expect(vm.errorMessage, '소리를 재생할 수 없습니다.');
      expect(vm.isPlaying, isFalse);
    });

    test('clearError 로 닫는다', () async {
      final vm = vmOf(book([page(0, text: 'A')]));
      await vm.start();
      audio.fail('오류');

      vm.clearError();
      expect(vm.errorMessage, isNull);
    });
  });

  group('독서 기록 — M4 통계의 원천', () {
    test('재생을 시작하면 기록이 생긴다', () async {
      final vm = vmOf(book([page(0, text: 'A')]), childId: 'ch1');
      await vm.start();

      expect(events.saved.length, 1);
      expect(events.saved.single.contentId, 'c1');
      expect(events.saved.single.childId, 'ch1');
      expect(events.saved.single.isClosed, isFalse); // 아직 진행 중
    });

    test('완독하면 completed 로 닫힌다', () async {
      var clock = DateTime.utc(2026, 9, 12, 20, 0, 0);
      final vm = vmOf(book([page(0, text: 'A')]), now: () => clock);
      await vm.start();

      clock = DateTime.utc(2026, 9, 12, 20, 3, 30);
      audio.finish();
      await Future<void>.delayed(Duration.zero);

      final event = events.saved.single;
      expect(event.completed, isTrue);
      expect(event.isClosed, isTrue);
      expect(event.durationSec, 210); // 3분 30초
    });

    test('중간에 나가면 completed=false 로 닫힌다', () async {
      var clock = DateTime.utc(2026, 9, 12, 20, 0, 0);
      final vm = vmOf(book([page(0, text: 'A'), page(1, text: 'B')]),
          now: () => clock);
      await vm.start();

      clock = DateTime.utc(2026, 9, 12, 20, 0, 45);
      await vm.leave();

      final event = events.saved.single;
      expect(event.completed, isFalse);
      expect(event.durationSec, 45);
      expect(audio.calls.contains('stop'), isTrue);
    });

    test('기록은 하나만 열린다 (start 를 두 번 불러도)', () async {
      final vm = vmOf(book([page(0, text: 'A')]));
      await vm.start();
      await vm.start();

      expect(events.saved.length, 1);
    });

    test('leave 를 두 번 불러도 안전하다', () async {
      final vm = vmOf(book([page(0, text: 'A')]));
      await vm.start();

      await vm.leave();
      await vm.leave();

      expect(events.saved.length, 1);
    });
  });
}

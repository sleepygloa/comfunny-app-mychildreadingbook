import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/data/services/device_tts_service.dart';
import 'package:mychild_reading/data/services/page_audio_player.dart';

class FileBackend implements FileAudioBackend {
  final events = StreamController<void>.broadcast();
  Completer<void>? release;
  final entered = Completer<void>();
  Completer<void>? resumeRelease;
  final resumeEntered = Completer<void>();
  bool playing = false;
  int plays = 0;
  @override
  Stream<void> get onComplete => events.stream;
  @override
  Future<void> play(String path) async {
    plays++;
    if (!entered.isCompleted) entered.complete();
    await release?.future;
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> resume() async {
    if (!resumeEntered.isCompleted) resumeEntered.complete();
    await resumeRelease?.future;
    playing = true;
  }

  @override
  Future<void> dispose() async {
    await events.close();
  }
}

class FakeTts extends DeviceTtsService {
  int disposed = 0;
  int stopped = 0;
  int spoken = 0;
  @override
  Future<void> speak(String text) async {
    spoken++;
  }

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {
    stopped++;
  }

  @override
  Future<void> dispose() async {
    disposed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('오디오 포커스 거절은 파일 재생을 시작하지 않는다', () async {
    final backend = FileBackend();
    final audio = PageAudioPlayerImpl(
      tts: FakeTts(),
      backend: backend,
      prepareAudio: () async => false,
    );
    String? error;
    audio.onError = (message) => error = message;
    await audio.playFile('test.m4a');
    expect(backend.plays, 0);
    expect(error, isNotNull);
    await audio.dispose();
  });

  test('오디오 포커스 준비 중 정지는 늦은 재생을 차단한다', () async {
    final entered = Completer<void>();
    final ready = Completer<bool>();
    final backend = FileBackend();
    final audio = PageAudioPlayerImpl(
      tts: FakeTts(),
      backend: backend,
      prepareAudio: () {
        entered.complete();
        return ready.future;
      },
    );
    final play = audio.playFile('test.m4a');
    await entered.future;
    final stop = audio.stop();
    ready.complete(true);
    await Future.wait([play, stop]);
    expect(backend.plays, 0);
    expect(audio.isPlaying, isFalse);
    await audio.dispose();
  });

  test('파일 시작 대기 중 pause는 늦은 재생을 멈추고 다시 시작할 수 있다', () async {
    final backend = FileBackend()..release = Completer<void>();
    final audio = PageAudioPlayerImpl(tts: FakeTts(), backend: backend);
    final play = audio.playFile('test.m4a');
    await backend.entered.future;
    final pause = audio.pause();
    backend.release!.complete();
    await Future.wait([play, pause]);
    expect(backend.playing, isFalse);
    await audio.resume();
    expect(backend.playing, isTrue);
    expect(backend.plays, 2);
    await audio.dispose();
  });
  test('이전 파일 시작을 기다린 stop이 끝난 뒤에 다음 재생을 시작한다', () async {
    final backend = FileBackend()..release = Completer<void>();
    final audio = PageAudioPlayerImpl(tts: FakeTts(), backend: backend);
    final play = audio.playFile('old.m4a');
    await backend.entered.future;
    final stop = audio.stop();
    backend.release!.complete();
    await Future.wait([play, stop]);
    expect(backend.playing, isFalse);
    await audio.playFile('new.m4a');
    expect(backend.playing, isTrue);
    await audio.dispose();
  });
  test('공유 TTS 완료 콜백은 새 소유자에게 전달되고 이전 해제가 엔진을 해제하지 않는다', () async {
    final tts = FakeTts();
    final old = PageAudioPlayerImpl(tts: tts, backend: FileBackend());
    final next = PageAudioPlayerImpl(tts: tts, backend: FileBackend());
    var oldDone = 0;
    var nextDone = 0;
    old.onComplete = () => oldDone++;
    next.onComplete = () => nextDone++;
    await old.speak('old');
    await old.stop();
    await next.speak('new');
    final stops = tts.stopped;
    await old.dispose();
    expect(tts.disposed, 0);
    expect(tts.stopped, stops);
    tts.onComplete!();
    expect(oldDone, 0);
    expect(nextDone, 1);
    await next.dispose();
  });
  test('파일 이어재생 대기 중 pause도 늦은 시작을 취소한다', () async {
    final backend = FileBackend();
    final audio = PageAudioPlayerImpl(tts: FakeTts(), backend: backend);
    await audio.playFile('test.m4a');
    await audio.pause();
    backend.resumeRelease = Completer<void>();
    final resume = audio.resume();
    await backend.resumeEntered.future;
    final pause = audio.pause();
    backend.resumeRelease!.complete();
    await Future.wait([resume, pause]);
    expect(backend.playing, isFalse);
    await audio.dispose();
  });
}

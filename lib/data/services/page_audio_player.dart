import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'device_tts_service.dart';

/// 페이지 오디오 재생 창구.
///
/// **왜 추상화하나:** 이 앱은 두 종류를 재생한다 —
/// ① 파일(부모 녹음·AI 합성) ② **런타임 TTS**(기기 내장, 파일이 없다).
/// 재생 주체가 다른데 플레이어는 "이 페이지를 소리내라" 만 알면 된다.
///
/// 부수 효과로 **ViewModel 을 플러그인 없이 테스트할 수 있다** — fake 로 갈아끼운다.
/// `audioplayers`·`flutter_tts` 는 플랫폼 채널이라 위젯 테스트에서 못 쓴다.
abstract class PageAudioPlayer {
  /// 재생이 끝났을 때. **자동 페이지 넘김의 신호다.**
  ///
  /// 기기 TTS 는 길이를 미리 알 수 없어 타이머로 예측할 수 없다 — 이벤트에 의존해야 한다.
  void Function()? onComplete;

  /// 재생 실패. 파일이 깨졌거나 TTS 엔진이 해당 언어를 지원하지 않는 경우.
  void Function(String message)? onError;

  bool get isPlaying;

  /// 파일을 재생한다. [absolutePath] 는 절대 경로.
  Future<void> playFile(String absolutePath);

  /// 텍스트를 기기 TTS 로 읽는다. 파일을 만들지 않는다.
  Future<void> speak(String text);

  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

/// 실제 구현 — `audioplayers`(파일) + [DeviceTtsService](런타임 TTS).
///
/// 두 엔진 중 **하나만 활성**이다. 페이지를 넘기면 이전 것을 멈추고 새로 시작한다.
/// 동시에 울리면 아이에게 혼란스럽다.
/// 플랫폼 호출을 지연시키는 회귀 테스트에서도 같은 오디오 조정 로직을 쓴다.
abstract interface class FileAudioBackend {
  Stream<void> get onComplete;
  Future<void> play(String path);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

class _PluginFileAudio implements FileAudioBackend {
  _PluginFileAudio(this.player);
  final AudioPlayer player;
  @override
  Stream<void> get onComplete => player.onPlayerComplete;
  @override
  Future<void> play(String path) => player.play(DeviceFileSource(path));
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> resume() => player.resume();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> dispose() => player.dispose();
}

class PageAudioPlayerImpl implements PageAudioPlayer {
  PageAudioPlayerImpl({
    required this.tts,
    this.prepareAudio,
    AudioPlayer? filePlayer,
    FileAudioBackend? backend,
  }) : _file = backend ?? _PluginFileAudio(filePlayer ?? AudioPlayer()) {
    _completion = _file.onComplete.listen((_) {
      if (_disposed || _activeEngine != _Engine.file) return;
      _activeEngine = _Engine.none;
      onComplete?.call();
    });
  }
  final FileAudioBackend _file;
  final Future<bool> Function()? prepareAudio;
  // 앱 수명 동안 하나의 FlutterTts 채널을 공유한다. 콜백은 발화할 때 소유권을 얻는다.
  final DeviceTtsService tts;
  late final StreamSubscription<void> _completion;
  _Engine _activeEngine = _Engine.none;
  int _generation = 0;
  String? _lastFile;
  bool _disposed = false;
  Future<void> _pending = Future.value();
  @override
  void Function()? onComplete;
  @override
  void Function(String)? onError;
  @override
  bool get isPlaying => _activeEngine != _Engine.none;

  Future<void> _start(_Engine engine, Future<void> Function() action) {
    final generation = ++_generation;
    final next = _pending.then((_) async {
      if (_disposed || generation != _generation) return;
      try {
        await _file.stop();
        await tts.stop();
        _activeEngine = _Engine.none;
        if (_disposed || generation != _generation) return;
        if (prepareAudio != null && !await prepareAudio!()) {
          onError?.call('다른 소리 사용이 끝난 뒤 다시 재생해 주세요.');
          return;
        }
        if (_disposed || generation != _generation) return;
        _activeEngine = engine;
        if (engine == _Engine.tts) {
          tts.onComplete = () {
            if (_disposed ||
                generation != _generation ||
                _activeEngine != _Engine.tts) {
              return;
            }
            _activeEngine = _Engine.none;
            onComplete?.call();
          };
          tts.onError = (message) {
            if (_disposed || generation != _generation) return;
            _activeEngine = _Engine.none;
            onError?.call(message);
          };
        }
        await action();
        if (_disposed || generation != _generation) {
          await _file.stop();
          if (engine == _Engine.tts) await tts.stop();
          _activeEngine = _Engine.none;
        }
      } on Object {
        _activeEngine = _Engine.none;
        if (!_disposed && generation == _generation) {
          onError?.call('소리를 재생하지 못했어요. 녹음이나 오프라인 음성을 확인해 주세요.');
        }
      }
    });
    _pending = next;
    return next;
  }

  @override
  Future<void> playFile(String path) {
    _lastFile = path;
    return _start(_Engine.file, () => _file.play(path));
  }

  @override
  Future<void> speak(String text) => _start(_Engine.tts, () => tts.speak(text));
  @override
  Future<void> pause() async {
    _generation++;
    await tts.pause();
    await _file.pause();
    await _pending;
  }

  @override
  Future<void> resume() async {
    if (_disposed) return;
    if (_activeEngine == _Engine.file) {
      final generation = ++_generation;
      final next = _pending.then((_) async {
        if (_disposed || generation != _generation) return;
        try {
          if (prepareAudio != null && !await prepareAudio!()) {
            onError?.call('다른 소리 사용이 끝난 뒤 다시 재생해 주세요.');
            return;
          }
          if (_disposed || generation != _generation) return;
          await _file.resume();
          if (_disposed || generation != _generation) {
            await _file.stop();
            _activeEngine = _Engine.none;
          }
        } on Object {
          _activeEngine = _Engine.none;
          if (!_disposed && generation == _generation) {
            onError?.call('소리를 이어 재생하지 못했어요. 다시 재생해 주세요.');
          }
        }
      });
      _pending = next;
      await next;
    } else if (_lastFile != null) {
      await playFile(_lastFile!);
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await tts.stop();
    await _file.stop();
    await _pending;
    _activeEngine = _Engine.none;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    onComplete = null;
    onError = null;
    await _pending;
    await _completion.cancel();
    await _file.dispose();
    // 공유 TTS 해제는 DI가 담당한다. 이전 책의 늦은 해제가 새 책을 멈추면 안 된다.
  }
}

enum _Engine { none, file, tts }

import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import '../../core/app_logger.dart';

/// 기기 내장 TTS. **OS 엔진이 런타임에 합성한다** — 파일을 만들지 않는다.
///
/// 설치된 오프라인 한국어 음성을 확인한 기기에서만 사용한다.
/// 사용할 수 없으면 부모 직접 녹음으로 안내한다.
///
/// 네트워크가 필요하지 않은 음성만 확인 후 선택하여 책 본문이 기기 밖으로
/// 나가지 않는다 — 아동 앱의 전제다(`[A-06-7]` · [1_DESIGN ADR-4]).
class DeviceTtsService {
  DeviceTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;
  bool _speaking = false;

  /// 지금 말하고 있나. 플레이어가 중복 재생을 막는 데 쓴다.
  bool get isSpeaking => _speaking;

  /// 재생이 끝났을 때 호출된다. 페이지 자동 넘김의 신호다.
  ///
  /// 왜 콜백인가: 기기 TTS 는 **길이를 미리 알 수 없다**(파일이 아니라 런타임 합성).
  /// 타이머로 예측할 수 없으므로 완료 이벤트에 의존해야 한다.
  void Function()? onComplete;

  /// 오류 발생 시. 엔진이 해당 언어를 지원하지 않는 경우 등.
  void Function(String message)? onError;

  /// 한 번만 실행되는 초기화. 언어·속도를 세팅하고 콜백을 연결한다.
  ///
  /// 왜 지연 초기화인가: 생성 시점에 하면 앱 기동이 느려지고, TTS 를 쓰지 않는
  /// 사용자(부모 녹음만 쓰는 경우)에게 불필요한 비용이 된다.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    // 아이가 듣는다. 기본 속도를 성인 기준보다 느리게 잡는다.
    if (!await isKoreanAvailable()) {
      throw StateError('오프라인 한국어 음성을 확인할 수 없습니다. 직접 녹음을 사용해 주세요.');
    }
    await _tts.setSpeechRate(defaultSpeechRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    _tts.setCompletionHandler(() {
      _speaking = false;
      onComplete?.call();
    });
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((dynamic message) {
      _speaking = false;
      final text = message?.toString() ?? '알 수 없는 오류';
      AppLogger.w('기기 TTS 오류: $text');
      onError?.call(text);
    });

    _initialized = true;
  }

  /// [text] 를 읽는다. 이미 말하고 있으면 **먼저 멈춘다**.
  ///
  /// 왜 멈추고 시작하나: 페이지를 빨리 넘기면 이전 페이지 음성과 겹친다.
  /// 겹친 소리는 아이에게 혼란스럽다.
  Future<void> speak(String text) async {
    if (_disposed) return;
    final generation = ++_generation;
    final trimmed = text.trim();
    // FLOW 1: 빈 텍스트는 조용히 통과 — 텍스트 없는 페이지에서 오류를 띄우지 않는다
    if (trimmed.isEmpty) {
      onComplete?.call();
      return;
    }
    // FLOW 2: 초기화 보장
    await _ensureInitialized();
    // FLOW 3: 진행 중인 재생 중단
    if (_disposed || generation != _generation) return;
    if (_speaking) await _tts.stop();
    if (_disposed || generation != _generation) return;
    // FLOW 9: 합성 시작
    _speaking = true;
    await _tts.speak(trimmed);
    if (_disposed || generation != _generation) {
      await _tts.stop();
      _speaking = false;
    }
  }

  Future<void> stop() async {
    _generation++;
    if (!_initialized) return;
    await _tts.stop();
    _speaking = false;
  }

  Future<void> pause() async {
    _generation++;
    if (!_initialized) return;
    await _tts.pause();
    _speaking = false;
  }

  /// 재생 속도를 바꾼다. 0.0~1.0 범위로 잘라낸다.
  ///
  /// 왜 잘라내나: 플랫폼마다 허용 범위가 달라 범위를 넘기면 조용히 무시되거나
  /// 예외가 난다. 호출자가 매번 검증하게 하지 않는다.
  Future<void> setSpeechRate(double rate) async {
    await _ensureInitialized();
    final clamped = rate.clamp(minSpeechRate, maxSpeechRate);
    await _tts.setSpeechRate(clamped);
  }

  /// 이 기기가 한국어를 지원하나. 지원하지 않으면 UI 에서 안내해야 한다.
  ///
  /// 기기·OS 버전마다 설치된 음성이 다르다 — 구형 안드로이드는 한국어가 없을 수 있다.
  Future<bool> isKoreanAvailable() async {
    // Android 플러그인의 network_required=0인 설치 음성만 선택한다.
    // iOS는 오프라인 확인 계약이 아직 없으므로 보수적으로 녹음을 안내한다.
    if (!Platform.isAndroid) return false;
    try {
      final voices = await _tts.getVoices;
      if (voices is! List) return false;
      for (final voice in voices.whereType<Map>()) {
        if (voice['network_required'].toString() == '0' &&
            voice['locale'].toString().replaceAll('_', '-').startsWith('ko-') &&
            voice['name'] is String) {
          final result = await _tts.setVoice({
            'name': voice['name'] as String,
            'locale': voice['locale'].toString(),
          });
          return result == 1;
        }
      }
    } on Object {
      AppLogger.w('오프라인 기기 음성을 확인하지 못했습니다');
    }
    return false;
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    onComplete = null;
    onError = null;
    if (_initialized) await _tts.stop();
  }

  /// 아이용 기본 속도. 성인 기준(0.5)보다 느리다.
  static const double defaultSpeechRate = 0.4;
  static const double minSpeechRate = 0.1;
  static const double maxSpeechRate = 1.0;
}

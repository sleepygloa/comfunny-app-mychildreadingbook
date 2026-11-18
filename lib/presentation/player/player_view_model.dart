import '../../domain/entities/reading_position.dart';
import '../../domain/repositories/reading_workspace_repositories.dart';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_logger.dart';
import '../../core/error_codes.dart';
import '../../data/local/media_storage.dart';
import '../../data/services/page_audio_player.dart';
import '../../domain/entities/book_page.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/reading_event.dart';
import '../../domain/enums/enums.dart';
import '../../domain/repositories/repositories.dart';

/// 반복 모드.
enum PlayerRepeatMode {
  /// 끝까지 읽으면 멈춘다.
  none,

  /// 책 전체를 처음부터 다시.
  book,

  /// **한 페이지만 반복.** 아이가 특정 장면을 계속 보고 싶어할 때.
  page,
}

/// 통합 플레이어 상태.
///
/// 하는 일 3가지:
/// 1. 페이지 순차 재생 + **오디오 완료 시 자동 넘김**
/// 2. 트랙 선택 — 부모녹음/AI/기기TTS 중 무엇으로 들려줄지
/// 3. **[ReadingEvent] 기록** (통계 화면은 M4 지만 데이터는 지금부터 쌓는다)
class PlayerViewModel extends ChangeNotifier {
  PlayerViewModel({
    required this.content,
    required PageAudioPlayer audioPlayer,
    required MediaStorage mediaStorage,
    required ReadingEventRepository readingEventRepository,
    this.childId,
    this.positionRepository,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _player = audioPlayer,
       _media = mediaStorage,
       _events = readingEventRepository,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now {
    // 오디오가 끝나면 다음 페이지로. 기기 TTS 는 길이를 알 수 없어 이벤트에 의존한다.
    _player.onComplete = _onAudioComplete;
    _player.onError = _onAudioError;
  }

  /// 재생 대상. 재생 중 바뀌지 않는 불변 입력이다.
  final Content content;
  void Function()? onBookComplete;
  final ReadingPositionRepository? positionRepository;
  final PageAudioPlayer _player;
  final MediaStorage _media;
  final ReadingEventRepository _events;
  final Uuid _uuid;
  final DateTime Function() _now;

  /// 누가 듣고 있나. 다자녀(M2) 전에는 `null`.
  final String? childId;

  // ── 상태 ─────────────────────────────────────────────────
  int _index = 0;
  int _generation = 0;
  bool _active = true;
  bool _disposed = false;
  bool _audioStarted = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool _playing = false;
  bool _finished = false;
  PlayerRepeatMode _repeat = PlayerRepeatMode.none;
  AudioSource? _preferred;
  String? _errorMessage;

  ReadingEvent? _event;
  DateTime? _startedAt;

  /// 정렬된 페이지. **저장 순서를 믿지 않고 `orderIndex` 로 정렬한다.**
  List<BookPage> get pages => content.orderedPages;

  int get index => _index;
  int get pageCount => pages.length;

  BookPage? get currentPage =>
      (_index >= 0 && _index < pages.length) ? pages[_index] : null;

  bool get isPlaying => _playing;

  /// 끝까지 읽었나. 완료 화면 표시에 쓴다.
  bool get isFinished => _finished;

  PlayerRepeatMode get repeatMode => _repeat;

  /// 사용자가 명시 선택한 트랙 종류. `null` 이면 기본 우선순위를 따른다.
  AudioSource? get preferredSource => _preferred;

  String? get errorMessage => _errorMessage;

  bool get hasPrevious => _index > 0;
  bool get hasNext => _index < pages.length - 1;

  /// 진행률 0.0~1.0. 진행바에 쓴다.
  double get progress => pages.isEmpty ? 0 : (_index + 1) / pages.length;

  /// 이 책에서 고를 수 있는 트랙 종류. 트랙 전환 UI 의 옵션이다.
  ///
  /// 기기 TTS 는 **텍스트가 있는 페이지가 하나라도 있으면** 항상 가능하다 —
  /// 트랙 객체가 없어도 즉석 합성할 수 있기 때문이다.
  Set<AudioSource> get availableSources {
    final out = <AudioSource>{};
    for (final page in pages) {
      for (final t in page.tracks) {
        if (t.source == AudioSource.deviceTts || t.hasFile) out.add(t.source);
      }
      if (page.hasText) out.add(AudioSource.deviceTts);
    }
    return out;
  }

  /// 재생을 시작한다. 화면 진입 시 호출한다.
  Future<void> start() async {
    final generation = _generation;
    // FLOW 1: 재생 가능한지 확인 — 페이지가 없으면 할 일이 없다
    if (pages.isEmpty) {
      _errorMessage = '읽을 페이지가 없습니다. 먼저 페이지를 추가해 주세요.';
      notifyListeners();
      return;
    }
    try {
      final position = await positionRepository?.getById(content.id);
      _index = position?.resolvePageIndex(content) ?? 0;
    } on Object {
      _errorMessage = '읽던 위치를 복원하지 못했어요. 첫 장부터 읽어요.';
    }
    if (_disposed || !_active || generation != _generation) return;
    // FLOW 2: 독서 기록 시작 (M4 통계의 원천)
    await _openEvent();
    if (_disposed || !_active || generation != _generation) return;
    // FLOW 9: 현재 페이지 소리내기
    await _playCurrent();
  }

  /// 현재 페이지의 오디오를 재생한다.
  Future<void> _playCurrent() async {
    if (_disposed || !_active) return;
    final generation = ++_generation;
    _audioStarted = false;
    final page = currentPage;
    if (page == null) return;

    _errorMessage = null;
    _finished = false;
    try {
      await positionRepository?.save(
        ReadingPosition(
          contentId: content.id,
          pageId: page.id,
          updatedAt: _now(),
        ),
      );
    } on Object {
      _errorMessage = '읽던 위치를 저장하지 못했어요.';
    }

    if (_disposed || !_active || generation != _generation) return;
    _audioStarted = true;
    // FLOW 1: 사용자가 **기기 TTS 를 명시 선택**했다면 트랙 객체 없이도 읽는다.
    //
    // 왜 먼저 처리하나: deviceTts 는 텍스트만 있으면 성립하므로 트랙 객체가 없는 것이 정상이다.
    // selectTrack 에 맡기면 객체를 못 찾아 기본 우선순위(부모녹음)로 흘러가고,
    // **사용자가 "기기 목소리" 를 골랐는데 부모 녹음이 나오는** 버그가 된다
    // (2026-09-15 테스트가 잡았다).
    if (_preferred == AudioSource.deviceTts && page.hasText) {
      _playing = true;
      notifyListeners();
      await _player.speak(page.text!);
      return;
    }

    // FLOW 2: 이 페이지에서 들려줄 트랙을 고른다.
    //         우선순위는 BookPage.selectTrack 이 정의한다(부모녹음 우선, 기기TTS 최후).
    final track = page.selectTrack(preferred: _preferred);

    // FLOW 3: 파일이 있는 트랙 → 파일 재생
    if (track != null && track.hasFile) {
      final abs = _media.absolutePathOf(content.id, track.path!);
      _playing = true;
      notifyListeners();
      await _player.playFile(abs);
      return;
    }

    // FLOW 4: 기기 TTS — 트랙 객체가 없어도 텍스트만 있으면 읽을 수 있다.
    //         **이것이 최후의 폴백이라 재생 불가 페이지가 생기지 않는다.**
    if (page.hasText) {
      _playing = true;
      notifyListeners();
      await _player.speak(page.text!);
      return;
    }

    // FLOW 9: 소리낼 것이 없다 (텍스트도 트랙도 없는 페이지).
    //         멈추지 않고 사용자가 직접 넘기도록 둔다 — 그림만 보는 페이지일 수 있다.
    _playing = false;
    notifyListeners();
  }

  void _onAudioComplete() {
    if (_disposed || !_active) return;
    // 한 페이지 반복이면 같은 페이지를 다시 읽는다.
    if (_repeat == PlayerRepeatMode.page) {
      _playCurrent();
      return;
    }
    if (hasNext) {
      next();
      return;
    }
    // 마지막 페이지를 끝냈다.
    if (_repeat == PlayerRepeatMode.book) {
      _index = 0;
      notifyListeners();
      _playCurrent();
      return;
    }
    _finishReading();
  }

  void _onAudioError(String message) {
    _playing = false;
    _errorMessage = message;
    AppLogger.w('플레이어 오디오 오류: $message');
    notifyListeners();
  }

  Future<void> pause() async {
    _generation++;
    _active = false;
    if (!_playing) return;
    await _player.pause();
    _playing = false;
    notifyListeners();
  }

  /// 이어재생. 기기 TTS 는 이어재생이 없어 **현재 페이지를 다시 읽는다.**
  Future<void> resume() async {
    if (_disposed || _playing) return;
    _active = true;
    if (_finished) {
      _index = 0;
      await _openEvent();
      await _playCurrent();
      return;
    }
    if (!_audioStarted) {
      await _playCurrent();
      return;
    }
    final page = currentPage;
    // 파일 트랙이면 이어재생, TTS 면 처음부터 — 후자가 예측 가능하다.
    final track = page?.selectTrack(preferred: _preferred);
    if (track != null && track.hasFile) {
      _playing = true;
      notifyListeners();
      await _player.resume();
    } else {
      await _playCurrent();
    }
  }

  Future<void> next() async {
    if (_disposed) return;
    _active = true;
    if (!hasNext) return;
    _index += 1;
    notifyListeners();
    await _playCurrent();
  }

  Future<void> previous() async {
    if (_disposed) return;
    _active = true;
    if (!hasPrevious) return;
    _index -= 1;
    notifyListeners();
    await _playCurrent();
  }

  /// 특정 페이지로 이동한다. 범위를 벗어나면 무시한다.
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= pages.length || index == _index) return;
    _index = index;
    notifyListeners();
    await _playCurrent();
  }

  /// 트랙 종류를 바꾼다. 즉시 현재 페이지를 새 목소리로 다시 읽는다.
  ///
  /// 왜 즉시 반영하나: "엄마 목소리로 바꿨는데 다음 페이지부터 적용" 은 기대와 다르다.
  Future<void> selectSource(AudioSource? source) async {
    if (_preferred == source) return;
    _preferred = source;
    notifyListeners();
    if (_playing) await _playCurrent();
  }

  void setRepeatMode(PlayerRepeatMode mode) {
    if (_repeat == mode) return;
    _repeat = mode;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  // ── 독서 기록 ────────────────────────────────────────────

  /// 재생 시작 시 기록을 만든다.
  Future<void> _openEvent() async {
    if (_event != null) return; // 이미 열려 있다
    final started = _now();
    _startedAt = started;
    final event = ReadingEvent(
      id: _uuid.v4(),
      contentId: content.id,
      childId: childId,
      startedAt: started,
    );
    _event = event;
    try {
      await _events.save(event);
    } on AppException catch (e) {
      // 기록 실패로 재생을 막지 않는다 — 통계는 부가 기능이다.
      AppLogger.w('독서 기록 시작 실패(무시): $e');
    }
  }

  /// 끝까지 읽었다. 기록을 완독으로 닫는다.
  Future<void> _finishReading() async {
    _playing = false;
    _finished = true;
    notifyListeners();
    await _closeEvent(completed: true);
    if (!_disposed && _active && _finished) onBookComplete?.call();
  }

  /// 기록을 닫는다. 화면을 떠날 때도 호출한다(중간 이탈).
  Future<void> _closeEvent({required bool completed}) async {
    final event = _event;
    final started = _startedAt;
    if (event == null || started == null) return;
    _event = null;

    final ended = _now();
    // 실제로 들은 시간. 일시정지·이탈을 정밀 추적하지 않고 경과 시간으로 근사한다.
    final seconds = ended.difference(started).inSeconds;
    try {
      await _events.save(
        event.copyWith(
          endedAt: ended,
          durationSec: seconds < 0 ? 0 : seconds,
          completed: completed,
        ),
      );
    } on AppException catch (e) {
      AppLogger.w('독서 기록 종료 실패(무시): $e');
    }
  }

  /// 화면을 떠날 때 호출한다. **기록을 닫고 오디오를 멈춘다.**
  ///
  /// 왜 dispose 와 나누나: `dispose` 는 동기라 `await` 를 쓸 수 없다.
  /// 기록 저장은 비동기이므로 화면이 먼저 이걸 부른 뒤 dispose 가 뒤따른다.
  Future<void> leave() async {
    _active = false;
    _generation++;
    await _player.stop();
    _playing = false;
    // 끝까지 못 읽고 나갔다 — completed=false 로 닫는다.
    await _closeEvent(completed: _finished);
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _generation++;
    _player.dispose();
    _player.onComplete = null;
    _player.onError = null;
    super.dispose();
  }
}

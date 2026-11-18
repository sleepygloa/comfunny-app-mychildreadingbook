import 'dart:io';

import 'package:record/record.dart';

import '../../core/app_logger.dart';
import '../../core/error_codes.dart';

/// 부모 목소리 녹음. **이 앱의 본질**이다 — 부모가 직접 읽어주는 것.
///
/// 결과는 로컬 파일이며 [AudioSource.parentRecording] 트랙이 된다.
/// ⚠️ **외부로 전송하지 않는다.** 녹음 파일은 기기에만 있고, 백업(M2)에서만
/// 사용자 계정 Storage 로 간다(`[A-06]` · [1_DESIGN §1.6]).
class RecordingService {
  RecordingService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// 지금 녹음 중인 파일의 경로. 중단·완료 판단에 쓴다.
  String? _currentPath;

  bool get isRecording => _currentPath != null;

  /// 마이크 권한이 있나. 없으면 요청 다이얼로그가 뜬다.
  ///
  /// 왜 별도 메서드인가: 녹음 시작과 권한 요청을 한 번에 하면, 사용자가 거부했을 때
  /// "녹음 실패" 로만 보여 원인을 알 수 없다. 화면이 먼저 물어보고 안내할 수 있게 나눈다.
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } on Exception catch (e, st) {
      AppLogger.e('마이크 권한 확인 실패', error: e, stackTrace: st);
      return false;
    }
  }

  /// [absolutePath] 에 녹음을 시작한다. 상위 디렉토리는 자동 생성한다.
  ///
  /// 절대 경로를 받는 이유: 경로 조립은 `AppPaths` + 앱 문서 디렉토리의 책임이다.
  /// 이 서비스는 "받은 곳에 녹음한다" 만 한다(단일 책임).
  Future<void> start(String absolutePath) async {
    // FLOW 1: 중복 시작 차단 — 조용히 무시하면 이전 녹음이 유실된다
    if (isRecording) {
      throw const AppException(
        ErrorCode.conflict,
        detail: '이미 녹음 중이다. stop() 을 먼저 호출한다',
      );
    }
    // FLOW 2: 권한 확인. 여기서 막지 않으면 빈 파일이 만들어진다
    if (!await hasPermission()) {
      throw const AppException(ErrorCode.badRequest, detail: '마이크 권한이 없다');
    }
    // FLOW 3: 상위 디렉토리 확보
    await File(absolutePath).parent.create(recursive: true);

    // FLOW 9: 녹음 시작
    //
    // 왜 AAC-LC / m4a 인가: Android·iOS 양쪽이 기본 지원하고 음성에 충분한 품질을
    // 작은 용량으로 낸다. wav 는 용량이 10배 이상이라 페이지마다 녹음하는 이 앱에
    // 맞지 않는다(기기 저장소가 1차 저장소다).
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
        numChannels: 1, // 목소리는 모노로 충분하다 — 용량 절반
      ),
      path: absolutePath,
    );
    _currentPath = absolutePath;
    AppLogger.i('녹음 시작: $absolutePath');
  }

  /// 녹음을 마치고 **실제로 저장된 파일 경로**를 돌려준다.
  ///
  /// 파일이 비었거나 만들어지지 않으면 `null` — 호출자는 트랙을 추가하지 않아야 한다.
  /// 빈 트랙을 추가하면 재생 시 아무 소리도 안 나서 사용자가 원인을 모른다.
  Future<String?> stop() async {
    if (!isRecording) return null;
    final expected = _currentPath;
    _currentPath = null;

    final resultPath = await _recorder.stop();
    final path = resultPath ?? expected;
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) {
      AppLogger.w('녹음 파일이 생성되지 않았다: $path');
      return null;
    }
    final size = await file.length();
    if (size < _minValidBytes) {
      // 버튼을 잘못 눌러 순간 녹음된 경우. 쓰레기 파일을 남기지 않는다.
      AppLogger.w('녹음이 너무 짧다($size bytes) — 파일 삭제: $path');
      await file.delete();
      return null;
    }
    AppLogger.i('녹음 완료: $path ($size bytes)');
    return path;
  }

  /// 녹음을 버린다. 파일도 지운다.
  ///
  /// 사용자가 "다시 녹음" 을 누르는 경로다 — 중간 파일이 쌓이지 않게 한다.
  Future<void> cancel() async {
    if (!isRecording) return;
    final path = _currentPath;
    _currentPath = null;
    await _recorder.stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    AppLogger.i('녹음 취소');
  }

  Future<void> pause() async {
    if (isRecording) await _recorder.pause();
  }

  Future<void> resume() async {
    if (isRecording) await _recorder.resume();
  }

  /// 입력 음량 스트림(0.0~1.0 근사). 녹음 중 파형 UI 에 쓴다.
  ///
  /// 왜 파형이 필요한가: 녹음이 실제로 되고 있는지 눈으로 확인할 수 없으면
  /// 사용자가 다 읽고 나서야 실패를 안다.
  Stream<Amplitude> amplitudeStream({
    Duration interval = const Duration(milliseconds: 200),
  }) => _recorder.onAmplitudeChanged(interval);

  Future<void> dispose() async {
    if (isRecording) await cancel();
    await _recorder.dispose();
  }

  /// 이보다 작으면 실패로 본다. AAC 헤더만 있는 파일이 대략 이 수준이다.
  static const int _minValidBytes = 1024;
}

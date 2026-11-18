import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'app/playback_runtime.dart';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/app_logger.dart';
import 'service_locator.dart';

/// 앱 진입점.
///
/// 순서가 중요하다:
/// 1. `ensureInitialized` — 플랫폼 채널을 쓰기 전에 바인딩이 준비돼야 한다
/// 2. `setupLocator` — `path_provider` 로 앱 문서 디렉토리를 얻어 저장소를 만든다.
///    **이게 끝나야 화면이 데이터를 읽을 수 있다**
/// 3. `runApp`
///
/// 왜 DI 를 `runApp` 앞에서 기다리나: 화면이 먼저 뜨면 첫 프레임에서 저장소가 없어
/// `get_it` 이 예외를 던진다. 스플래시로 가리는 방법도 있지만, 로컬 디렉토리 조회는
/// 수십 ms 라 기다리는 편이 단순하다.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await setupLocator();
  } on Object catch (e, st) {
    // 저장소를 만들 수 없으면 앱이 아무것도 못 한다. 흰 화면 대신 원인을 보여준다.
    AppLogger.e('앱 초기화 실패', error: e, stackTrace: st);
    runApp(_StartupFailureApp(error: e));
    return;
  }

  AudioSession? session;
  try {
    session = await AudioSession.instance;
  } on Object {
    AppLogger.w('오디오 세션을 준비하지 못했습니다. 전경 재생만 사용합니다.');
  }
  final playback = createPlaybackQueue(session: session);
  await playback.restoreRecent();
  if (session != null) PlaybackInterruptions(session, playback);
  try {
    if (session == null) throw StateError("audio session unavailable");
    await AudioService.init(
      builder: () => ReadingAudioHandler(playback),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.comfunny.mychild_reading.playback',
        androidNotificationChannelName: '책 읽어주기',
        androidNotificationIcon: 'drawable/ic_reading_notification',
        androidStopForegroundOnPause: false,
      ),
    );
    playback.backgroundEnabled = true;
  } on Object {
    // 서비스 초기화 실패 시 앱을 막지 않고 기존 전경 재생을 유지한다.
    playback.error = '백그라운드 재생을 준비하지 못했어요. 앱을 켜 둔 상태로 들어 주세요.';
  }
  runApp(MyChildReadingApp(playbackQueue: playback));
}

/// 초기화 실패 화면.
///
/// 왜 이걸 만드나: 초기화가 실패하면 Flutter 는 회색 화면만 보여준다. 사용자는
/// 앱이 죽은 이유를 알 수 없고, 개발자도 로그를 못 본다(릴리스 빌드).
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 72),
              const SizedBox(height: 20),
              const Text(
                '앱을 시작할 수 없습니다',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                '저장 공간에 접근하지 못했습니다.\n기기를 다시 시작한 뒤 열어 주세요.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 개발 중 원인 확인용. 사용자에게도 문의 시 도움이 된다.
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

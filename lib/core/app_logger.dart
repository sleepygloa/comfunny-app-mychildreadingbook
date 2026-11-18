import 'package:logger/logger.dart';

/// 앱 전역 로거.
///
/// 왜 이 래퍼를 두는가: `print()` 는 릴리스 빌드에서도 남고 레벨 구분이 없어
/// 운영 중 원인 추적이 안 된다. [A-08] 이 `print` 금지를 규정하므로 진입점을 하나로 모은다.
/// 나중에 파일 로깅·원격 리포팅을 붙일 때도 이 한 곳만 고치면 된다.
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      // 왜 색을 끄는가: CI·파일 리다이렉트 시 ANSI escape 가 로그를 오염시킨다.
      colors: false,
      printEmojis: false,
    ),
  );

  /// 개발 중 흐름 확인용. 릴리스에서 굳이 남길 필요 없는 것.
  static void d(Object? message) => _logger.d(message);

  /// 정상 동작 중 기록할 가치가 있는 사건 (백업 완료, 작업 신청 등).
  static void i(Object? message) => _logger.i(message);

  /// 실패는 아니지만 주의가 필요한 것 (폴백 발동, 권한 거부).
  static void w(Object? message) => _logger.w(message);

  /// 실패. [error] 와 [stackTrace] 를 함께 넘겨 원인을 남긴다.
  static void e(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
}

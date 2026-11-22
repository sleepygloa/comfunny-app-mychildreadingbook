/// 앱 에러코드 — `E-MCR-{번호}` 체계. [A-08]
///
/// 왜 코드를 붙이는가: 사용자에게 보여줄 문구와 개발자가 추적할 식별자는 다르다.
/// 코드가 있으면 로그·문의에서 같은 사건을 같은 이름으로 부를 수 있다.
class ErrorCode {
  const ErrorCode(this.code, this.userMessage);

  /// `E-MCR-400` 형태. 로그·리포트에 남는 식별자.
  final String code;

  /// 사용자에게 그대로 보여줄 한국어 문구.
  final String userMessage;

  /// 잘못된 입력 — 빈 제목, 페이지 0장 등.
  static const badRequest = ErrorCode('E-MCR-400', '입력값을 확인해 주세요.');

  /// 대상이 없다 — 콘텐츠·페이지·목소리 프로필.
  static const notFound = ErrorCode('E-MCR-404', '대상을 찾을 수 없습니다.');

  /// 상태 충돌 — 이미 처리 중인 작업을 다시 신청하는 등.
  ///
  /// 왜 별도 코드인가: 조용한 무시(no-op)로 넘기면 사용자가 성공으로 착각한다.
  static const conflict = ErrorCode('E-MCR-409', '이미 처리 중입니다.');

  /// 파일 IO·직렬화 실패. 데이터 손실 위험이 있는 유일한 등급.
  static const storageFailure = ErrorCode('E-MCR-500', '저장에 실패했습니다.');

  static const backupInvalid = ErrorCode(
    'E-MCR-510',
    '백업 파일을 확인할 수 없어요. 원본은 그대로 보관됩니다.',
  );
  static const backupChanged = ErrorCode(
    'E-MCR-511',
    '저장 중인 작업이 있어요. 작업을 마친 뒤 다시 백업해 주세요.',
  );

  /// 영상처럼 보기의 화면 보호(캡처 막기 · 화면 켜 두기)를 켜거나 끄지 못했다.
  /// 보기는 계속되므로 사용자에게 알리지 않고 기록만 한다.
  static const screenGuardFailure = ErrorCode('E-MCR-520', '화면 보호를 켜지 못했어요.');

  /// 사진에서 글자 뽑기(기기 안 글자 인식)가 실패했다. 글은 그대로 두고 직접 쓰게 안내한다.
  static const textExtractFailure = ErrorCode(
    'E-MCR-530',
    '글자를 읽지 못했어요. 직접 적거나 다시 해 주세요.',
  );

  @override
  String toString() => code;
}

/// 도메인 계층이 던지는 예외.
///
/// 왜 Flutter 예외를 쓰지 않는가: `domain` 은 Flutter 를 모른다(순수 Dart).
/// 이 규칙이 도메인 단위 테스트를 가능하게 한다.
class AppException implements Exception {
  const AppException(this.errorCode, {this.detail, this.cause});

  final ErrorCode errorCode;

  /// 개발자용 상세. 사용자에게 보여주지 않는다.
  final String? detail;
  final Object? cause;

  @override
  String toString() =>
      'AppException(${errorCode.code}${detail == null ? '' : ': $detail'})';
}

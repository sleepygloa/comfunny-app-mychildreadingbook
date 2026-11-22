/// 책 쪽 사진에서 글자를 읽어 오는 기능. 녹음할 때 보고 읽을 글을 채워 준다.
///
/// 왜 domain 에 인터페이스만 두나: 화면은 글자 인식 엔진(ML Kit)을 몰라야 한다.
/// 테스트는 가짜를 끼우고, 나중에 엔진을 바꿔도 화면은 그대로다 `[B-02]`.
///
/// ⚠️ 구현은 **기기 안에서만** 읽어야 한다. 책 사진은 아이 앱의 자료다 `[A-06-7]` (ADR-16).
abstract interface class TextExtractor {
  /// 이 기기에서 한국어 글자를 읽을 수 있나. 아니면 버튼을 끄고 안내한다.
  bool get isAvailable;

  /// [imagePath] 사진의 글자를 줄 단위로 읽어 돌려준다. 글자가 없으면 빈 문자열.
  Future<String> extract(String imagePath);

  /// 엔진 자원을 푼다.
  Future<void> dispose();
}

/// 읽은 글을 녹음용으로 다듬는다.
///
/// 왜: 인식 결과는 책의 줄마다 끊기고, 글 덩어리 사이에 빈 줄이 들어가 화면에서 띄엄띄엄 보인다
/// (2026-11-22 오너 실기기 사용). 한 덩어리 안의 줄은 띄어쓰기로 이어 문장으로 만들고,
/// 덩어리 사이는 줄바꿈 하나로만 나눠 녹음할 때 한눈에 읽히게 한다.
String tidyExtractedText(String raw) {
  final paragraphs = <String>[];
  final current = <String>[];
  void flush() {
    if (current.isNotEmpty) paragraphs.add(current.join(' '));
    current.clear();
  }

  for (final line in raw.replaceAll('\r\n', '\n').split('\n')) {
    final clean = line.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      flush();
    } else {
      current.add(clean);
    }
  }
  flush();
  return paragraphs.join('\n');
}

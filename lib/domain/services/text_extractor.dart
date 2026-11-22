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
/// 왜: 인식 결과는 줄마다 끊겨 있고 빈 줄·앞뒤 공백이 섞인다. 문단(빈 줄)은 살리고
/// 한 문단 안의 줄바꿈은 그대로 두어 책 모양과 같게 읽히게 한다.
String tidyExtractedText(String raw) {
  final lines = raw
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
      .toList();
  final out = <String>[];
  for (final line in lines) {
    if (line.isEmpty) {
      if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
    } else {
      out.add(line);
    }
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

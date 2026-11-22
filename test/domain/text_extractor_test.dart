import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/domain/services/text_extractor.dart';

void main() {
  test('뽑은 글은 공백을 줄이고 문단 빈 줄을 하나만 남긴다', () {
    expect(
      tidyExtractedText('  옛날 옛날에   \r\n작은 곰이\n\n\n\n살았어요.  \n\n'),
      '옛날 옛날에\n작은 곰이\n\n살았어요.',
    );
  });
  test('글자가 없으면 빈 문자열이다', () {
    expect(tidyExtractedText(' \n \n'), '');
  });
}

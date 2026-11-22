import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/domain/services/text_extractor.dart';

void main() {
  test('덩어리 안의 줄은 이어 문장으로, 덩어리 사이는 줄바꿈 하나로 붙인다', () {
    expect(
      tidyExtractedText('  옛날 옛날에   \r\n작은 곰이\n\n\n\n살았어요.  \n\n'),
      '옛날 옛날에 작은 곰이\n살았어요.',
    );
  });
  test('글자가 없으면 빈 문자열이다', () {
    expect(tidyExtractedText(' \n \n'), '');
  });
}

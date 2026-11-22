import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/app_logger.dart';
import '../../domain/services/text_extractor.dart';

/// ML Kit 글자 인식. **모델이 앱 안에 묶여 기기에서만 돈다** — 사진이 나가지 않는다 `[A-06-7]`.
///
/// Android 는 한국어 모델(`text-recognition-korean`, 번들형)을 함께 넣었다.
/// iOS 플러그인은 아직 한국어를 지원하지 않아(라틴 글자로 대체) 버튼을 끈다.
class MlKitTextExtractor implements TextExtractor {
  TextRecognizer? _recognizer;

  @override
  bool get isAvailable => Platform.isAndroid;

  @override
  Future<String> extract(String imagePath) async {
    // FLOW 1: 쓸 수 없는 기기는 시도하지 않는다
    if (!isAvailable) return '';
    // FLOW 2: 인식기는 처음 쓸 때 만든다 — 녹음만 하는 사람에게 모델 적재 비용을 물리지 않는다
    final recognizer = _recognizer ??= TextRecognizer(
      script: TextRecognitionScript.korean,
    );
    // FLOW 3: 사진을 읽는다. 블록(문단) 사이를 빈 줄로 잇는다
    final result = await recognizer.processImage(
      InputImage.fromFilePath(imagePath),
    );
    final text = result.blocks.map((b) => b.text).join('\n\n');
    // FLOW 9: 글 내용은 로그에 남기지 않는다(가족 자료) — 글자 수만
    AppLogger.d('글자 뽑기 완료: ${text.length}자');
    return text;
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}

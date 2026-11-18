import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 미리보기와 저장에 같은 색 변환을 사용한다. 원본 파일은 덮어쓰지 않는다.
class PhotoProcessing {
  static ui.ColorFilter filter({
    required bool enhanced,
    required double brightness,
  }) {
    final contrast = enhanced ? 1.16 : 1.0;
    final offset = 255 * brightness + 128 * (1 - contrast);
    return ui.ColorFilter.matrix([
      contrast,
      0,
      0,
      0,
      offset,
      0,
      contrast,
      0,
      0,
      offset,
      0,
      0,
      contrast,
      0,
      offset,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  static Future<ui.Image> load(String path) async {
    final file = File(path);
    if (await file.length() > 40 * 1024 * 1024) {
      throw const FormatException('image too large');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await file.readAsBytes(),
    );
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      // 편집·출력 메모리를 제한하되 카메라 high 해상도의 글자를 유지한다.
      final scale = math.min(
        1.0,
        3200 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static Future<Uint8List> render(
    ui.Image image,
    ui.Rect normalized, {
    required bool enhanced,
    required double brightness,
  }) async {
    if (!normalized.isFinite ||
        normalized.left < 0 ||
        normalized.top < 0 ||
        normalized.right > 1 ||
        normalized.bottom > 1 ||
        normalized.width <= 0 ||
        normalized.height <= 0 ||
        !brightness.isFinite ||
        brightness < -.2 ||
        brightness > .3) {
      throw const FormatException('invalid crop');
    }
    final source = ui.Rect.fromLTRB(
      (normalized.left * image.width).floorToDouble(),
      (normalized.top * image.height).floorToDouble(),
      (normalized.right * image.width).ceilToDouble(),
      (normalized.bottom * image.height).ceilToDouble(),
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      source,
      ui.Rect.fromLTWH(0, 0, source.width, source.height),
      ui.Paint()
        ..filterQuality = ui.FilterQuality.high
        ..colorFilter = filter(enhanced: enhanced, brightness: brightness),
    );
    final picture = recorder.endRecording();
    ui.Image? result;
    try {
      result = await picture.toImage(
        source.width.toInt(),
        source.height.toInt(),
      );
      final bytes = await result.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('encoding failed');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      result?.dispose();
      picture.dispose();
    }
  }
}

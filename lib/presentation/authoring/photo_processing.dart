import 'dart:async';
import 'dart:io';
import 'dart:isolate';
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

  // ── 글자 또렷하게 (2026-11-22) ──────────────────────────────
  //
  // 왜 AI 가 아닌가: 폰 안에서, 사진을 밖으로 보내지 않고, 돈 없이 해야 한다(A-06-7 · A-01).
  // 조명 평탄화는 오래된 문서 스캔 기법으로 충분히 효과가 있다 — 종이의 밝기를 쪽 전체에서
  // 고르게 맞추면 그늘진 글자는 살아나고 반사로 번쩍이는 곳은 눌린다.
  // 단, 반사로 완전히 하얗게 날아간 글자는 정보가 없어 살릴 수 없다.

  /// 거의 하얗게 날아간 픽셀의 비율(0~1). 반사 안내를 띄울지 정한다.
  static double glareRatio(Uint8List rgba) {
    var bright = 0, total = 0;
    // 모든 픽셀을 볼 필요 없다 — 16개 중 1개만 본다.
    for (var i = 0; i + 3 < rgba.length; i += 64) {
      total++;
      if (rgba[i] > 248 && rgba[i + 1] > 248 && rgba[i + 2] > 248) bright++;
    }
    return total == 0 ? 0 : bright / total;
  }

  /// 조명 평탄화 + 대비. 색은 그대로 두고 밝기만 고르게 한다(그림책 그림이 회색이 되지 않게).
  static Uint8List clarifyText(Uint8List rgba, int width, int height) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      throw const FormatException('invalid pixels');
    }
    // FLOW 1: 종이 밝기 지도 — 칸마다 가장 밝은 값(종이)을 잡는다
    final cell = math.max(8, math.max(width, height) ~/ 40);
    final gw = (width + cell - 1) ~/ cell, gh = (height + cell - 1) ~/ cell;
    final grid = Float64List(gw * gh);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        var best = 0.0;
        final y1 = math.min(height, (gy + 1) * cell);
        final x1 = math.min(width, (gx + 1) * cell);
        // 칸 안을 듬성듬성 본다 — 종이 밝기는 천천히 변한다.
        for (var y = gy * cell; y < y1; y += 2) {
          for (var x = gx * cell; x < x1; x += 2) {
            final o = (y * width + x) * 4;
            final l = .299 * rgba[o] + .587 * rgba[o + 1] + .114 * rgba[o + 2];
            if (l > best) best = l;
          }
        }
        grid[gy * gw + gx] = best;
      }
    }
    // FLOW 2: 이웃 칸과 고르게 — 글자만 있는 칸이 어둡게 잡혀도 튀지 않게
    final smooth = Float64List(gw * gh);
    for (var gy = 0; gy < gh; gy++) {
      for (var gx = 0; gx < gw; gx++) {
        var sum = 0.0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final x = gx + dx, y = gy + dy;
            if (x < 0 || y < 0 || x >= gw || y >= gh) continue;
            sum += grid[y * gw + x];
            n++;
          }
        }
        smooth[gy * gw + gx] = math.max(40, sum / n);
      }
    }
    // FLOW 3: 픽셀마다 종이 밝기로 나눠 고르게 + 대비
    final out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      final fy = (y + .5) / cell - .5;
      final y0 = fy.floor().clamp(0, gh - 1), y1 = (y0 + 1).clamp(0, gh - 1);
      final ty = (fy - y0).clamp(0.0, 1.0);
      for (var x = 0; x < width; x++) {
        final fx = (x + .5) / cell - .5;
        final x0 = fx.floor().clamp(0, gw - 1), x1 = (x0 + 1).clamp(0, gw - 1);
        final tx = (fx - x0).clamp(0.0, 1.0);
        final top = smooth[y0 * gw + x0] * (1 - tx) + smooth[y0 * gw + x1] * tx;
        final bottom =
            smooth[y1 * gw + x0] * (1 - tx) + smooth[y1 * gw + x1] * tx;
        final paper = top * (1 - ty) + bottom * ty;
        final scale = 238 / paper;
        final o = (y * width + x) * 4;
        for (var c = 0; c < 3; c++) {
          final v = rgba[o + c] * scale;
          // 종이 쪽은 하얗게, 글자 쪽은 더 진하게.
          out[o + c] = ((v - 128) * 1.3 + 128).round().clamp(0, 255);
        }
        out[o + 3] = 255;
      }
    }
    // FLOW 9: 원본 바이트는 건드리지 않았다
    return out;
  }

  /// [image] 를 글자 또렷하게 한 새 이미지. 무거운 계산은 별도 isolate 에서 한다.
  static Future<ui.Image> clarified(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('pixels unavailable');
    final w = image.width, h = image.height;
    final input = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final pixels = await Isolate.run(() => clarifyText(input, w, h));
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  /// 반사 안내용 — 이미지에서 하얗게 날아간 비율.
  static Future<double> glareOf(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return 0;
    return glareRatio(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}

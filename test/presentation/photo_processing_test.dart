import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/presentation/authoring/photo_processing.dart';

Future<ui.Image> samplePhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 100, 80),
    ui.Paint()..color = const ui.Color(0xFFAAAAAA),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(30, 25, 40, 10),
    ui.Paint()..color = const ui.Color(0xFF222222),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 80);
  picture.dispose();
  return image;
}

Future<ui.Image> decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('선택한 사각형 크기로 잘라 PNG를 만들고 보정은 종이 밝기와 글자 대비를 높인다', () async {
    final image = await samplePhoto();
    final raw = await decode(
      await PhotoProcessing.render(
        image,
        const ui.Rect.fromLTRB(.2, .25, .8, .75),
        enhanced: false,
        brightness: 0,
      ),
    );
    final corrected = await decode(
      await PhotoProcessing.render(
        image,
        const ui.Rect.fromLTRB(.2, .25, .8, .75),
        enhanced: true,
        brightness: .09,
      ),
    );
    expect(raw.width, 60);
    expect(raw.height, 40);
    final rawBytes = (await raw.toByteData())!.buffer.asUint8List();
    final correctedBytes = (await corrected.toByteData())!.buffer.asUint8List();
    final textOffset = (6 * 60 + 11) * 4;
    expect(correctedBytes[0], greaterThan(rawBytes[0]));
    expect(
      correctedBytes[0] - correctedBytes[textOffset],
      greaterThan(rawBytes[0] - rawBytes[textOffset]),
    );
    image.dispose();
    raw.dispose();
    corrected.dispose();
  });
  test('범위 밖 또는 빈 자르기는 거절하고 원본 PNG 파일은 바꾸지 않는다', () async {
    final image = await samplePhoto();
    await expectLater(
      PhotoProcessing.render(
        image,
        const ui.Rect.fromLTRB(-.1, 0, 1, 1),
        enhanced: false,
        brightness: 0,
      ),
      throwsFormatException,
    );
    await expectLater(
      PhotoProcessing.render(
        image,
        ui.Rect.zero,
        enhanced: false,
        brightness: 0,
      ),
      throwsFormatException,
    );
    final dir = await Directory.systemTemp.createTemp('scan_test_');
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      final file = await File('${dir.path}/original.png').writeAsBytes(bytes);
      final loaded = await PhotoProcessing.load(file.path);
      await PhotoProcessing.render(
        loaded,
        const ui.Rect.fromLTRB(0, 0, .5, 1),
        enhanced: true,
        brightness: .1,
      );
      expect(await file.readAsBytes(), bytes);
      loaded.dispose();
    } finally {
      image.dispose();
      await dir.delete(recursive: true);
    }
  });

  group('글자 또렷하게', () {
    // 합성 쪽: 왼쪽은 그늘(종이 150), 오른쪽은 밝음(종이 245). 양쪽에 같은 진하기의 글자 줄.
    Uint8List page(int w, int h) {
      final px = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final paper = 150 + 95 * x / (w - 1);
          final text = y % 20 < 3 && x % 7 < 4;
          final v = (text ? paper * .45 : paper).round();
          final o = (y * w + x) * 4;
          px[o] = px[o + 1] = px[o + 2] = v;
          px[o + 3] = 255;
        }
      }
      return px;
    }

    int at(Uint8List px, int w, int x, int y) => px[(y * w + x) * 4];

    test('그늘진 종이와 밝은 종이를 비슷하게 맞추고 글자는 더 진하게 한다', () {
      const w = 320, h = 200;
      final before = page(w, h);
      final after = PhotoProcessing.clarifyText(before, w, h);
      // 종이: 왼쪽 그늘(y=10, 글자 없음)과 오른쪽 밝은 곳의 차이가 줄어든다.
      final gapBefore = (at(before, w, 310, 10) - at(before, w, 10, 10)).abs();
      final gapAfter = (at(after, w, 310, 10) - at(after, w, 10, 10)).abs();
      expect(gapAfter, lessThan(gapBefore ~/ 3));
      // 그늘 속 글자와 종이의 대비가 커진다.
      final contrastBefore = at(before, w, 10, 10) - at(before, w, 0, 0);
      final contrastAfter = at(after, w, 10, 10) - at(after, w, 0, 0);
      expect(contrastAfter, greaterThan(contrastBefore));
      // 원본 바이트는 그대로다.
      expect(before, page(w, h));
    });

    test('반사 비율은 하얗게 날아간 픽셀 비율이고, 잘못된 크기는 거절한다', () {
      final white = Uint8List(64 * 64 * 4)..fillRange(0, 64 * 64 * 4, 255);
      expect(PhotoProcessing.glareRatio(white), 1);
      expect(PhotoProcessing.glareRatio(page(64, 64)), 0);
      expect(
        () => PhotoProcessing.clarifyText(Uint8List(10), 64, 64),
        throwsFormatException,
      );
    });

    test('이미지로 돌려 같은 크기의 새 이미지를 만든다', () async {
      final image = await samplePhoto();
      final clear = await PhotoProcessing.clarified(image);
      expect((clear.width, clear.height), (image.width, image.height));
      clear.dispose();
      image.dispose();
    });
  });
}

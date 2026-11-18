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
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/presentation/authoring/photo_edit_screen.dart';

import 'photo_processing_test.dart' as fixtures;

void main() {
  testWidgets('모서리 조절과 원본 색상 선택 후 적용하면 잘린 새 사진을 반환한다', (tester) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late Directory dir;
    late File original;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('photo_ui_');
      final image = await fixtures.samplePhoto();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      original = await File('${dir.path}/original.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await dir.delete(recursive: true);
    });
    String? output;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              output = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoEditScreen(path: original.path),
                ),
              );
            },
            child: const Text('편집'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('편집'));
    Future<void> settleIo() async {
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await settleIo();
    expect(find.byKey(const ValueKey('crop-corner-0')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('crop-corner-0')),
      const Offset(55, 35),
    );
    await tester.pump();
    // 점에서 떨어진 안쪽을 끌어도 가장 가까운 모서리(오른아래)가 따라온다.
    final before = tester.getCenter(
      find.byKey(const ValueKey('crop-corner-2')),
    );
    await tester.dragFrom(
      before - const Offset(40, 40),
      const Offset(-30, -20),
    );
    await tester.pump();
    final after = tester.getCenter(find.byKey(const ValueKey('crop-corner-2')));
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    await tester.tap(find.text('원본 색상'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    await tester.tap(find.text('적용'));
    await settleIo();
    expect(output, isNotNull);
    expect(output, isNot(original.path));
    await tester.runAsync(() async {
      final image = await fixtures.decode(await File(output!).readAsBytes());
      expect(image.width, lessThan(100));
      expect(image.height, lessThan(80));
      expect(await original.exists(), isTrue);
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

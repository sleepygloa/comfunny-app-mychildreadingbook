import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/presentation/authoring/capture_screen.dart';

class FakeCamera extends CameraController {
  FakeCamera()
    : super(
        const CameraDescription(
          name: 'test',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
        ResolutionPreset.high,
      );
  Completer<void>? initialization;
  int shots = 0;
  bool closed = false;
  bool failInitialize = false;
  DeviceOrientation? locked;
  @override
  Future<void> initialize() async {
    await initialization?.future;
    if (failInitialize) throw StateError('camera unavailable');
    value = value.copyWith(
      isInitialized: true,
      previewSize: const Size(1200, 800),
    );
  }

  @override
  Future<void> lockCaptureOrientation([DeviceOrientation? orientation]) async {
    locked = orientation;
    value = value.copyWith(lockedCaptureOrientation: Optional.of(orientation!));
  }

  @override
  Future<XFile> takePicture() async => XFile('/synthetic-${++shots}.jpg');
  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);
  @override
  // Fake camera has no platform resources to dispose.
  // ignore: must_call_super
  Future<void> dispose() async {
    closed = true;
  }
}

void main() {
  final orientations = <Object?>[];
  setUp(() {
    orientations.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add(call.arguments);
          }
          return null;
        });
  });
  Future<void> open(
    WidgetTester tester,
    FakeCamera camera,
    Future<bool> Function(String)? save, {
    bool landscape = true,
    Future<String?> Function(BuildContext, String)? review,
  }) async {
    tester.view.physicalSize = landscape
        ? const Size(900, 420)
        : const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<String>(
              context,
              MaterialPageRoute(
                builder: (_) => CaptureScreen(
                  createCamera: () async => camera,
                  reviewPhoto: review ?? (_, path) async => path,
                  onPageCaptured: save,
                ),
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  testWidgets('본문 두 장을 연속 촬영하고 완료 때만 복귀하며 방향을 복원한다', (tester) async {
    final camera = FakeCamera();
    final paths = <String>[];
    await open(tester, camera, (path) async {
      paths.add(path);
      return true;
    });
    expect(camera.locked, DeviceOrientation.landscapeLeft);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('사진 찍기'));
      await tester.pumpAndSettle();
    }
    expect(paths, ['/synthetic-1.jpg', '/synthetic-2.jpg']);
    expect(find.text('2장 보관됨'), findsOneWidget);
    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();
    expect(find.text('열기'), findsOneWidget);
    expect(camera.closed, isTrue);
    expect(orientations.first, ['DeviceOrientation.landscapeLeft']);
    expect(orientations.last, isEmpty);
  });
  testWidgets('저장 중 중복 촬영을 막고 실패 사진을 재촬영 없이 재시도한다', (tester) async {
    final camera = FakeCamera();
    final first = Completer<bool>();
    var attempts = 0;
    await open(tester, camera, (_) {
      attempts++;
      return attempts == 1 ? first.future : Future.value(true);
    });
    await tester.tap(find.text('사진 찍기'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(camera.shots, 1);
    first.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('0장 보관됨'), findsOneWidget);
    camera.failInitialize = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('카메라 다시 열기'), findsOneWidget);
    await tester.tap(find.text('저장 재시도'));
    await tester.pumpAndSettle();
    expect(camera.shots, 1);
    expect(find.text('1장 보관됨'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('자르기를 취소하면 페이지 추가 없이 다음 촬영을 이어간다', (tester) async {
    final camera = FakeCamera();
    var saved = 0;
    var reviews = 0;
    await open(tester, camera, (_) async {
      saved++;
      return true;
    }, review: (_, path) async => ++reviews == 1 ? null : '/edited.png');
    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();
    expect(saved, 0);
    expect(find.text('0장 보관됨'), findsOneWidget);
    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();
    expect(saved, 1);
    expect(camera.shots, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('초기화 중 닫고 재진입해도 새 가로 잠금과 카메라 소유권을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = FakeCamera()..initialization = Completer<void>();
    final second = FakeCamera();
    await tester.pumpWidget(
      MaterialApp(
        home: CaptureScreen(
          key: const ValueKey('first'),
          createCamera: () async => first,
          onPageCaptured: (_) async => true,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: CaptureScreen(
          key: const ValueKey('second'),
          createCamera: () async => second,
          onPageCaptured: (_) async => true,
        ),
      ),
    );
    await tester.pump();
    expect(second.value.isInitialized, isFalse);
    first.initialization!.complete();
    await tester.pumpAndSettle();
    expect(first.closed, isTrue);
    expect(second.value.isInitialized, isTrue);
    expect(orientations.last, ['DeviceOrientation.landscapeLeft']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('세로 화면에서는 본문 촬영을 막고 표지는 한 장 뒤 복귀한다', (tester) async {
    final camera = FakeCamera();
    await open(tester, camera, (_) async => true, landscape: false);
    await tester.tap(find.text('사진 찍기'));
    expect(camera.shots, 0);
    expect(find.text('휴대폰을 가로로 돌려 주세요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final cover = FakeCamera();
    await open(tester, cover, null, landscape: false);
    await tester.tap(find.text('사진 찍기'));
    await tester.pumpAndSettle();
    expect(cover.shots, 1);
    expect(cover.locked, isNull);
    expect(find.text('열기'), findsOneWidget);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/data/local/media_storage.dart';
import 'package:mychild_reading/domain/repositories/repositories.dart';
import 'package:mychild_reading/presentation/player/player_view_model.dart';
import 'package:mychild_reading/presentation/player/watch_screen.dart';
import 'package:mychild_reading/service_locator.dart';

import 'music_navigation_test.dart' show FakeAudio, Events, book;

/// 영상처럼 보기 — 합성 책 한 권, 그림 파일 없음(없는 그림 안내가 뜬다).
void main() {
  late Directory tmp;
  late PlayerViewModel vm;
  late List<MethodCall> screenCalls;
  late List<MethodCall> systemCalls;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('watch_');
    await registerWith(tmp);
    vm = PlayerViewModel(
      content: book('a'),
      audioPlayer: FakeAudio(),
      mediaStorage: MediaStorage(tmp),
      readingEventRepository: Events(),
    );
    screenCalls = [];
    systemCalls = [];
  });
  tearDown(() async {
    vm.dispose();
    await resetLocator();
    await tmp.delete(recursive: true);
  });

  Future<int> pumpWatch(WidgetTester tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('mychild_reading/screen'),
      (call) async {
        screenCalls.add(call);
        return null;
      },
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      systemCalls.add(call);
      return null;
    });
    var toggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WatchScreen(
                  player: vm,
                  onNext: () async {},
                  onPrevious: () async {},
                  onToggle: ({bool onlyPlay = false}) async => toggles++,
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
    // 설정 파일을 읽는 실제 IO 가 끝날 때까지 기다린다.
    for (var i = 0; i < 20 && screenCalls.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    return toggles;
  }

  testWidgets('가로 전체 화면 · 화면 보호를 켜고, 나가면 되돌린다', (tester) async {
    await pumpWatch(tester);
    expect(screenCalls.single.arguments, {'on': true, 'secure': true});
    final orient = systemCalls.firstWhere(
      (c) => c.method == 'SystemChrome.setPreferredOrientations',
    );
    expect(orient.arguments, [
      'DeviceOrientation.landscapeLeft',
      'DeviceOrientation.landscapeRight',
    ]);
    expect(find.text('1 / 1'), findsOneWidget);

    // 자물쇠를 2초 동안 누르고 있으면 나간다.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.lock_outline)),
    );
    // 손가락이 닿고 잠깐 뒤에 눌림이 시작된다(탭 판정 대기). 그다음 2초.
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(
      WatchScreen.unlockHold + const Duration(milliseconds: 100),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('열기'), findsOneWidget);
    expect(screenCalls.last.arguments['on'], isFalse);
    expect(
      systemCalls.where(
        (c) =>
            c.method == 'SystemChrome.setPreferredOrientations' &&
            (c.arguments as List).isEmpty,
      ),
      isNotEmpty,
    );
  });

  testWidgets('아이 잠금: 뒤로 가기 · 짧게 누르기로는 나가지 않는다', (tester) async {
    await pumpWatch(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('나가려면 🔒 를 꾹 누르고 있어요'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('열기'), findsNothing);
    expect(find.byType(WatchScreen), findsOneWidget);
  });

  testWidgets('설정에서 미러링을 허용하면 캡처 막기를 켜지 않는다(화면 켜 두기만)', (tester) async {
    await tester.runAsync(
      () => sl<WatchSettingsRepository>().setAllowMirroring(true),
    );
    await pumpWatch(tester);
    expect(screenCalls.single.arguments, {'on': true, 'secure': false});
    expect(
      await tester.runAsync(
        () => sl<WatchSettingsRepository>().allowMirroring(),
      ),
      isTrue,
    );
  });
}

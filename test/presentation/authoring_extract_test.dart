import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mychild_reading/domain/repositories/book_authoring_repository.dart';
import 'package:mychild_reading/domain/services/text_extractor.dart';
import 'package:mychild_reading/presentation/authoring/authoring_screen.dart';
import 'package:mychild_reading/presentation/authoring/authoring_view_model.dart';
import 'package:mychild_reading/service_locator.dart';

/// 기기 글자 인식 대신 정해 둔 글을 돌려주는 가짜. 합성 데이터만 쓴다.
class _FakeExtractor implements TextExtractor {
  _FakeExtractor(this.result);
  String result;
  bool available = true;
  int calls = 0;
  @override
  bool get isAvailable => available;
  @override
  Future<String> extract(String imagePath) async {
    calls++;
    return result;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory tmp;
  late _FakeExtractor fake;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('extract_ui_');
    await registerWith(tmp);
    fake = _FakeExtractor('  옛날 옛날에\n작은 곰이 살았어요.  ');
    sl
      ..unregister<TextExtractor>()
      ..registerSingleton<TextExtractor>(fake);
  });
  tearDown(() async {
    await resetLocator();
    await tmp.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<AuthoringViewModel> pumpVoice(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vm = AuthoringViewModel(sl<BookAuthoringRepository>());
    await tester.runAsync(() async {
      await vm.load(null);
      final photo = File('${tmp.path}/page.jpg');
      await photo.writeAsBytes([1, 2, 3]);
      await vm.addPhoto(photo.path);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: vm,
        child: const MaterialApp(home: AuthoringScreen(voiceOnly: true)),
      ),
    );
    await settle(tester);
    return vm;
  }

  testWidgets('사진에서 글자를 뽑아 글을 채우고 큰 글씨로 보인다', (tester) async {
    final vm = await pumpVoice(tester);
    expect(find.text('글 크게 보기'), findsNothing);
    await tester.tap(find.text('사진에서 글자 뽑기'));
    await settle(tester);
    expect(fake.calls, 1);
    final page = vm.draft!.content.orderedPages.single;
    expect(page.text, '옛날 옛날에\n작은 곰이 살았어요.');
    expect(find.byKey(ValueKey('big-text-${page.id}')), findsOneWidget);
    expect(find.text('큰 글씨 접기'), findsOneWidget);
    await tester.tap(find.text('큰 글씨 접기'));
    await tester.pump();
    expect(find.byKey(ValueKey('big-text-${page.id}')), findsNothing);
    expect(find.text('글 크게 보기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('이미 쓴 글은 묻고 그대로 두기를 고르면 바꾸지 않는다', (tester) async {
    final vm = await pumpVoice(tester);
    final id = vm.draft!.content.orderedPages.single.id;
    vm.setText(id, '내가 쓴 글');
    await tester.pump();
    fake.result = '새 글';
    await tester.tap(find.text('사진에서 글자 뽑기'));
    await tester.pumpAndSettle();
    expect(find.text('지금 글을 바꿀까요?'), findsOneWidget);
    await tester.tap(find.text('그대로 두기'));
    await settle(tester);
    expect(fake.calls, 0);
    expect(vm.draft!.content.orderedPages.single.text, '내가 쓴 글');
    await tester.tap(find.text('사진에서 글자 뽑기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('바꾸기'));
    await settle(tester);
    expect(vm.draft!.content.orderedPages.single.text, '새 글');
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('글자가 없거나 쓸 수 없는 기기면 안내만 하고 글을 두지 않는다', (tester) async {
    final vm = await pumpVoice(tester);
    fake.result = '  \n ';
    await tester.tap(find.text('사진에서 글자 뽑기'));
    await settle(tester);
    expect(find.textContaining('글자를 찾지 못했어요'), findsOneWidget);
    expect(vm.draft!.content.orderedPages.single.hasText, isFalse);
    fake.available = false;
    await tester.tap(find.text('사진에서 글자 뽑기'));
    await settle(tester);
    expect(fake.calls, 1);
    expect(find.textContaining('글자 뽑기를 쓸 수 없어요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}

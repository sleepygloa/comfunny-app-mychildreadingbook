import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/app/theme.dart';
import 'package:mychild_reading/presentation/common/storybook_widgets.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('책 친구는 작은 화면 큰 글자 모션 감소에서 안전하다 dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(1.8),
            ),
            child: Scaffold(
              body: ListView(
                children: const [
                  StoryWelcome(
                    title: '오늘은 어떤 책을 함께 읽을까요?',
                    subtitle: '한 권의 책에 다정한 목소리를 담아요.',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('톡, 인사해 볼까요?'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }
  testWidgets('책 친구 인사 애니메이션은 반복하지 않고 끝난다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: StoryWelcome(title: '우리 집 책방', subtitle: '반가워요'),
        ),
      ),
    );
    await tester.tap(find.byTooltip('톡, 인사해 볼까요?'));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}

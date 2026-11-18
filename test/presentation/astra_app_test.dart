import 'package:provider/provider.dart';
import 'package:mychild_reading/presentation/authoring/authoring_view_model.dart';
import 'package:mychild_reading/data/local/media_storage.dart';
import 'package:mychild_reading/presentation/player/playback_queue.dart';
import 'package:mychild_reading/presentation/player/player_view_model.dart';

import 'music_navigation_test.dart' as fixtures;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/series.dart';
import 'package:mychild_reading/domain/entities/playlist.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/domain/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/app/app.dart';
import 'package:mychild_reading/domain/repositories/reading_workspace_repositories.dart';
import 'package:mychild_reading/domain/entities/book_draft.dart';
import 'package:mychild_reading/service_locator.dart';

void main() {
  late Directory tmp;
  setUpAll(() async {
    final iconPath = Platform.environment['MCR_ICON_FONT'];
    if (iconPath != null) {
      final bytes = await File(iconPath).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final path = Platform.environment['MCR_TEST_FONT'];
    if (path != null) {
      final bytes = await File(path).readAsBytes();
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('astra_ui_');
    await registerWith(tmp);
  });
  tearDown(() async {
    await resetLocator();
    await tmp.delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('책장에서 제작 직행하고 단일 저장은 필수 전집을 검사한다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const MyChildReadingApp()),
    );
    await settle(tester);
    expect(find.text('첫 이야기를 기다리고 있어요'), findsOneWidget);
    expect(find.byTooltip('책 삭제'), findsNothing);
    await tester.tap(find.byTooltip('책 등록'));
    await settle(tester);
    expect(find.text('부모 공간 열기'), findsNothing);
    expect(find.text('저장'), findsOneWidget);
    expect(find.text('초안 저장'), findsNothing);
    expect(find.text('책장에 넣기'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, '달빛 도서관');
    await settle(tester);
    await tester.tap(find.text('저장'));
    await settle(tester);
    List<BookDraft>? drafts;
    sl<BookDraftRepository>().getAll().then((value) => drafts = value);
    await settle(tester);
    expect(drafts!.single.content.title, '달빛 도서관');
    expect(find.text('다음 단계'), findsNothing);
    expect(find.text('전집을 입력해 주세요.'), findsWidgets);
    expect(find.text('표지 촬영'), findsOneWidget);
    await tester.ensureVisible(find.text('내용 연속 촬영'));
    await tester.pumpAndSettle();
    expect(find.text('내용 연속 촬영'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final vm = tester.element(find.text('책 만들기')).read<AuthoringViewModel>();
    vm.updateClassification(series: '달빛 전집', volume: '1');
    final photo = File('${tmp.path}/photo.jpg');
    await tester.runAsync(() async {
      await photo.writeAsBytes([1, 2, 3]);
    });
    vm.addPhoto(photo.path);
    await settle(tester);
    expect(vm.error, isNull);
    expect(find.text('녹음'), findsNothing);
    expect(find.text('들어보기'), findsNothing);
    expect(find.text('자르기 · 보정'), findsOneWidget);
    await tester.tap(find.text('저장'));
    await settle(tester);
    for (var attempt = 0; attempt < 8 && vm.isBusy; attempt++) {
      await settle(tester);
    }
    await settle(tester);
    expect(vm.error, isNull);
    expect(vm.isBusy, isFalse);
    expect(find.text('책 만들기'), findsNothing);
    List<Content>? savedBooks;
    List<BookDraft>? remainingDrafts;
    sl<ContentRepository>().getAll().then((value) => savedBooks = value);
    sl<BookDraftRepository>().getAll().then((value) => remainingDrafts = value);
    await settle(tester);
    expect(savedBooks!.single.title, '달빛 도서관');
    expect(savedBooks!.single.volume, 1);
    expect(savedBooks!.single.publisher, isNull);
    expect(remainingDrafts, isEmpty);
    expect(savedBooks!.single.pages.single.tracks, isEmpty);
    await tester.tap(find.text('달빛 전집'));
    await settle(tester);
    await tester.tap(find.byTooltip('달빛 도서관 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('목소리 넣기'));
    await settle(tester);
    for (
      var attempt = 0;
      attempt < 8 && find.text('녹음').evaluate().isEmpty;
      attempt++
    ) {
      await settle(tester);
    }
    await tester.ensureVisible(find.text('녹음'));
    expect(find.text('녹음'), findsOneWidget);
    expect(find.text('들어보기'), findsOneWidget);
    expect(find.text('내용 연속 촬영'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
  testWidgets('탭에서 저장 플레이리스트 생성 책 추가 이름 변경 삭제까지 연결된다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await sl<SeriesRepository>().save(
        const Series(id: 'set', title: '우리 이야기', publisher: '그레이트북스'),
      );
      await sl<ContentRepository>().save(
        Content(
          id: 'sample',
          type: ContentType.pagedBook,
          title: '달빛 산책',
          publisher: '그레이트북스',
          seriesId: 'set',
          volume: 1,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          pages: [
            const BookPage(
              id: 'page',
              orderIndex: 0,
              imagePath: 'sample.jpg',
              text: '테스트용 이야기',
            ),
          ],
        ),
      );
    });
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: capture, child: const MyChildReadingApp()),
    );
    await settle(tester);
    await tester.tap(find.text('우리 이야기'));
    await settle(tester);
    expect(find.text('1. 달빛 산책'), findsOneWidget);
    await tester.runAsync(() async {
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File('/private/tmp/astra-library-tabs.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
    await tester.tap(find.text('플레이리스트').last);
    await settle(tester);
    await tester.tap(find.byTooltip('플레이리스트 만들기'));
    await settle(tester);
    await tester.tap(find.text('계속하기'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '잠들기 전');
    await tester.tap(find.text('저장'));
    await settle(tester);
    expect(find.text('잠들기 전'), findsOneWidget);
    await tester.tap(find.text('잠들기 전'));
    await settle(tester);
    await tester.tap(find.byTooltip('플레이리스트 관리'));
    await settle(tester);
    await tester.tap(find.text('책 추가 · 제외 · 순서'));
    await settle(tester);
    await tester.tap(find.text('계속하기'));
    await settle(tester);
    await tester.tap(find.byTooltip('달빛 산책 추가'));
    await settle(tester);
    await tester.tap(find.text('저장'));
    await settle(tester);
    expect(find.text('1권의 이야기'), findsOneWidget);
    List<Playlist>? saved;
    sl<PlaylistRepository>().getAll().then((value) => saved = value);
    await settle(tester);
    expect(saved!.single.contentIds, ['sample']);
    await tester.tap(find.byTooltip('플레이리스트 관리'));
    await settle(tester);
    await tester.tap(find.text('이름 변경'));
    await settle(tester);
    await tester.tap(find.text('계속하기'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '좋아하는 이야기');
    await tester.tap(find.text('저장'));
    await settle(tester);
    expect(find.text('좋아하는 이야기'), findsOneWidget);
    await tester.tap(find.byTooltip('플레이리스트 관리'));
    await settle(tester);
    await tester.tap(find.text('플레이리스트 삭제'));
    await settle(tester);
    await tester.tap(find.text('계속하기'));
    await settle(tester);
    await tester.tap(find.text('삭제'));
    await settle(tester);
    expect(find.text('나만의 목록을 만들어 보세요'), findsOneWidget);
    await tester.tap(find.text('책장').last);
    await settle(tester);
    expect(find.text('1. 달빛 산책'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
  testWidgets('세 메뉴는 같은 플로팅 플레이어를 쓰고 목록은 모달에서 관리한다', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final book = fixtures.book('floating').copyWith(title: '달빛 산책');
    await tester.runAsync(() async {
      await sl<ContentRepository>().save(book);
      await sl<PlaylistRepository>().save(
        Playlist(
          id: 'bedtime',
          title: '잠들기 전',
          createdAt: DateTime(2026),
          contentIds: [book.id],
        ),
      );
    });
    final queue = PlaybackQueue(
      createPlayer: (b) => PlayerViewModel(
        content: b,
        audioPlayer: fixtures.FakeAudio(),
        mediaStorage: MediaStorage(tmp),
        readingEventRepository: fixtures.Events(),
      ),
    )..backgroundEnabled = true;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MyChildReadingApp(playbackQueue: queue),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('전체 재생 (1권)'));
    await settle(tester);
    expect(find.text('작은 도서관'), findsOneWidget);
    expect(queue.player!.isPlaying, isTrue);
    expect(find.byTooltip('플로팅 플레이어 펼치기'), findsOneWidget);
    final first = queue.player;
    await tester.tap(find.text('플레이리스트').last);
    await settle(tester);
    expect(queue.player, same(first));
    await tester.tap(find.byTooltip('잠들기 전 전체 재생'));
    await settle(tester);
    expect(find.text('잠들기 전'), findsOneWidget);
    await tester.tap(find.text('최근재생목록').last);
    await settle(tester);
    expect(find.text('달빛 산책'), findsNWidgets(2));
    await tester.tap(find.text('달빛 산책').first);
    await settle(tester);
    expect(queue.player!.isPlaying, isTrue);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/private/tmp/astra-recent-playback.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.byTooltip('플로팅 플레이어 펼치기'));
    await settle(tester);
    expect(find.text('재생 종료'), findsNothing);
    expect(find.byTooltip('재생 종료'), findsOneWidget);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/private/tmp/astra-floating-player.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    tester.view.physicalSize = const Size(320, 740);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('일시정지').last);
    await settle(tester);
    expect(queue.player!.isPlaying, isFalse);
    await tester.pumpWidget(const SizedBox());
    queue.dispose();
    await settle(tester);
  });

  for (final size in [const Size(320, 740), const Size(1024, 768)]) {
    testWidgets('책장은 $size 및 큰 글자에서 넘치지 않는다', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const MyChildReadingApp());
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  }
}

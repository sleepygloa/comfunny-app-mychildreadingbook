import '../domain/repositories/reading_workspace_repositories.dart';
import '../presentation/library/catalog_view_model.dart';
import '../presentation/player/playback_queue.dart';
import 'playback_runtime.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/repositories/repositories.dart';
import '../presentation/library/library_view_model.dart';
import '../service_locator.dart';
import 'router.dart';
import 'theme.dart';

/// 앱 루트.
///
/// **역할 분담** ([2_DEVELOPMENT §2.4]):
/// - `get_it`(`sl`) = 저장소·서비스 — 상태가 아닌 것
/// - `provider`(`MultiProvider`) = ViewModel — UI 상태
///
/// 섞지 않는 이유: 저장소를 `ChangeNotifier` 로 감싸면 "무엇이 상태인가" 가 흐려지고,
/// 위젯 트리 밖(테스트·백그라운드 작업)에서 저장소를 쓸 수 없게 된다.
class MyChildReadingApp extends StatefulWidget {
  const MyChildReadingApp({super.key, this.playbackQueue});
  final PlaybackQueue? playbackQueue;

  @override
  State<MyChildReadingApp> createState() => _MyChildReadingAppState();
}

class _MyChildReadingAppState extends State<MyChildReadingApp>
    with WidgetsBindingObserver {
  late final PlaybackQueue _queue =
      widget.playbackQueue ?? createPlaybackQueue();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _queue.setForeground(state == AppLifecycleState.resumed);
  }

  // 라우터를 State 에 보관하는 이유: build 마다 새로 만들면 내비게이션 이력이 초기화된다.
  late final GoRouter _router = AppRouter.create();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    if (widget.playbackQueue == null) _queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PlaybackQueue>.value(value: _queue),
        ChangeNotifierProvider(
          create: (_) => CatalogViewModel(
            contents: sl<ContentRepository>(),
            series: sl<SeriesRepository>(),
            playlists: sl<PlaylistRepository>(),
            drafts: sl<BookDraftRepository>(),
            topicRepository: sl<TopicRepository>(),
            bookTags: sl<BookTagRepository>(),
          ),
        ),
        // 책장 VM 은 앱 전역에 하나면 충분하다 — 탭을 옮겨도 목록을 다시 읽지 않는다.
        ChangeNotifierProvider(
          create: (_) => LibraryViewModel(
            contentRepository: sl<ContentRepository>(),
            seriesRepository: sl<SeriesRepository>(),
          ),
        ),
        // 편집 VM(AuthoringViewModel)은 라우트(router.dart)에서, 플레이어 VM 은 재생 큐가
        // 책마다(playback_runtime.dart createPlayer) 만든다 — 화면·책이 바뀌면 버려야 하는 상태라 전역에 두지 않는다.
      ],
      child: MaterialApp.router(
        title: '작은 도서관',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // 자기 전에 쓰는 앱이라 시스템 설정을 따른다.
        themeMode: ThemeMode.system,
        routerConfig: _router,
      ),
    );
  }
}

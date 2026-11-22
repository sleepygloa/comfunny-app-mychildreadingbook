import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../presentation/navigation/library_shell.dart';
import '../presentation/player/queue_screen.dart';
import '../presentation/player/watch_screen.dart';
import '../presentation/player/playback_editing_boundary.dart';
import '../presentation/library/astra_library_screen.dart';
import '../presentation/common/parent_boundary.dart';
import '../presentation/authoring/authoring_screen.dart';
import '../presentation/authoring/authoring_view_model.dart';
import '../domain/repositories/book_authoring_repository.dart';
import '../domain/repositories/repositories.dart';
import '../service_locator.dart';

/// 탭은 한 화면에서 유지하고 편집/재생목록만 별도 경로로 연다.
class AppRouter {
  AppRouter._();
  static const library = '/';
  static const contentNew = '/content/new';
  static GoRouter create() => GoRouter(
    initialLocation: library,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LibraryShell()),
      GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
      GoRoute(path: '/reader', builder: (_, _) => const QueueReader()),
      // 영상처럼 보기 — 가로 전체 화면 · 아이 잠금 (2026-11-22)
      GoRoute(path: '/watch', builder: (_, _) => const WatchReader()),
      GoRoute(
        path: '/drafts',
        builder: (_, _) => const ParentBoundary(child: ParentLibraryScreen()),
      ),
      GoRoute(
        path: contentNew,
        builder: (_, state) => ChangeNotifierProvider(
          create: (_) => AuthoringViewModel(
            sl<BookAuthoringRepository>(),
            seriesRepository: sl<SeriesRepository>(),
            contentRepository: sl<ContentRepository>(),
          )..load(null, seriesId: state.uri.queryParameters['series']),
          child: const PlaybackEditingBoundary(child: AuthoringScreen()),
        ),
      ),
      GoRoute(
        path: '/content/:id/edit',
        builder: (_, state) => ChangeNotifierProvider(
          create: (_) => AuthoringViewModel(
            sl<BookAuthoringRepository>(),
            seriesRepository: sl<SeriesRepository>(),
            contentRepository: sl<ContentRepository>(),
          )..load(state.pathParameters['id']),
          child: const PlaybackEditingBoundary(child: AuthoringScreen()),
        ),
      ),
      GoRoute(
        path: '/content/:id/voice',
        builder: (_, state) => ChangeNotifierProvider(
          create: (_) => AuthoringViewModel(
            sl<BookAuthoringRepository>(),
            seriesRepository: sl<SeriesRepository>(),
            contentRepository: sl<ContentRepository>(),
          )..load(state.pathParameters['id']),
          child: const PlaybackEditingBoundary(
            child: AuthoringScreen(voiceOnly: true),
          ),
        ),
      ),
    ],
  );
}

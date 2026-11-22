import 'domain/repositories/pending_writes.dart';

import 'dart:io';

import 'data/services/restore_transaction.dart';

import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import 'core/app_logger.dart';
import 'data/repositories/recent_playback_repository_impl.dart';
import 'domain/repositories/recent_playback_repository.dart';
import 'data/repositories/backup_repository_impl.dart';
import 'domain/repositories/backup_repository.dart';
import 'data/local/json_store.dart';
import 'data/local/authoring_media_store.dart';
import 'data/repositories/book_authoring_repository_impl.dart';
import 'domain/repositories/book_authoring_repository.dart';
import 'data/local/media_storage.dart';
import 'data/repositories/content_repository_impl.dart';
import 'data/repositories/index_repositories.dart';
import 'data/repositories/reading_workspace_repositories.dart';
import 'data/services/device_tts_service.dart';
import 'data/services/recording_service.dart';
import 'domain/repositories/reading_workspace_repositories.dart';
import 'domain/repositories/repositories.dart';

/// 의존성 등록소. `[B-02]` §2.1 권장 조합대로 `get_it` 을 쓴다.
///
/// 왜 provider 가 아니라 get_it 으로 저장소를 주입하나:
/// - **저장소·서비스는 상태가 아니다.** `ChangeNotifier` 로 감쌀 이유가 없다
/// - ViewModel 생성 시점에 `sl<ContentRepository>()` 로 꺼내면 위젯 트리와 무관하게 쓸 수 있다
/// - `provider` 는 **UI 상태(ViewModel)** 전용으로 남긴다 — 역할이 섞이지 않는다
final GetIt sl = GetIt.instance;

/// 앱 기동 시 한 번 호출한다. `runApp` **전에** 완료돼야 한다.
///
/// 왜 async 인가: `path_provider` 가 플랫폼 채널이라 비동기다. 앱 문서 디렉토리를
/// 모르면 저장소를 만들 수 없어서 여기서 기다린다.
Future<void> setupLocator() async {
  // FLOW 1: 앱 문서 디렉토리 — 로컬 우선 저장소의 뿌리
  //
  // 왜 Documents 인가: OS 가 임의로 비우지 않는다. Caches 는 용량이 부족하면 OS 가
  // 지운다 — 사용자가 만든 책이 사라진다.
  // 단 OS 클라우드 백업에서는 뺀다 [A-06-7] (2026-10-06) — 아이 사진·보호자 녹음이 기기 밖으로
  // 나가지 않게 iOS 는 AppDelegate.swift 가 iCloud 백업 제외를 걸고, Android 는 매니페스트가
  // allowBackup=false·dataExtractionRules 로 막는다. 기기 밖 보관은 사용자가 고르는 .mcrb 백업 파일뿐이다.
  final docs = await getApplicationDocumentsDirectory();
  AppLogger.i('앱 문서 디렉토리: ${docs.path}');

  await RestoreTransaction(docs).recover();
  // 이전 프로세스가 검사/확인 중 종료된 staging만 회수한다.
  await for (final entity in docs.list(followLinks: false)) {
    if (entity is Directory &&
        entity.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('.restore-stage-')) {
      try {
        await entity.delete(recursive: true);
      } on Object {
        /* 다음 시작 또는 OS 캐시 정리 때 회수한다. */
      }
    }
  }
  await registerWith(docs);
}

/// 디렉토리를 명시해 등록한다. **테스트에서 임시 폴더로 갈아끼우는 진입점.**
Future<void> registerWith(Directory baseDir) async {
  // FLOW 2: 저장 기반 — JSON(메타)과 미디어(바이너리)를 나눈다
  sl
    ..registerLazySingleton<JsonStore>(() => JsonStore(baseDir))
    ..registerLazySingleton<MediaStorage>(
      () => MediaStorage(baseDir, gate: sl<JsonStore>().gate),
    );

  // FLOW 3: 저장소 — 인터페이스로 등록한다.
  //         화면·ViewModel 은 구현체를 모른다(교체·fake 가 쉬워진다).
  sl
    ..registerLazySingleton<ContentRepository>(
      () => ContentRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<BookDraftRepository>(
      () => BookDraftRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<ReadingPositionRepository>(
      () => ReadingPositionRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<SeriesRepository>(
      () => SeriesRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<PlaylistRepository>(
      () => PlaylistRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<ChildProfileRepository>(
      () => ChildProfileRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<VoiceProfileRepository>(
      () => VoiceProfileRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<ReadingEventRepository>(
      () => ReadingEventRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<TopicRepository>(
      () => TopicRepositoryImpl(sl<JsonStore>()),
    )
    ..registerLazySingleton<BookTagRepository>(
      () => BookTagRepositoryImpl(sl<JsonStore>()),
    );

  sl.registerLazySingleton<RecentPlaybackRepository>(
    () => RecentPlaybackRepositoryImpl(sl<JsonStore>()),
  );
  sl.registerLazySingleton<BackupRepository>(
    () => BackupRepositoryImpl(baseDir),
  );

  sl.registerLazySingleton<BookAuthoringRepository>(
    () => BookAuthoringRepositoryImpl(
      contents: sl<ContentRepository>(),
      revisions: sl<ContentRepository>() as ContentRevisionRepository,
      drafts: sl<BookDraftRepository>(),
      media: AuthoringMediaStore(baseDir, gate: sl<JsonStore>().gate),
    ),
  );

  // FLOW 9: 서비스 — 플랫폼 자원을 쥔다.
  //
  // 왜 lazy 인가: TTS 엔진·녹음기는 **생성만으로도 플랫폼 채널을 건드린다**
  // (`record` 는 생성자에서 채널에 `create` 를 호출한다). 부모 녹음만 쓰는 사용자에게
  // TTS 초기화 비용을 물리지 않고, 위젯 테스트에서 불필요한 플러그인 의존을 피한다.
  //
  // ⚠️ **해제는 `dispose` 콜백으로 등록한다.** `reset()` 시 get_it 이
  // **실제로 생성된 인스턴스에만** 이 콜백을 호출한다.
  // 직접 `sl<T>()` 로 꺼내 해제하면 lazy singleton 을 **그 자리에서 생성**해 버려서,
  // 플러그인이 없는 테스트 환경에서 MissingPluginException 이 난다
  // (2026-09-12 위젯 테스트가 이 실수를 잡았다).
  sl
    ..registerLazySingleton<DeviceTtsService>(
      () => DeviceTtsService(),
      dispose: (service) => service.dispose(),
    )
    ..registerLazySingleton<RecordingService>(
      () => RecordingService(),
      dispose: (service) => service.dispose(),
    );
}

/// 등록을 전부 비운다. **테스트 `setUp`/`tearDown` 에서 호출한다.**
///
/// 생성된 인스턴스의 해제는 등록 시 준 `dispose` 콜백이 담당한다 —
/// 여기서 `sl<T>()` 를 호출하면 안 된다(미생성 lazy singleton 을 깨운다).
Future<void> resetLocator() => sl.reset();

/// 백업 화면은 내비게이션/재생을 잠근 뒤 호출한다. 제작 완료 후 하위 저장도 기다린다.
Future<void> waitForStorageWrites() async {
  for (final repository in <Object>[
    sl<BookAuthoringRepository>(),
    sl<ContentRepository>(),
    sl<BookDraftRepository>(),
    sl<ReadingPositionRepository>(),
    sl<SeriesRepository>(),
    sl<PlaylistRepository>(),
    sl<ChildProfileRepository>(),
    sl<VoiceProfileRepository>(),
    sl<ReadingEventRepository>(),
    sl<RecentPlaybackRepository>(),
  ]) {
    if (repository is PendingWrites) await repository.waitForWrites();
  }
}

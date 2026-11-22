/// 저장소 추상 인터페이스 모음.
///
/// **`domain` 은 구현을 모른다** — Flutter·Firebase·파일시스템 의존이 여기 없다.
/// 이 규칙이 도메인·ViewModel 단위 테스트를 가능하게 한다(fake 로 갈아끼운다).
///
/// 왜 한 파일에 모았나: 인터페이스가 각 10~20줄이라 파일을 6개로 쪼개면 탐색 비용만 늘어난다.
/// 구현체는 파일을 나눈다(로직이 있으므로).
library;

import '../entities/book_tags.dart';
import '../entities/child_profile.dart';
import '../entities/content.dart';
import '../entities/playlist.dart';
import '../entities/reading_event.dart';
import '../entities/series.dart';
import '../entities/topic.dart';
import '../entities/voice_profile.dart';

/// 콘텐츠(책·영상) 저장소. 콘텐츠별 `library/{id}/data.json` 을 다룬다.
abstract class ContentRepository {
  /// 전체 조회. `library/` 하위 폴더를 스캔한다.
  Future<List<Content>> getAll();

  Future<Content?> getById(String id);

  /// 신규 저장 또는 갱신(업서트). `updatedAt` 은 호출자가 갱신한다.
  Future<void> save(Content content);

  /// 콘텐츠와 **미디어 파일 전체**를 삭제한다.
  ///
  /// 순서 주의: 메타데이터 먼저, 파일 나중. 역순이면 참조가 깨진 고아 레코드가 남는다.
  Future<void> delete(String id);
}

/// 전집 저장소. `index/series.json`.
abstract class SeriesRepository {
  Future<List<Series>> getAll();
  Future<void> save(Series series);
  Future<void> delete(String id);
}

/// 저장 플레이리스트 저장소. 세션 재생목록은 별도 상태다. `index/playlists.json`.
abstract class PlaylistRepository {
  Future<List<Playlist>> getAll();
  Future<void> save(Playlist playlist);
  Future<void> delete(String id);
}

/// 아이 프로필 저장소 (M2 화면). `index/children.json`.
abstract class ChildProfileRepository {
  Future<List<ChildProfile>> getAll();
  Future<void> save(ChildProfile child);
  Future<void> delete(String id);
}

/// 독서 기록 저장소. `index/reading_events.json`.
///
/// **M1 부터 기록한다** — 통계 화면은 M4 지만 데이터가 먼저 쌓여 있어야 한다.
abstract class ReadingEventRepository {
  /// 기간으로 조회한다. 인자를 비우면 전체.
  Future<List<ReadingEvent>> query({
    DateTime? from,
    DateTime? to,
    String? childId,
  });

  /// append 또는 갱신(재생 종료 시 `endedAt`·`durationSec` 를 채운다).
  Future<void> save(ReadingEvent event);
}

/// 목소리 프로필 저장소 (M3). `index/voice_profiles.json`.
abstract class VoiceProfileRepository {
  Future<List<VoiceProfile>> getAll();
  Future<void> save(VoiceProfile profile);
  Future<void> delete(String id);
}

/// 주제 사전 저장소 — `index/topics.json`.
abstract class TopicRepository {
  /// 저장된 사전. 아직 저장한 적이 없으면 빈 목록(기본 사전은 화면 쪽에서 채운다).
  Future<List<Topic>> getAll();
  Future<void> save(Topic topic);
  Future<void> delete(String id);
}

/// 책 꼬리표 저장소 — `index/book_tags.json`. 행 id = 책 id.
abstract class BookTagRepository {
  Future<List<BookTags>> getAll();
  Future<void> save(BookTags tags);
  Future<void> delete(String contentId);
}

/// 이 기기의 영상처럼 보기 설정 — `settings/watch.json`.
///
/// 왜 백업에 넣지 않나: 기기마다 다른 선택이다(TV 에 연결하는 태블릿만 미러링을 켠다).
/// 그래서 백업 루트(`index/` 등) 밖에 두고, 복원이 건드리지 않는다.
abstract class WatchSettingsRepository {
  /// TV 미러링(화면 보내기)을 허용하는가. 기본은 막음(캡처 · 녹화 막기).
  Future<bool> allowMirroring();
  Future<void> setAllowMirroring(bool value);
}

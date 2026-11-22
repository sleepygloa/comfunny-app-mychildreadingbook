import '../../domain/entities/book_tags.dart';
import '../../domain/entities/child_profile.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/reading_event.dart';
import '../../domain/entities/series.dart';
import '../../domain/entities/topic.dart';
import '../../domain/entities/voice_profile.dart';
import '../../domain/repositories/repositories.dart';
import '../local/app_paths.dart';
import '../local/json_store.dart';
import 'index_repository_base.dart';

/// 전집 저장소 — `index/series.json`.
class SeriesRepositoryImpl extends IndexRepositoryBase<Series>
    implements SeriesRepository {
  SeriesRepositoryImpl(JsonStore store) : super(store, AppPaths.seriesFile);

  @override
  Series fromJson(Map<String, Object?> json) => Series.fromJson(json);
  @override
  Map<String, Object?> toJson(Series item) => item.toJson();
  @override
  String idOf(Series item) => item.id;

  /// 전집은 제목순이 찾기 쉽다.
  @override
  int Function(Series, Series)? get comparator =>
      (a, b) => a.title.compareTo(b.title);
}

/// 재생목록 저장소 (M2) — `index/playlists.json`.
class PlaylistRepositoryImpl extends IndexRepositoryBase<Playlist>
    implements PlaylistRepository {
  PlaylistRepositoryImpl(JsonStore store)
    : super(store, AppPaths.playlistsFile);

  @override
  Playlist fromJson(Map<String, Object?> json) => Playlist.fromJson(json);
  @override
  Map<String, Object?> toJson(Playlist item) => item.toJson();
  @override
  String idOf(Playlist item) => item.id;

  /// 최근 만든 목록이 위에.
  @override
  int Function(Playlist, Playlist)? get comparator =>
      (a, b) => b.createdAt.compareTo(a.createdAt);
}

/// 아이 프로필 저장소 (M2 화면) — `index/children.json`.
///
/// ⚠️ [A-06-7] 아동 개인정보 — 보호자 계정에 종속되며 외부로 내보내지 않는다.
class ChildProfileRepositoryImpl extends IndexRepositoryBase<ChildProfile>
    implements ChildProfileRepository {
  ChildProfileRepositoryImpl(JsonStore store)
    : super(store, AppPaths.childrenFile);

  @override
  ChildProfile fromJson(Map<String, Object?> json) =>
      ChildProfile.fromJson(json);
  @override
  Map<String, Object?> toJson(ChildProfile item) => item.toJson();
  @override
  String idOf(ChildProfile item) => item.id;
}

/// 목소리 프로필 저장소 (M3) — `index/voice_profiles.json`.
class VoiceProfileRepositoryImpl extends IndexRepositoryBase<VoiceProfile>
    implements VoiceProfileRepository {
  VoiceProfileRepositoryImpl(JsonStore store)
    : super(store, AppPaths.voiceProfilesFile);

  @override
  VoiceProfile fromJson(Map<String, Object?> json) =>
      VoiceProfile.fromJson(json);
  @override
  Map<String, Object?> toJson(VoiceProfile item) => item.toJson();
  @override
  String idOf(VoiceProfile item) => item.id;
}

/// 독서 기록 저장소 — `index/reading_events.json`.
///
/// **M1 부터 쌓는다.** 통계 화면(M4)이 이 데이터를 쓴다.
class ReadingEventRepositoryImpl extends IndexRepositoryBase<ReadingEvent>
    implements ReadingEventRepository {
  ReadingEventRepositoryImpl(JsonStore store)
    : super(store, AppPaths.readingEventsFile);

  @override
  ReadingEvent fromJson(Map<String, Object?> json) =>
      ReadingEvent.fromJson(json);
  @override
  Map<String, Object?> toJson(ReadingEvent item) => item.toJson();
  @override
  String idOf(ReadingEvent item) => item.id;

  /// 최근 기록이 위에. 통계·최근 읽은 책 표시에 그대로 쓴다.
  @override
  int Function(ReadingEvent, ReadingEvent)? get comparator =>
      (a, b) => b.startedAt.compareTo(a.startedAt);

  @override
  Future<List<ReadingEvent>> query({
    DateTime? from,
    DateTime? to,
    String? childId,
  }) async {
    final all = await getAll();
    return all.where((e) {
      // 기간은 시작 시각 기준으로 판단한다 — 자정을 넘긴 재생은 시작일에 속한다.
      if (from != null && e.startedAt.isBefore(from)) return false;
      if (to != null && e.startedAt.isAfter(to)) return false;
      if (childId != null && e.childId != childId) return false;
      return true;
    }).toList();
  }
}

/// 주제 사전 저장소 — `index/topics.json`.
class TopicRepositoryImpl extends IndexRepositoryBase<Topic>
    implements TopicRepository {
  TopicRepositoryImpl(JsonStore store) : super(store, AppPaths.topicsFile);

  @override
  Topic fromJson(Map<String, Object?> json) => Topic.fromJson(json);
  @override
  Map<String, Object?> toJson(Topic item) => item.toJson();
  @override
  String idOf(Topic item) => item.id;

  /// 보호자가 정한 순서, 같으면 이름순.
  @override
  int Function(Topic, Topic)? get comparator => (a, b) {
    final order = a.order.compareTo(b.order);
    return order != 0 ? order : a.name.compareTo(b.name);
  };
}

/// 책 꼬리표 저장소 — `index/book_tags.json`.
class BookTagRepositoryImpl extends IndexRepositoryBase<BookTags>
    implements BookTagRepository {
  BookTagRepositoryImpl(JsonStore store) : super(store, AppPaths.bookTagsFile);

  @override
  BookTags fromJson(Map<String, Object?> json) => BookTags.fromJson(json);
  @override
  Map<String, Object?> toJson(BookTags item) => item.toJson();
  @override
  String idOf(BookTags item) => item.contentId;
}

import '../../core/json_codec.dart';
import '../enums/enums.dart';
import 'book_page.dart';
import 'growth_dimensions.dart';
import 'video_clip.dart';

/// **읽을 수 있는 것 하나.** 책과 영상을 [type] 으로 구분해 한 엔티티로 통합했다.
///
/// 왜 통합했나: 플레이리스트·독서기록·성장통계가 둘을 구분 없이 다뤄야 한다.
/// 별도 엔티티로 두면 그 세 곳에서 매번 분기가 생긴다.
///
/// 이 객체가 `library/{id}/data.json` 의 내용이며 **해당 콘텐츠의 진실**이다.
class Content {
  const Content({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.author,
    this.publisher,
    this.seriesId,
    this.volume,
    this.coverPath,
    this.pages = const [],
    this.videoPath,
    this.clips = const [],
    this.dimensions = GrowthDimensions.empty,
    this.tags = const [],
  });

  final String id;
  final ContentType type;
  final String title;
  final String? author;
  final String? publisher;

  /// 소속 전집. 전집을 [Series] 로 분리한 이유는 출판사 → 전집 → 책 3단 구조를
  /// 책 자신의 필드로 흉내내면 같은 전집 정보가 책마다 중복되기 때문이다.
  final String? seriesId;

  /// 전집 내 권 번호.
  final int? volume;

  /// 콘텐츠 폴더 기준 상대 경로 (`cover.jpg`).
  final String? coverPath;

  /// [ContentType.pagedBook] 일 때의 페이지들.
  final List<BookPage> pages;

  /// [ContentType.video] 일 때의 영상 경로 (상대).
  final String? videoPath;

  /// [ContentType.video] 일 때의 구간·자막 (M4).
  final List<VideoClip> clips;

  final GrowthDimensions dimensions;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isBook => type == ContentType.pagedBook;
  bool get isVideo => type == ContentType.video;

  int get pageCount => pages.length;

  /// 순서대로 정렬한 페이지. **저장 순서를 신뢰하지 않는다** —
  /// 리오더 도중 앱이 죽으면 파일의 순서와 `orderIndex` 가 어긋날 수 있다.
  List<BookPage> get orderedPages {
    final sorted = [...pages]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return sorted;
  }

  /// 재생할 수 있는 상태인가.
  bool get isPlayable =>
      isBook ? pages.isNotEmpty : (videoPath != null && videoPath!.isNotEmpty);

  Content copyWith({
    String? id,
    ContentType? type,
    String? title,
    String? author,
    String? publisher,
    String? seriesId,
    int? volume,
    String? coverPath,
    List<BookPage>? pages,
    String? videoPath,
    List<VideoClip>? clips,
    GrowthDimensions? dimensions,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Content(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      author: author ?? this.author,
      publisher: publisher ?? this.publisher,
      seriesId: seriesId ?? this.seriesId,
      volume: volume ?? this.volume,
      coverPath: coverPath ?? this.coverPath,
      pages: pages ?? this.pages,
      videoPath: videoPath ?? this.videoPath,
      clips: clips ?? this.clips,
      dimensions: dimensions ?? this.dimensions,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'type': type.name,
    'title': title,
    'author': author,
    'publisher': publisher,
    'seriesId': seriesId,
    'volume': volume,
    'coverPath': coverPath,
    'pages': pages.map((p) => p.toJson()).toList(),
    'videoPath': videoPath,
    'clips': clips.map((c) => c.toJson()).toList(),
    'dimensions': dimensions.toJson(),
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  });

  factory Content.fromJson(Map<String, Object?> json) {
    return Content(
      id: asString(json['id']),
      type: enumFromName(
        json['type'],
        ContentType.values,
        fallback: ContentType.pagedBook,
      ),
      title: asString(json['title']),
      author: asStringOrNull(json['author']),
      publisher: asStringOrNull(json['publisher']),
      seriesId: asStringOrNull(json['seriesId']),
      volume: asIntOrNull(json['volume']),
      coverPath: asStringOrNull(json['coverPath']),
      pages: asList(
        json['pages'],
        (e) => e is Map ? BookPage.fromJson(asMap(e)) : null,
      ),
      videoPath: asStringOrNull(json['videoPath']),
      clips: asList(
        json['clips'],
        (e) => e is Map ? VideoClip.fromJson(asMap(e)) : null,
      ),
      dimensions: json['dimensions'] is Map
          ? GrowthDimensions.fromJson(asMap(json['dimensions']))
          : GrowthDimensions.empty,
      tags: asStringList(json['tags']),
      createdAt: asDateTime(json['createdAt']),
      updatedAt: asDateTime(json['updatedAt']),
    );
  }

  /// Firestore 로 보내는 **경량 메타** (M2 메타데이터 동기화).
  ///
  /// ⚠️ **미디어 경로·바이너리를 넣지 않는다.** 로컬 경로는 기기마다 다르고,
  /// 아동 콘텐츠를 클라우드에 남기지 않는 것이 [A-06-7] 요구다.
  Map<String, Object?> toMetadataJson() => compactMap({
    'id': id,
    'type': type.name,
    'title': title,
    'author': author,
    'publisher': publisher,
    'seriesId': seriesId,
    'volume': volume,
    'pageCount': pageCount,
    'dimensions': dimensions.toJson(),
    'tags': tags,
    'updatedAt': updatedAt.toIso8601String(),
  });
}

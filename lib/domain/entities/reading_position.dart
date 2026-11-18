import '../../core/json_codec.dart';
import 'content.dart';

/// 마지막으로 읽은 페이지. 회차별 통계인 ReadingEvent와 수명을 분리한다.
class ReadingPosition {
  const ReadingPosition({
    required this.contentId,
    required this.pageId,
    required this.updatedAt,
  });

  final String contentId;
  final String pageId;
  final DateTime updatedAt;

  /// 페이지 순서가 바뀌어도 같은 그림으로 돌아간다. 삭제됐으면 첫 페이지다.
  int? resolvePageIndex(Content content) {
    if (!content.isBook || content.pages.isEmpty) return null;
    if (content.id != contentId) return 0;
    final index = content.orderedPages.indexWhere((page) => page.id == pageId);
    return index < 0 ? 0 : index;
  }

  Map<String, Object?> toJson() => {
    'contentId': contentId,
    'pageId': pageId,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ReadingPosition.fromJson(Map<String, Object?> json) =>
      ReadingPosition(
        contentId: asString(json['contentId']),
        pageId: asString(json['pageId']),
        updatedAt: asDateTime(json['updatedAt']),
      );
}

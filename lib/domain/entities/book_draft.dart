import '../../core/json_codec.dart';
import 'content.dart';

/// 순서 대신 이름으로 저장해 제작 단계 재배치에도 기존 초안을 읽는다.
enum AuthoringStep { cover, pages, text, voice, preview }

/// 완성본과 분리한 편집 스냅샷. 이 객체 저장만으로 아이 책장에 게시되지 않는다.
class BookDraft {
  const BookDraft({
    required this.content,
    required this.savedAt,
    this.step = AuthoringStep.cover,
    this.sourceUpdatedAt,
  });

  final Content content;
  final AuthoringStep step;
  final DateTime savedAt;

  /// 기존 책에서 편집을 시작한 시점의 버전. null이면 신규 책이다.
  final DateTime? sourceUpdatedAt;

  String get id => content.id;
  bool get isRevision => sourceUpdatedAt != null;

  BookDraft copyWith({
    Content? content,
    AuthoringStep? step,
    DateTime? savedAt,
  }) => BookDraft(
    content: content ?? this.content,
    step: step ?? this.step,
    savedAt: savedAt ?? this.savedAt,
    sourceUpdatedAt: sourceUpdatedAt,
  );

  Map<String, Object?> toJson() => compactMap({
    'content': content.toJson(),
    'step': step.name,
    'savedAt': savedAt.toIso8601String(),
    'sourceUpdatedAt': sourceUpdatedAt?.toIso8601String(),
  });

  factory BookDraft.fromJson(Map<String, Object?> json) => BookDraft(
    content: Content.fromJson(asMap(json['content'])),
    step: enumFromName(
      json['step'],
      AuthoringStep.values,
      fallback: AuthoringStep.cover,
    ),
    savedAt: asDateTime(json['savedAt']),
    sourceUpdatedAt: asDateTimeOrNull(json['sourceUpdatedAt']),
  );
}

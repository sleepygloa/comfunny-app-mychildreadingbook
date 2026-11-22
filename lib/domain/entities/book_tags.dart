import '../../core/json_codec.dart';

/// 누리과정 5영역. 보호자가 직접 고른다(자동 추천 아님 — INDEX 제외 항목 참고).
///
/// 왜 enum 이 아닌 문자열로 저장하나: 저장은 [name] 문자열이고, 모르는 값은 읽을 때 버린다.
/// 영역 이름이 바뀌어도 옛 백업이 죽지 않게 하려는 것이다(`fromJson` 방어 규칙).
enum NuriArea {
  body('신체운동·건강', '🤸'),
  communication('의사소통', '💬'),
  social('사회관계', '🤝'),
  art('예술경험', '🎨'),
  nature('자연탐구', '🔍');

  const NuriArea(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// 책 한 권에 보호자가 붙인 꼬리표. `index/book_tags.json` 에 책마다 한 줄.
///
/// 왜 [Content] 안에 넣지 않나: 책 데이터는 초안 → 게시 → 수정 흐름(리비전 검사)을 거친다.
/// 별 하나 누르는 데 그 흐름을 태우면 편집 중인 초안과 부딪히고 `updatedAt` 이 쓸데없이 바뀐다.
/// 꼬리표는 책 내용이 아니라 "우리 집이 이 책을 어떻게 분류하나"라서 따로 둔다.
///
/// [contentId] 가 행의 id 다(책 한 권에 한 줄). 책을 지우면 행도 지운다.
/// 지우지 못하고 남은 행은 조회할 때 무시한다(고아 참조 허용 — [Playlist] 와 같은 이유).
class BookTags {
  const BookTags({
    required this.contentId,
    this.topicIds = const [],
    this.favorite = false,
    this.ageMin,
    this.ageMax,
    this.nuriAreas = const [],
  });

  final String contentId;
  final List<String> topicIds;
  final bool favorite;

  /// 권장 나이(만 나이 아님 — 집에서 쓰는 "몇 살"). 둘 다 없으면 나이 무관.
  final int? ageMin;
  final int? ageMax;
  final List<NuriArea> nuriAreas;

  /// 꼬리표가 하나도 없으면 행을 저장하지 않아도 된다.
  bool get isEmpty =>
      topicIds.isEmpty &&
      !favorite &&
      ageMin == null &&
      ageMax == null &&
      nuriAreas.isEmpty;

  /// [age] 살 아이에게 맞는 책인가. 나이를 정하지 않은 책은 어느 나이에도 넣지 않는다 —
  /// "7세 몰아보기"에 아무 책이나 섞이면 목록을 믿을 수 없다.
  bool fitsAge(int age) {
    if (ageMin == null && ageMax == null) return false;
    return (ageMin ?? 0) <= age && age <= (ageMax ?? 99);
  }

  /// 화면에 보일 나이 글자. 예: "5~7세", "6세".
  String? get ageLabel {
    if (ageMin == null && ageMax == null) return null;
    if (ageMin != null && ageMax != null) {
      return ageMin == ageMax ? '$ageMin세' : '$ageMin~$ageMax세';
    }
    return ageMin != null ? '$ageMin세~' : '~$ageMax세';
  }

  BookTags copyWith({
    List<String>? topicIds,
    bool? favorite,
    int? Function()? ageMin,
    int? Function()? ageMax,
    List<NuriArea>? nuriAreas,
  }) => BookTags(
    contentId: contentId,
    topicIds: topicIds ?? this.topicIds,
    favorite: favorite ?? this.favorite,
    ageMin: ageMin == null ? this.ageMin : ageMin(),
    ageMax: ageMax == null ? this.ageMax : ageMax(),
    nuriAreas: nuriAreas ?? this.nuriAreas,
  );

  Map<String, Object?> toJson() => compactMap({
    'id': contentId,
    'topicIds': topicIds,
    'favorite': favorite,
    'ageMin': ageMin,
    'ageMax': ageMax,
    'nuriAreas': [for (final a in nuriAreas) a.name],
  });

  factory BookTags.fromJson(Map<String, Object?> json) {
    // 0~19 밖의 나이는 잘못 들어온 값으로 보고 버린다.
    int? age(Object? v) {
      final n = asIntOrNull(v);
      return n != null && n >= 0 && n < 20 ? n : null;
    }

    var min = age(json['ageMin']);
    var max = age(json['ageMax']);
    if (min != null && max != null && min > max) (min, max) = (max, min);
    final names = asStringList(json['nuriAreas']);
    return BookTags(
      contentId: asString(json['id']),
      topicIds: asStringList(json['topicIds']).toSet().toList(),
      favorite: asBool(json['favorite']),
      ageMin: min,
      ageMax: max,
      nuriAreas: [
        for (final area in NuriArea.values)
          if (names.contains(area.name)) area,
      ],
    );
  }
}

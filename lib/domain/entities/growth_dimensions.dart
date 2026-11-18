import '../../core/json_codec.dart';

/// 성장 6각형의 축 값. 콘텐츠마다 "이 책이 어느 영역을 키우나" 를 태깅한다.
///
/// 각 축은 0~5 가중치다. 재생할 때마다 [ReadingEvent] 가 쌓이고, 통계 화면(M4)이
/// 이 값을 누적해 RadarChart 로 보여준다. **M1 에서도 태깅은 받아 둔다** —
/// 나중에 화면을 켜면 과거 데이터가 이미 있다.
class GrowthDimensions {
  const GrowthDimensions({
    this.language = 0,
    this.math = 0,
    this.science = 0,
    this.art = 0,
    this.social = 0,
    this.physical = 0,
  });

  /// 언어
  final int language;

  /// 수리·연산
  final int math;

  /// 과학·탐구
  final int science;

  /// 예술·창작
  final int art;

  /// 사회성·관계
  final int social;

  /// 신체·건강
  final int physical;

  static const empty = GrowthDimensions();

  /// 축 하나당 허용 범위. UI 슬라이더와 검증이 같은 값을 쓴다.
  static const int minValue = 0;
  static const int maxValue = 5;

  /// 6축 합계. 태깅이 하나도 없으면 0 — 통계에서 제외 판단에 쓴다.
  int get total => language + math + science + art + social + physical;

  bool get isEmpty => total == 0;

  GrowthDimensions copyWith({
    int? language,
    int? math,
    int? science,
    int? art,
    int? social,
    int? physical,
  }) {
    return GrowthDimensions(
      language: language ?? this.language,
      math: math ?? this.math,
      science: science ?? this.science,
      art: art ?? this.art,
      social: social ?? this.social,
      physical: physical ?? this.physical,
    );
  }

  Map<String, Object?> toJson() => {
    'language': language,
    'math': math,
    'science': science,
    'art': art,
    'social': social,
    'physical': physical,
  };

  factory GrowthDimensions.fromJson(Map<String, Object?> json) {
    return GrowthDimensions(
      language: asInt(json['language']),
      math: asInt(json['math']),
      science: asInt(json['science']),
      art: asInt(json['art']),
      social: asInt(json['social']),
      physical: asInt(json['physical']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GrowthDimensions &&
      other.language == language &&
      other.math == math &&
      other.science == science &&
      other.art == art &&
      other.social == social &&
      other.physical == physical;

  @override
  int get hashCode =>
      Object.hash(language, math, science, art, social, physical);
}

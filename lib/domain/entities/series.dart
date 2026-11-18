import '../../core/json_codec.dart';

/// 전집. `index/series.json` 에 목록으로 저장된다.
///
/// 왜 별도 엔티티인가: 출판사 → 전집 → 책 3단 구조에서 전집 정보를 책의 필드로 흉내내면
/// 같은 전집 이름·표지가 책마다 중복 저장되고, 전집명을 고칠 때 전부 찾아 고쳐야 한다.
class Series {
  const Series({
    required this.id,
    required this.title,
    this.publisher,
    this.coverPath,
  });

  final String id;
  final String title;
  final String? publisher;

  /// 전집 표지. `index/` 기준이 아니라 앱 문서 디렉토리 기준 상대 경로.
  final String? coverPath;

  Series copyWith({
    String? id,
    String? title,
    String? publisher,
    String? coverPath,
  }) {
    return Series(
      id: id ?? this.id,
      title: title ?? this.title,
      publisher: publisher ?? this.publisher,
      coverPath: coverPath ?? this.coverPath,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'title': title,
    'publisher': publisher,
    'coverPath': coverPath,
  });

  factory Series.fromJson(Map<String, Object?> json) => Series(
    id: asString(json['id']),
    title: asString(json['title']),
    publisher: asStringOrNull(json['publisher']),
    coverPath: asStringOrNull(json['coverPath']),
  );
}

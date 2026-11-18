import '../../core/json_codec.dart';

/// 저장 플레이리스트. 현재 재생 순서(PlaybackQueue)와 별개다. `index/playlists.json` 에 저장된다.
///
/// [contentIds] 는 참조만 담는다 — 콘텐츠를 복사하지 않으므로 책을 지우면
/// 목록에 죽은 id 가 남는다. 조회 시 실재하는 것만 걸러 쓴다(고아 참조 허용).
/// 왜 허용하나: 즉시 정리하려면 책 삭제 시 모든 플레이리스트를 훑어야 하는데,
/// 그 비용이 죽은 id 하나를 무시하는 비용보다 크다.
class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    required this.createdAt,
    this.coverPath,
    this.contentIds = const [],
  });

  final String id;
  final String title;
  final String? coverPath;
  final List<String> contentIds;
  final DateTime createdAt;

  int get length => contentIds.length;
  bool get isEmpty => contentIds.isEmpty;

  Playlist copyWith({
    String? id,
    String? title,
    String? coverPath,
    List<String>? contentIds,
    DateTime? createdAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      coverPath: coverPath ?? this.coverPath,
      contentIds: contentIds ?? this.contentIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'title': title,
    'coverPath': coverPath,
    'contentIds': contentIds,
    'createdAt': createdAt.toIso8601String(),
  });

  factory Playlist.fromJson(Map<String, Object?> json) => Playlist(
    id: asString(json['id']),
    title: asString(json['title']),
    coverPath: asStringOrNull(json['coverPath']),
    contentIds: asStringList(json['contentIds']),
    createdAt: asDateTime(json['createdAt']),
  );
}

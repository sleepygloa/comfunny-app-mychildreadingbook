import '../../core/json_codec.dart';

/// 동영상의 한 구간 + 자막 (M4).
///
/// 엔티티를 M1 에 정의해 두는 이유: [Content] 가 책과 영상을 하나의 타입으로 다루므로
/// 직렬화 포맷이 처음부터 이 필드를 알고 있어야 한다. 화면만 M4 로 미룬다.
class VideoClip {
  const VideoClip({
    required this.id,
    required this.startMs,
    required this.endMs,
    this.subtitle,
  });

  final String id;
  final int startMs;
  final int endMs;
  final String? subtitle;

  /// 구간 길이. 음수가 나오면 데이터가 잘못된 것이므로 0 으로 막는다.
  int get durationMs => endMs > startMs ? endMs - startMs : 0;

  bool get isValid => endMs > startMs;

  VideoClip copyWith({String? id, int? startMs, int? endMs, String? subtitle}) {
    return VideoClip(
      id: id ?? this.id,
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      subtitle: subtitle ?? this.subtitle,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'startMs': startMs,
    'endMs': endMs,
    'subtitle': subtitle,
  });

  factory VideoClip.fromJson(Map<String, Object?> json) {
    return VideoClip(
      id: asString(json['id']),
      startMs: asInt(json['startMs']),
      endMs: asInt(json['endMs']),
      subtitle: asStringOrNull(json['subtitle']),
    );
  }
}

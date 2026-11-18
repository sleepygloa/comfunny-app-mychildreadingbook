import '../../core/json_codec.dart';

/// 재생 1회 기록. `index/reading_events.json` 에 append 된다.
///
/// **M1 부터 조용히 쌓는다** — 통계 화면은 M4 지만, 나중에 화면을 켜면 과거 데이터가
/// 이미 있어야 한다. 나중에 기록을 시작하면 그 이전 독서 이력이 영원히 비어 있다.
class ReadingEvent {
  const ReadingEvent({
    required this.id,
    required this.contentId,
    required this.startedAt,
    this.childId,
    this.endedAt,
    this.durationSec = 0,
    this.completed = false,
  });

  final String id;
  final String contentId;

  /// 누가 들었나. 다자녀 기능(M2) 전에는 `null` 이다.
  final String? childId;

  final DateTime startedAt;

  /// 재생이 끝난 시각. 앱이 강제 종료되면 `null` 로 남는다.
  final DateTime? endedAt;

  /// 실제 들은 시간(초). [endedAt] 과 별도로 두는 이유는 일시정지·이탈 때문에
  /// 종료−시작 이 실제 청취 시간과 다르기 때문이다.
  final int durationSec;

  /// 끝까지 들었나. 통계에서 "완독" 판정에 쓴다.
  final bool completed;

  /// 기록이 정상 종료됐나. `false` 면 앱이 중간에 죽은 것이다.
  bool get isClosed => endedAt != null;

  ReadingEvent copyWith({
    String? id,
    String? contentId,
    String? childId,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSec,
    bool? completed,
  }) {
    return ReadingEvent(
      id: id ?? this.id,
      contentId: contentId ?? this.contentId,
      childId: childId ?? this.childId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      durationSec: durationSec ?? this.durationSec,
      completed: completed ?? this.completed,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'contentId': contentId,
    'childId': childId,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'durationSec': durationSec,
    'completed': completed,
  });

  factory ReadingEvent.fromJson(Map<String, Object?> json) => ReadingEvent(
    id: asString(json['id']),
    contentId: asString(json['contentId']),
    childId: asStringOrNull(json['childId']),
    startedAt: asDateTime(json['startedAt']),
    endedAt: asDateTimeOrNull(json['endedAt']),
    durationSec: asInt(json['durationSec']),
    completed: asBool(json['completed']),
  );
}

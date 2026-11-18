/// JSON 파싱 헬퍼 — **방어적으로** 읽는다.
///
/// 왜 이 파일이 있는가 (AGENTS.md §3 `fromJson` 방어 규칙):
/// 이 앱은 로컬 우선이라 사용자 기기의 JSON 파일이 유일한 진실이다. 앱을 다운그레이드하거나
/// 스키마를 바꾼 뒤 구버전 파일을 만났을 때 **파싱이 죽으면 사용자가 만든 책이 사라진다.**
/// 그래서 모르는 값·없는 값·타입이 다른 값을 만나도 예외를 던지지 않고 기본값으로 흘린다.
library;

/// 문자열로 읽되 값이 없거나 타입이 다르면 `null`.
String? asStringOrNull(Object? v) => v is String ? v : null;

/// 문자열로 읽되 없으면 [fallback].
String asString(Object? v, {String fallback = ''}) =>
    v is String ? v : fallback;

/// 정수로 읽는다. JSON 이 `1.0` 처럼 실수로 저장된 경우도 받아준다.
int? asIntOrNull(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

int asInt(Object? v, {int fallback = 0}) => asIntOrNull(v) ?? fallback;

bool asBool(Object? v, {bool fallback = false}) => v is bool ? v : fallback;

/// ISO 8601 문자열 → [DateTime]. 파싱 실패 시 `null`.
DateTime? asDateTimeOrNull(Object? v) {
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// ISO 8601 문자열 → [DateTime]. 실패 시 [fallback] (기본: epoch).
///
/// 왜 epoch 을 쓰는가: `DateTime.now()` 를 기본값으로 쓰면 매번 값이 달라져
/// round-trip 테스트가 불안정해지고, 정렬 결과가 실행마다 바뀐다.
DateTime asDateTime(Object? v, {DateTime? fallback}) =>
    asDateTimeOrNull(v) ?? fallback ?? DateTime.fromMillisecondsSinceEpoch(0);

/// `Map<String, Object?>` 로 안전하게 좁힌다.
Map<String, Object?> asMap(Object? v) =>
    v is Map ? v.map((k, value) => MapEntry(k.toString(), value)) : const {};

/// 리스트를 [item] 으로 변환한다. **변환에 실패한 요소는 조용히 버린다.**
///
/// 왜 버리는가: 한 페이지의 오디오 트랙 하나가 깨졌다고 책 전체를 못 읽게 만들면
/// 손실이 훨씬 크다. 부분 손실을 감수하고 나머지를 살린다.
List<T> asList<T>(Object? v, T? Function(Object?) item) {
  if (v is! List) return const [];
  final out = <T>[];
  for (final e in v) {
    final parsed = item(e);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

List<String> asStringList(Object? v) =>
    asList<String>(v, (e) => e is String ? e : null);

/// enum 이름 문자열 → enum 값. **모르는 값이면 [fallback].**
///
/// 왜 index 가 아니라 name 을 저장하는가: enum 순서를 바꾸면 index 기반 데이터가
/// 전부 다른 값으로 읽힌다(조용한 데이터 오염). name 은 순서 변경에 안전하다.
T enumFromName<T extends Enum>(
  Object? v,
  List<T> values, {
  required T fallback,
}) {
  if (v is String) {
    for (final e in values) {
      if (e.name == v) return e;
    }
  }
  return fallback;
}

/// `null` 값을 제거한 맵을 만든다.
///
/// 왜 제거하는가: 파일 크기를 줄이고, "필드가 없음" 과 "명시적 null" 을 구분할 필요가
/// 없는 이 앱에서는 없는 편이 읽기 쉽다.
Map<String, Object?> compactMap(Map<String, Object?> src) {
  final out = <String, Object?>{};
  src.forEach((k, v) {
    if (v != null) out[k] = v;
  });
  return out;
}

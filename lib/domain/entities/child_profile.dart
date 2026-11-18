import '../../core/json_codec.dart';

/// 아이 프로필 (M2 화면, 엔티티는 M1 부터).
///
/// ⚠️ **[A-06-7] 아동 개인정보 특칙 대상이다.**
/// - 보호자 계정에 **종속**된다. 아이용 로그인 경로를 만들지 않는다
/// - 수집 항목을 최소로 유지한다 — 이름과 (선택) 생일뿐
/// - **이 값을 어떤 외부 페이로드에도 넣지 않는다.** AI 작업 요청에도 포함하지 않는다
class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.name,
    this.birthDate,
    this.avatarPath,
  });

  final String id;

  /// 아이 이름 또는 애칭. **실명을 강제하지 않는다** (최소 수집 원칙).
  final String name;

  /// 생일. 연령 표시·추천에만 쓰며 **필수가 아니다**.
  final DateTime? birthDate;

  final String? avatarPath;

  /// 만 나이. 생일이 없으면 `null`.
  ///
  /// 왜 계산해서 저장하지 않나: 나이는 시간이 지나면 변한다. 저장하면 낡는다.
  int? ageAt(DateTime now) {
    final b = birthDate;
    if (b == null) return null;
    var age = now.year - b.year;
    // 생일이 아직 안 지났으면 한 살 뺀다.
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) {
      age -= 1;
    }
    return age < 0 ? 0 : age;
  }

  ChildProfile copyWith({
    String? id,
    String? name,
    DateTime? birthDate,
    String? avatarPath,
  }) {
    return ChildProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'name': name,
    'birthDate': birthDate?.toIso8601String(),
    'avatarPath': avatarPath,
  });

  factory ChildProfile.fromJson(Map<String, Object?> json) => ChildProfile(
    id: asString(json['id']),
    name: asString(json['name']),
    birthDate: asDateTimeOrNull(json['birthDate']),
    avatarPath: asStringOrNull(json['avatarPath']),
  );
}

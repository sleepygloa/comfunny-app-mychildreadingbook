import '../../core/json_codec.dart';
import '../enums/enums.dart';

/// 등록된 목소리 하나 (M3). 엄마·아빠·조부모를 각각 등록할 수 있다.
///
/// ⚠️ **목소리는 생체정보다** ([A-06] · [1_DESIGN §1.6]).
/// - 샘플 파일은 워커가 가져간 뒤 **Storage 에서 삭제**한다
/// - 합성은 **로컬 GPU 에서만** — 클라우드로 보내지 않는다
///
/// 엔티티를 M1 에 정의해 두는 이유: [AudioTrack.voiceProfileId] 가 이걸 참조하므로
/// 저장 포맷이 처음부터 알고 있어야 한다.
class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.label,
    required this.registeredAt,
    this.status = VoiceStatus.pending,
    this.remoteVoiceId,
    this.failureReason,
  });

  final String id;

  /// 사용자에게 보이는 이름 — '엄마', '아빠' 등.
  final String label;

  final VoiceStatus status;

  /// 워커가 발급한 참조 식별자. 책 음원을 신청할 때 이 값을 보낸다.
  ///
  /// XTTS 는 zero-shot 참조 방식이라 **"학습된 모델"이 아니라 참조 샘플 식별자**다
  /// ([1_DESIGN ADR-5]).
  final String? remoteVoiceId;

  /// 검증 실패 사유 (샘플 품질 부족 등). 사용자에게 재녹음을 안내하는 근거.
  final String? failureReason;

  final DateTime registeredAt;

  /// 이 목소리로 책 음원을 만들 수 있나.
  bool get isUsable =>
      status == VoiceStatus.ready &&
      remoteVoiceId != null &&
      remoteVoiceId!.isNotEmpty;

  VoiceProfile copyWith({
    String? id,
    String? label,
    VoiceStatus? status,
    String? remoteVoiceId,
    String? failureReason,
    DateTime? registeredAt,
  }) {
    return VoiceProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      status: status ?? this.status,
      remoteVoiceId: remoteVoiceId ?? this.remoteVoiceId,
      failureReason: failureReason ?? this.failureReason,
      registeredAt: registeredAt ?? this.registeredAt,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'label': label,
    'status': status.name,
    'remoteVoiceId': remoteVoiceId,
    'failureReason': failureReason,
    'registeredAt': registeredAt.toIso8601String(),
  });

  factory VoiceProfile.fromJson(Map<String, Object?> json) => VoiceProfile(
    id: asString(json['id']),
    label: asString(json['label']),
    // 모르는 상태는 pending 으로 흘린다 — ready 로 흘리면 쓸 수 없는 목소리를
    // 사용 가능한 것으로 보여주게 된다.
    status: enumFromName(
      json['status'],
      VoiceStatus.values,
      fallback: VoiceStatus.pending,
    ),
    remoteVoiceId: asStringOrNull(json['remoteVoiceId']),
    failureReason: asStringOrNull(json['failureReason']),
    registeredAt: asDateTime(json['registeredAt']),
  );
}

import '../../core/json_codec.dart';
import '../enums/enums.dart';

/// 한 페이지의 오디오 하나.
///
/// **한 페이지가 여러 트랙을 동시에 보유한다** — 기기TTS·부모녹음·AI목소리를 함께 두고
/// 재생 중 전환하는 것이 이 앱 설계의 중심이다([1_DESIGN §1.1]).
class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.source,
    required this.createdAt,
    this.path,
    this.voiceProfileId,
    this.durationMs,
  });

  final String id;
  final AudioSource source;

  /// 콘텐츠 폴더 기준 **상대 경로** (`audio/xxx.mp3`).
  ///
  /// ⚠️ [AudioSource.deviceTts] 는 런타임 합성이라 **파일이 없다 → `null`**.
  /// 그래서 이 트랙은 백업에 담기지 않고 재생 길이를 미리 알 수 없다.
  ///
  /// 왜 절대 경로가 아닌가: iOS 앱 문서 디렉토리 경로는 재설치·복원 시 바뀐다.
  /// 절대 경로를 저장하면 백업 복구 후 전부 깨진다.
  final String? path;

  /// 어느 목소리로 만들었나 ([AudioSource.aiClonedVoice] 일 때). M3
  final String? voiceProfileId;

  /// 재생 길이. 알 수 없으면 `null` (기기 TTS).
  final int? durationMs;

  final DateTime createdAt;

  /// 재생 가능한 파일을 갖고 있나. 기기 TTS 는 `false` 지만 재생은 된다.
  bool get hasFile => path != null && path!.isNotEmpty;

  AudioTrack copyWith({
    String? id,
    AudioSource? source,
    String? path,
    String? voiceProfileId,
    int? durationMs,
    DateTime? createdAt,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      source: source ?? this.source,
      path: path ?? this.path,
      voiceProfileId: voiceProfileId ?? this.voiceProfileId,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'source': source.name,
    'path': path,
    'voiceProfileId': voiceProfileId,
    'durationMs': durationMs,
    'createdAt': createdAt.toIso8601String(),
  });

  factory AudioTrack.fromJson(Map<String, Object?> json) {
    return AudioTrack(
      id: asString(json['id']),
      // 모르는 source 를 만나면 deviceTts 로 흘린다 — 텍스트만 있으면 재생은 되므로
      // 사용자가 완전히 막히지 않는다.
      source: enumFromName(
        json['source'],
        AudioSource.values,
        fallback: AudioSource.deviceTts,
      ),
      path: asStringOrNull(json['path']),
      voiceProfileId: asStringOrNull(json['voiceProfileId']),
      durationMs: asIntOrNull(json['durationMs']),
      createdAt: asDateTime(json['createdAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AudioTrack &&
      other.id == id &&
      other.source == source &&
      other.path == path &&
      other.voiceProfileId == voiceProfileId &&
      other.durationMs == durationMs &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(id, source, path, voiceProfileId, durationMs, createdAt);
}

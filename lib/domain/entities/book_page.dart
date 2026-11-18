import '../../core/json_codec.dart';
import '../enums/enums.dart';
import 'audio_track.dart';

/// 책의 한 페이지 — 사진 + 텍스트 + 오디오 트랙들.
class BookPage {
  const BookPage({
    required this.id,
    required this.orderIndex,
    required this.imagePath,
    this.text,
    this.tracks = const [],
  });

  final String id;

  /// 페이지 순서 (0부터). 리오더는 이 값을 다시 매긴다.
  final int orderIndex;

  /// 콘텐츠 폴더 기준 **상대 경로** (`pages/page_000.jpg`).
  final String imagePath;

  /// 페이지 본문. M1 은 수동 입력, M2 부터 OCR 로 채운다.
  ///
  /// 텍스트가 없으면 **기기 TTS 를 만들 수 없다** — 부모 녹음만 가능하다.
  final String? text;

  final List<AudioTrack> tracks;

  bool get hasText => text != null && text!.trim().isNotEmpty;

  /// 재생할 트랙을 고른다. [preferred] 가 있으면 그 종류를 우선한다.
  ///
  /// 기본 우선순위: `parentRecording` → `aiClonedVoice` → `aiNarration` → `deviceTts`
  ///
  /// **왜 `deviceTts` 가 마지막인가:** 텍스트만 있으면 항상 만들 수 있어 최후의 폴백이다.
  /// 그래서 재생이 불가능한 페이지가 생기지 않는다. 순서를 바꾸면 이 성질이 깨진다.
  /// 부모 목소리를 최우선에 둔 것은 이 앱의 본질이 그것이기 때문이다.
  AudioTrack? selectTrack({AudioSource? preferred}) {
    // FLOW 1: 사용자가 명시 선택한 종류가 있으면 그것을 먼저 찾는다.
    if (preferred != null) {
      final picked = _firstOf(preferred);
      if (picked != null) return picked;
    }
    // FLOW 2: 기본 우선순위대로 훑는다.
    for (final source in const [
      AudioSource.parentRecording,
      AudioSource.aiClonedVoice,
      AudioSource.aiNarration,
      AudioSource.deviceTts,
    ]) {
      final picked = _firstOf(source);
      if (picked != null) return picked;
    }
    // FLOW 9: 트랙이 하나도 없다. 텍스트가 있으면 호출자가 기기 TTS 를 즉석 생성할 수 있다.
    return null;
  }

  /// 해당 종류의 트랙 중 **가장 최근에 만든 것**.
  ///
  /// 왜 최신인가: 부모가 다시 녹음했다면 새 녹음을 들려주는 것이 기대에 맞다.
  AudioTrack? _firstOf(AudioSource source) {
    AudioTrack? best;
    for (final t in tracks) {
      if (t.source != source) continue;
      // deviceTts 는 파일이 없어도 유효하다. 나머지는 파일이 있어야 재생된다.
      if (source != AudioSource.deviceTts && !t.hasFile) continue;
      if (best == null || t.createdAt.isAfter(best.createdAt)) best = t;
    }
    return best;
  }

  BookPage copyWith({
    String? id,
    int? orderIndex,
    String? imagePath,
    String? text,
    List<AudioTrack>? tracks,
  }) {
    return BookPage(
      id: id ?? this.id,
      orderIndex: orderIndex ?? this.orderIndex,
      imagePath: imagePath ?? this.imagePath,
      text: text ?? this.text,
      tracks: tracks ?? this.tracks,
    );
  }

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'orderIndex': orderIndex,
    'imagePath': imagePath,
    'text': text,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  });

  factory BookPage.fromJson(Map<String, Object?> json) {
    return BookPage(
      id: asString(json['id']),
      orderIndex: asInt(json['orderIndex']),
      imagePath: asString(json['imagePath']),
      text: asStringOrNull(json['text']),
      tracks: asList(
        json['tracks'],
        (e) => e is Map ? AudioTrack.fromJson(asMap(e)) : null,
      ),
    );
  }
}

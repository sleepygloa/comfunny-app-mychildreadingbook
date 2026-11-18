import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/json_codec.dart';
import 'package:mychild_reading/domain/entities/audio_track.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/child_profile.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/growth_dimensions.dart';
import 'package:mychild_reading/domain/entities/playlist.dart';
import 'package:mychild_reading/domain/entities/reading_event.dart';
import 'package:mychild_reading/domain/entities/series.dart';
import 'package:mychild_reading/domain/entities/video_clip.dart';
import 'package:mychild_reading/domain/entities/voice_profile.dart';
import 'package:mychild_reading/domain/enums/enums.dart';

/// 직렬화 round-trip 검증.
///
/// **왜 이 테스트가 1순위인가** ([3_TEST §3.1]):
/// 이 앱은 로컬 우선이라 모든 데이터가 JSON 파일로 오간다. 직렬화가 깨지면
/// 사용자가 만든 책과 녹음이 사라진다. 과거 이 프로젝트에서 실제로 코드 생성기 설정
/// 누락으로 중첩 리스트가 변환되지 않아 저장이 조용히 실패한 사고가 있었다.
///
/// 실제 파일 저장을 흉내내기 위해 **`jsonEncode`/`jsonDecode` 를 통과시킨다** —
/// `toJson()` 결과를 그대로 `fromJson` 에 넣으면 "JSON 으로 표현 불가한 값"(DateTime 객체 등)이
/// 섞여 있어도 통과해 버린다. 그 함정을 여기서 막는다.
void main() {
  /// toJson → jsonEncode → jsonDecode → fromJson 을 통과시킨다.
  Map<String, Object?> cycle(Map<String, Object?> json) =>
      asMap(jsonDecode(jsonEncode(json)));

  group('GrowthDimensions', () {
    test('6축 값이 보존된다', () {
      const src = GrowthDimensions(
        language: 5,
        math: 3,
        science: 2,
        art: 4,
        social: 1,
        physical: 0,
      );
      final out = GrowthDimensions.fromJson(cycle(src.toJson()));

      expect(out, src);
      expect(out.total, 15);
      expect(out.isEmpty, isFalse);
    });

    test('필드가 전부 없으면 기본값 0 이고 isEmpty 다', () {
      final out = GrowthDimensions.fromJson(const {});
      expect(out, GrowthDimensions.empty);
      expect(out.isEmpty, isTrue);
    });
  });

  group('AudioTrack', () {
    test('부모 녹음 트랙 round-trip', () {
      final src = AudioTrack(
        id: 't1',
        source: AudioSource.parentRecording,
        path: 'audio/p1_parentRecording.m4a',
        durationMs: 12345,
        createdAt: DateTime.utc(2026, 9, 12, 10, 30),
      );
      final out = AudioTrack.fromJson(cycle(src.toJson()));

      expect(out, src);
      expect(out.hasFile, isTrue);
    });

    test('기기 TTS 트랙은 path 가 null 이고 hasFile 이 false 다', () {
      final src = AudioTrack(
        id: 't2',
        source: AudioSource.deviceTts,
        createdAt: DateTime.utc(2026, 9, 12),
      );
      final json = src.toJson();

      // compactMap 이 null 을 제거하므로 키 자체가 없어야 한다.
      expect(json.containsKey('path'), isFalse);
      expect(json.containsKey('durationMs'), isFalse);

      final out = AudioTrack.fromJson(cycle(json));
      expect(out.path, isNull);
      expect(out.hasFile, isFalse);
      expect(out.source, AudioSource.deviceTts);
    });

    test('AI 목소리 트랙은 voiceProfileId 를 보존한다', () {
      final src = AudioTrack(
        id: 't3',
        source: AudioSource.aiClonedVoice,
        path: 'audio/p1_ai.mp3',
        voiceProfileId: 'v-mom',
        createdAt: DateTime.utc(2026, 9, 12),
      );
      final out = AudioTrack.fromJson(cycle(src.toJson()));
      expect(out.voiceProfileId, 'v-mom');
      expect(out.source, AudioSource.aiClonedVoice);
    });

    test('모르는 source 문자열은 deviceTts 로 흘린다 (다운그레이드 안전)', () {
      final out = AudioTrack.fromJson({
        'id': 't4',
        'source': 'someFutureSource',
        'createdAt': '2026-09-12T00:00:00.000Z',
      });
      expect(out.source, AudioSource.deviceTts);
    });
  });

  group('BookPage', () {
    test('멀티 오디오 트랙이 전부 보존된다 (중첩 리스트 회귀 방지)', () {
      final src = BookPage(
        id: 'p1',
        orderIndex: 0,
        imagePath: 'pages/page_000.jpg',
        text: '옛날 옛적에',
        tracks: [
          AudioTrack(
            id: 'a1',
            source: AudioSource.deviceTts,
            createdAt: DateTime.utc(2026, 9, 1),
          ),
          AudioTrack(
            id: 'a2',
            source: AudioSource.parentRecording,
            path: 'audio/p1_rec.m4a',
            createdAt: DateTime.utc(2026, 9, 2),
          ),
        ],
      );
      final out = BookPage.fromJson(cycle(src.toJson()));

      expect(out.tracks.length, 2);
      expect(out.tracks.map((t) => t.source),
          containsAll([AudioSource.deviceTts, AudioSource.parentRecording]));
      expect(out.hasText, isTrue);
    });

    test('텍스트가 없으면 hasText 가 false 다 (기기 TTS 불가 신호)', () {
      final out = BookPage.fromJson({
        'id': 'p2',
        'orderIndex': 1,
        'imagePath': 'pages/page_001.jpg',
      });
      expect(out.hasText, isFalse);
      expect(out.tracks, isEmpty);
    });

    test('깨진 트랙 요소는 버리고 나머지를 살린다', () {
      final out = BookPage.fromJson({
        'id': 'p3',
        'orderIndex': 0,
        'imagePath': 'pages/page_000.jpg',
        'tracks': [
          'not-a-map',
          {
            'id': 'ok',
            'source': 'parentRecording',
            'path': 'audio/x.m4a',
            'createdAt': '2026-09-12T00:00:00.000Z',
          },
          42,
        ],
      });
      expect(out.tracks.length, 1);
      expect(out.tracks.single.id, 'ok');
    });
  });

  group('BookPage.selectTrack — 트랙 우선순위', () {
    AudioTrack track(AudioSource s, {String? path, DateTime? at}) => AudioTrack(
          id: '${s.name}-${at?.day ?? 0}',
          source: s,
          path: path,
          createdAt: at ?? DateTime.utc(2026, 9, 1),
        );

    test('부모 녹음이 기기 TTS 보다 우선한다', () {
      final page = BookPage(
        id: 'p',
        orderIndex: 0,
        imagePath: 'i.jpg',
        tracks: [
          track(AudioSource.deviceTts),
          track(AudioSource.parentRecording, path: 'a.m4a'),
        ],
      );
      expect(page.selectTrack()?.source, AudioSource.parentRecording);
    });

    test('명시 선택한 종류가 최우선이다', () {
      final page = BookPage(
        id: 'p',
        orderIndex: 0,
        imagePath: 'i.jpg',
        tracks: [
          track(AudioSource.deviceTts),
          track(AudioSource.parentRecording, path: 'a.m4a'),
        ],
      );
      expect(
        page.selectTrack(preferred: AudioSource.deviceTts)?.source,
        AudioSource.deviceTts,
      );
    });

    test('기기 TTS 는 파일이 없어도 선택된다 — 최후의 폴백', () {
      final page = BookPage(
        id: 'p',
        orderIndex: 0,
        imagePath: 'i.jpg',
        tracks: [track(AudioSource.deviceTts)],
      );
      expect(page.selectTrack()?.source, AudioSource.deviceTts);
    });

    test('파일 없는 녹음 트랙은 건너뛴다', () {
      final page = BookPage(
        id: 'p',
        orderIndex: 0,
        imagePath: 'i.jpg',
        tracks: [
          track(AudioSource.parentRecording), // path 없음 = 깨진 트랙
          track(AudioSource.deviceTts),
        ],
      );
      expect(page.selectTrack()?.source, AudioSource.deviceTts);
    });

    test('같은 종류가 여러 개면 가장 최근 것을 고른다', () {
      final page = BookPage(
        id: 'p',
        orderIndex: 0,
        imagePath: 'i.jpg',
        tracks: [
          track(AudioSource.parentRecording,
              path: 'old.m4a', at: DateTime.utc(2026, 9, 1)),
          track(AudioSource.parentRecording,
              path: 'new.m4a', at: DateTime.utc(2026, 9, 10)),
        ],
      );
      expect(page.selectTrack()?.path, 'new.m4a');
    });

    test('트랙이 없으면 null — 호출자가 기기 TTS 를 즉석 생성한다', () {
      const page = BookPage(id: 'p', orderIndex: 0, imagePath: 'i.jpg');
      expect(page.selectTrack(), isNull);
    });
  });

  group('Content', () {
    Content sampleBook() => Content(
          id: 'c1',
          type: ContentType.pagedBook,
          title: '아기 돼지 삼형제',
          author: '작자미상',
          publisher: '테스트출판',
          seriesId: 's1',
          volume: 3,
          coverPath: 'cover.jpg',
          tags: const ['동화', '반복읽기'],
          dimensions: const GrowthDimensions(language: 5, social: 3),
          pages: [
            BookPage(
              id: 'p1',
              orderIndex: 1,
              imagePath: 'pages/page_001.jpg',
              text: '두 번째 페이지',
              tracks: [
                AudioTrack(
                  id: 'a1',
                  source: AudioSource.parentRecording,
                  path: 'audio/p1.m4a',
                  createdAt: DateTime.utc(2026, 9, 5),
                ),
              ],
            ),
            const BookPage(
              id: 'p0',
              orderIndex: 0,
              imagePath: 'pages/page_000.jpg',
              text: '첫 번째 페이지',
            ),
          ],
          createdAt: DateTime.utc(2026, 9, 1, 9),
          updatedAt: DateTime.utc(2026, 9, 12, 18, 45),
        );

    test('책 round-trip — 중첩 3단(Content→BookPage→AudioTrack) 보존', () {
      final src = sampleBook();
      final out = Content.fromJson(cycle(src.toJson()));

      expect(out.id, src.id);
      expect(out.type, ContentType.pagedBook);
      expect(out.title, src.title);
      expect(out.volume, 3);
      expect(out.tags, src.tags);
      expect(out.dimensions, src.dimensions);
      expect(out.pageCount, 2);
      expect(out.pages.firstWhere((p) => p.id == 'p1').tracks.length, 1);
      expect(out.createdAt, src.createdAt);
      expect(out.updatedAt, src.updatedAt);
    });

    test('orderedPages 는 저장 순서가 아니라 orderIndex 로 정렬한다', () {
      final out = Content.fromJson(cycle(sampleBook().toJson()));
      expect(out.pages.first.id, 'p1'); // 저장 순서
      expect(out.orderedPages.map((p) => p.id), ['p0', 'p1']);
    });

    test('영상 콘텐츠 round-trip', () {
      final src = Content(
        id: 'c2',
        type: ContentType.video,
        title: '동물원 나들이',
        videoPath: 'video.mp4',
        clips: const [
          VideoClip(id: 'v1', startMs: 1000, endMs: 4000, subtitle: '기린이다'),
        ],
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      final out = Content.fromJson(cycle(src.toJson()));

      expect(out.isVideo, isTrue);
      expect(out.videoPath, 'video.mp4');
      expect(out.clips.single.durationMs, 3000);
      expect(out.clips.single.subtitle, '기린이다');
      expect(out.isPlayable, isTrue);
    });

    test('페이지 없는 책은 isPlayable 이 false 다', () {
      final out = Content(
        id: 'c3',
        type: ContentType.pagedBook,
        title: '빈 책',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );
      expect(out.isPlayable, isFalse);
    });

    test('모르는 type 은 pagedBook 으로 흘린다', () {
      final out = Content.fromJson({
        'id': 'c4',
        'type': 'hologram',
        'title': '미래 콘텐츠',
        'createdAt': '2026-09-01T00:00:00.000Z',
        'updatedAt': '2026-09-01T00:00:00.000Z',
      });
      expect(out.type, ContentType.pagedBook);
    });

    test('경량 메타에는 미디어 경로가 들어가지 않는다 [A-06-7]', () {
      final meta = sampleBook().toMetadataJson();

      // 클라우드로 나가는 페이로드다. 미디어·본문이 섞이면 안 된다.
      expect(meta.containsKey('coverPath'), isFalse);
      expect(meta.containsKey('pages'), isFalse);
      expect(meta.containsKey('videoPath'), isFalse);
      expect(meta.containsKey('clips'), isFalse);
      // 대신 개수만 담는다.
      expect(meta['pageCount'], 2);
      expect(meta['title'], '아기 돼지 삼형제');

      // JSON 으로 직렬화 가능해야 한다 (Firestore 전송 전제).
      expect(() => jsonEncode(meta), returnsNormally);
    });
  });

  group('Series · Playlist · ChildProfile · ReadingEvent · VoiceProfile', () {
    test('Series round-trip', () {
      const src = Series(
        id: 's1',
        title: '세계명작동화',
        publisher: '테스트출판',
        coverPath: 'series/s1.jpg',
      );
      final out = Series.fromJson(cycle(src.toJson()));
      expect(out.title, src.title);
      expect(out.publisher, src.publisher);
      expect(out.coverPath, src.coverPath);
    });

    test('Playlist round-trip — contentIds 참조 목록', () {
      final src = Playlist(
        id: 'pl1',
        title: '잠자기 전',
        contentIds: const ['c1', 'c2', 'c3'],
        createdAt: DateTime.utc(2026, 9, 3),
      );
      final out = Playlist.fromJson(cycle(src.toJson()));
      expect(out.contentIds, ['c1', 'c2', 'c3']);
      expect(out.length, 3);
      expect(out.isEmpty, isFalse);
    });

    test('ChildProfile round-trip + 만 나이 계산', () {
      final src = ChildProfile(
        id: 'ch1',
        name: '첫째',
        birthDate: DateTime.utc(2020, 6, 15),
      );
      final out = ChildProfile.fromJson(cycle(src.toJson()));

      expect(out.name, '첫째');
      // 생일 지난 뒤
      expect(out.ageAt(DateTime.utc(2026, 9, 12)), 6);
      // 생일 전
      expect(out.ageAt(DateTime.utc(2026, 6, 14)), 5);
    });

    test('ChildProfile 은 생일 없이도 유효하다 (최소 수집)', () {
      final out = ChildProfile.fromJson({'id': 'ch2', 'name': '둘째'});
      expect(out.birthDate, isNull);
      expect(out.ageAt(DateTime.utc(2026, 9, 12)), isNull);
    });

    test('ReadingEvent round-trip — 미종료 기록도 유효하다', () {
      final src = ReadingEvent(
        id: 'e1',
        contentId: 'c1',
        childId: 'ch1',
        startedAt: DateTime.utc(2026, 9, 12, 20),
        durationSec: 0,
      );
      final out = ReadingEvent.fromJson(cycle(src.toJson()));

      expect(out.contentId, 'c1');
      expect(out.childId, 'ch1');
      expect(out.endedAt, isNull);
      expect(out.isClosed, isFalse); // 앱이 중간에 죽은 경우
      expect(out.completed, isFalse);
    });

    test('VoiceProfile — ready + remoteVoiceId 가 있어야 isUsable', () {
      final ready = VoiceProfile(
        id: 'v1',
        label: '엄마',
        status: VoiceStatus.ready,
        remoteVoiceId: 'xtts-ref-1',
        registeredAt: DateTime.utc(2026, 9, 10),
      );
      final out = VoiceProfile.fromJson(cycle(ready.toJson()));
      expect(out.isUsable, isTrue);

      final pending = out.copyWith(status: VoiceStatus.pending);
      expect(pending.isUsable, isFalse);
    });

    test('VoiceProfile 모르는 status 는 pending 으로 흘린다 (ready 로 흘리면 위험)', () {
      final out = VoiceProfile.fromJson({
        'id': 'v2',
        'label': '아빠',
        'status': 'trainingV2',
        'remoteVoiceId': 'x',
        'registeredAt': '2026-09-10T00:00:00.000Z',
      });
      expect(out.status, VoiceStatus.pending);
      expect(out.isUsable, isFalse);
    });
  });

  group('방어적 파싱 — 빈 맵에서도 죽지 않는다', () {
    test('전 엔티티가 빈 맵을 받아도 예외를 던지지 않는다', () {
      expect(() => Content.fromJson(const {}), returnsNormally);
      expect(() => BookPage.fromJson(const {}), returnsNormally);
      expect(() => AudioTrack.fromJson(const {}), returnsNormally);
      expect(() => Series.fromJson(const {}), returnsNormally);
      expect(() => Playlist.fromJson(const {}), returnsNormally);
      expect(() => ChildProfile.fromJson(const {}), returnsNormally);
      expect(() => ReadingEvent.fromJson(const {}), returnsNormally);
      expect(() => VoiceProfile.fromJson(const {}), returnsNormally);
      expect(() => VideoClip.fromJson(const {}), returnsNormally);
      expect(() => GrowthDimensions.fromJson(const {}), returnsNormally);
    });

    test('타입이 어긋난 값도 기본값으로 흘린다', () {
      final out = Content.fromJson({
        'id': 123, // 숫자
        'title': ['배열'], // 배열
        'pages': 'not-a-list', // 문자열
        'dimensions': 'nope',
        'tags': [1, 'ok', null],
        'createdAt': 'invalid-date',
      });
      expect(out.id, ''); // fallback
      expect(out.title, '');
      expect(out.pages, isEmpty);
      expect(out.dimensions, GrowthDimensions.empty);
      expect(out.tags, ['ok']); // 문자열만 살린다
      expect(out.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/domain/entities/audio_track.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/voice_samples.dart';
import 'package:mychild_reading/domain/enums/enums.dart';

final _at = DateTime.utc(2026, 11, 22);

AudioTrack _rec(int? ms) => AudioTrack(
  id: 'r$ms',
  source: AudioSource.parentRecording,
  path: 'audio/r.m4a',
  durationMs: ms,
  createdAt: _at,
);

Content book(String id, List<BookPage> pages, {ContentType? type}) => Content(
  id: id,
  type: type ?? ContentType.pagedBook,
  title: '책 $id',
  createdAt: _at,
  updatedAt: _at,
  pages: pages,
);

void main() {
  test('녹음과 글이 함께 있는 쪽만 자료로 세고 길이를 더한다', () {
    final summary = VoiceSampleSummary.fromContents([
      book('a', [
        BookPage(
          id: '1',
          orderIndex: 0,
          imagePath: 'p',
          text: '곰',
          tracks: [_rec(30000)],
        ),
        BookPage(
          id: '2',
          orderIndex: 1,
          imagePath: 'p',
          text: '숲',
          tracks: [_rec(null)],
        ),
        // 글 없는 녹음 — 자료가 아니다
        BookPage(id: '3', orderIndex: 2, imagePath: 'p', tracks: [_rec(10000)]),
        // 기기 읽기만 — 보호자 녹음이 아니다
        BookPage(
          id: '4',
          orderIndex: 3,
          imagePath: 'p',
          text: '별',
          tracks: [
            AudioTrack(id: 't', source: AudioSource.deviceTts, createdAt: _at),
          ],
        ),
      ]),
      book('b', [
        BookPage(
          id: '5',
          orderIndex: 0,
          imagePath: 'p',
          text: '달',
          tracks: [_rec(90000)],
        ),
      ]),
      book('v', [
        BookPage(
          id: '6',
          orderIndex: 0,
          imagePath: 'p',
          text: '영상',
          tracks: [_rec(60000)],
        ),
      ], type: ContentType.video),
    ]);
    expect(summary.pairedPages, 3);
    expect(summary.recordedWithoutText, 1);
    expect(summary.knownMs, 120000);
    expect(summary.unknownLength, 1);
    expect(summary.books.map((b) => b.contentId), ['a', 'b']);
    expect(summary.progress, closeTo(120000 / (20 * 60000), 1e-9));
    expect(summary.reachedTarget, isFalse);
  });

  test('20분을 넘으면 다 모인 것으로 본다', () {
    final summary = VoiceSampleSummary.fromContents([
      book('a', [
        BookPage(
          id: '1',
          orderIndex: 0,
          imagePath: 'p',
          text: '곰',
          tracks: [_rec(21 * 60000)],
        ),
      ]),
    ]);
    expect(summary.reachedTarget, isTrue);
    expect(summary.progress, 1);
  });
}

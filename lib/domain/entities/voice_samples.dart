import '../enums/enums.dart';
import 'content.dart';

/// 내 목소리 만들기에 쓸 자료 = **보호자 직접 녹음 + 그 쪽의 글** 짝.
///
/// 왜 저장하지 않고 매번 세나: 녹음과 글은 이미 책(`Content`) 안에 있다. 따로 목록을 두면
/// 책을 고치거나 지울 때마다 맞춰야 하고, 어긋나면 엉뚱한 글로 목소리를 배운다.
/// 책에서 바로 세면 늘 지금 책장과 같다 (2026-11-22, 오너 결정 "녹음과 글을 짝으로 모으기부터").
///
/// 아이 목소리 · 사진은 자료가 아니다 — 보호자 녹음(`parentRecording`)만 센다 `[A-06-7]`.
class VoiceSampleSummary {
  const VoiceSampleSummary({
    required this.books,
    required this.pairedPages,
    required this.recordedWithoutText,
    required this.knownMs,
    required this.unknownLength,
  });

  /// 목소리 만들기를 안내할 기준(분). 도구를 정하면 그 도구에 맞게 고친다 — 지금은 추정값.
  static const targetMinutes = 20;

  /// 책별로 센 자료. 자료가 있는 책만, 많은 순.
  final List<VoiceSampleBook> books;

  /// 녹음과 글이 함께 있는 쪽 수 — 학습에 쓸 수 있는 자료.
  final int pairedPages;

  /// 녹음은 있는데 글이 없는 쪽 수. 글을 채우면 자료가 된다.
  final int recordedWithoutText;

  /// 길이를 아는 짝 자료의 합(ms).
  final int knownMs;

  /// 길이를 모르는 짝 자료 수 — 길이 기록 전(2026-11-22 이전)에 녹음한 것.
  final int unknownLength;

  double get progress =>
      (knownMs / (targetMinutes * 60000)).clamp(0, 1).toDouble();

  bool get reachedTarget => knownMs >= targetMinutes * 60000;

  /// 책장 전체에서 센다. 책(`pagedBook`)만 본다.
  factory VoiceSampleSummary.fromContents(Iterable<Content> contents) {
    final books = <VoiceSampleBook>[];
    var paired = 0, noText = 0, known = 0, unknown = 0;
    for (final content in contents.where((c) => c.isBook)) {
      var bookPaired = 0, bookMs = 0;
      for (final page in content.orderedPages) {
        final recording = page.tracks
            .where((t) => t.source == AudioSource.parentRecording && t.hasFile)
            .firstOrNull;
        if (recording == null) continue;
        if (!page.hasText) {
          noText++;
          continue;
        }
        bookPaired++;
        final ms = recording.durationMs;
        if (ms == null || ms <= 0) {
          unknown++;
        } else {
          bookMs += ms;
        }
      }
      if (bookPaired > 0) {
        books.add(
          VoiceSampleBook(
            contentId: content.id,
            title: content.title,
            pages: bookPaired,
            ms: bookMs,
          ),
        );
      }
      paired += bookPaired;
      known += bookMs;
    }
    books.sort((a, b) => b.pages.compareTo(a.pages));
    return VoiceSampleSummary(
      books: books,
      pairedPages: paired,
      recordedWithoutText: noText,
      knownMs: known,
      unknownLength: unknown,
    );
  }
}

/// 한 권에서 모인 자료.
class VoiceSampleBook {
  const VoiceSampleBook({
    required this.contentId,
    required this.title,
    required this.pages,
    required this.ms,
  });
  final String contentId;
  final String title;
  final int pages;
  final int ms;
}

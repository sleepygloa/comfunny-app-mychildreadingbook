import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/services/restore_validator.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/audio_track.dart';
import 'package:mychild_reading/domain/enums/enums.dart';

void main() {
  late Directory root;
  late File metadata;
  late Map<String, Object?> book;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('restore-validator-');
    metadata = File('${root.path}/library/book/data.json');
    await metadata.parent.create(recursive: true);
    await File('${metadata.parent.path}/page.png').writeAsBytes([1, 2, 3]);
    await File('${metadata.parent.path}/voice.m4a').writeAsBytes([4, 5, 6]);
    book = Content(
      id: 'book',
      type: ContentType.pagedBook,
      title: '합성 테스트',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      pages: [
        BookPage(
          id: 'page',
          orderIndex: 0,
          imagePath: 'page.png',
          tracks: [
            AudioTrack(
              id: 'track',
              source: AudioSource.parentRecording,
              path: 'voice.m4a',
              createdAt: DateTime(2026),
            ),
          ],
        ),
      ],
    ).toJson();
  });
  tearDown(() async => root.delete(recursive: true));
  Future<void> save({int version = 1, bool legacy = false}) =>
      metadata.writeAsString(
        jsonEncode(legacy ? book : {'schemaVersion': version, 'data': book}),
      );
  test('책과 녹음 참조가 유효한 정상 백업을 승인한다', () async {
    await save();
    expect((await RestoreValidator().validate(root)).books, 1);
  });
  test('기존 앱이 지원하는 봉투 없는 구형 Content도 엄격 검증 후 승인한다', () async {
    await save(legacy: true);
    expect((await RestoreValidator().validate(root)).books, 1);
  });
  for (final kind in [
    'future',
    'json',
    'id',
    'path',
    'missing',
    'duplicate',
    'type',
    'date',
    'source',
  ]) {
    test('$kind 손상은 복원을 거절한다', () async {
      final pages = book['pages'] as List;
      final page = pages.first as Map;
      switch (kind) {
        case 'id':
          book['id'] = 'other';
        case 'path':
          page['imagePath'] = '../escape.png';
        case 'missing':
          await File('${metadata.parent.path}/voice.m4a').delete();
        case 'duplicate':
          book['pages'] = [...pages, Map.from(page)];
        case 'type':
          page['orderIndex'] = 'zero';
        case 'date':
          book['createdAt'] = 'not-a-date';
        case 'source':
          (page['tracks'] as List).first['source'] = 'unknown';
      }
      await save(version: kind == 'future' ? 99 : 1);
      if (kind == 'json') await metadata.writeAsString('{broken');
      await expectLater(
        RestoreValidator().validate(root),
        throwsA(isA<AppException>()),
      );
    });
  }
  test('삭제된 전집과 이전 읽던 페이지 ID는 기존 앱 폴백을 유지한다', () async {
    book['seriesId'] = 'deleted-series';
    await save();
    final pos = File('${root.path}/reading_positions/book/data.json');
    await pos.parent.create(recursive: true);
    await pos.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'data': {
          'contentId': 'book',
          'pageId': 'removed-page',
          'updatedAt': '2026-09-28T00:00:00Z',
        },
      }),
    );
    expect((await RestoreValidator().validate(root)).books, 1);
  });
  test('8MiB 초과 JSON은 파싱 전에 거절한다', () async {
    final out = await metadata.open(mode: FileMode.write);
    await out.truncate(RestoreValidator.maxJsonBytes + 1);
    await out.close();
    await expectLater(
      RestoreValidator().validate(root),
      throwsA(isA<AppException>()),
    );
  });
}

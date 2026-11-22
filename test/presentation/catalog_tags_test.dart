import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/data/services/restore_validator.dart';
import 'package:mychild_reading/domain/entities/book_tags.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/domain/entities/topic.dart';
import 'package:mychild_reading/domain/repositories/reading_workspace_repositories.dart';
import 'package:mychild_reading/domain/repositories/repositories.dart';
import 'package:mychild_reading/presentation/library/catalog_view_model.dart';
import 'package:mychild_reading/service_locator.dart';

import 'music_navigation_test.dart' show book;

/// 주제 · 즐겨찾기 · 나이 · 누리과정 꼬리표와 모아보기 — 합성 데이터만 쓴다.
void main() {
  late Directory tmp;
  late CatalogViewModel c;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('catalog_tags_');
    await registerWith(tmp);
    for (final id in ['a', 'b', 'c']) {
      await sl<ContentRepository>().save(book(id, volume: id.codeUnitAt(0)));
    }
    c = CatalogViewModel(
      contents: sl<ContentRepository>(),
      series: sl<SeriesRepository>(),
      playlists: sl<PlaylistRepository>(),
      drafts: sl<BookDraftRepository>(),
      topicRepository: sl<TopicRepository>(),
      bookTags: sl<BookTagRepository>(),
    );
    await c.load();
  });
  tearDown(() async {
    c.dispose();
    await resetLocator();
    await tmp.delete(recursive: true);
  });

  test('저장한 주제가 없으면 기본 사전을 보여 주고 파일은 만들지 않는다', () async {
    expect(c.topics.length, Topic.defaults.length);
    expect(File('${tmp.path}/index/topics.json').existsSync(), isFalse);
    expect(c.topicLabel('science-environment-air'), '과학 › 환경 › 대기오염');
  });

  test('주제를 처음 더하면 기본 사전과 함께 저장된다', () async {
    final t = await c.addTopic('공룡', parentId: 'science');
    expect(t, isNotNull);
    final stored = await sl<TopicRepository>().getAll();
    expect(stored.length, Topic.defaults.length + 1);
    expect(c.topicLabel(t!.id), '과학 › 공룡');
  });

  test('별을 누르면 즐겨찾기 모아보기에 들어가고, 다시 누르면 행이 지워진다', () async {
    final a = c.books.firstWhere((b) => b.id == 'a');
    await c.toggleFavorite(a);
    expect(c.tagsOf(a).favorite, isTrue);
    expect(c.collections.first.id, 'favorite');
    expect(c.collections.first.books.map((b) => b.id), ['a']);
    await c.toggleFavorite(a);
    expect(await sl<BookTagRepository>().getAll(), isEmpty);
    expect(c.collections.where((g) => g.id == 'favorite'), isEmpty);
  });

  test('하위 주제가 붙은 책도 큰 주제 몰아보기 · 거르기에 들어간다', () async {
    await c.saveTags(
      const BookTags(contentId: 'b', topicIds: ['science-environment-air']),
    );
    await c.saveTags(
      const BookTags(
        contentId: 'c',
        topicIds: ['story'],
        ageMin: 6,
        ageMax: 8,
        nuriAreas: [NuriArea.communication],
      ),
    );
    final science = c.collections.firstWhere((g) => g.id == 'topic-science');
    expect(science.title, '과학 몰아보기');
    expect(science.books.map((b) => b.id), ['b']);
    expect(c.collections.any((g) => g.id == 'age-7'), isTrue);
    expect(c.collections.any((g) => g.id == 'age-5'), isFalse);
    expect(
      c.collections
          .firstWhere((g) => g.id == 'nuri-communication')
          .books
          .single
          .id,
      'c',
    );
    c.selectTopic('science');
    expect(c.filter(c.books).map((b) => b.id), ['b']);
    c.selectTopic(null);
    c.search('대기오염');
    expect(c.filter(c.books).map((b) => b.id), ['b']);
    c.search('');
    c.selectAge(7);
    expect(c.filter(c.books).map((b) => b.id), ['c']);
  });

  test('책을 지우면 꼬리표 행도 지운다', () async {
    await c.saveTags(const BookTags(contentId: 'a', favorite: true));
    await c.deleteTagsOf('a');
    expect(await sl<BookTagRepository>().getAll(), isEmpty);
  });

  test('주제 · 꼬리표 파일이 든 백업은 복원 검사를 통과하고, 깨진 행은 거절한다', () async {
    await c.addTopic('공룡', parentId: 'science');
    await c.saveTags(
      const BookTags(
        contentId: 'a',
        topicIds: ['science'],
        favorite: true,
        ageMin: 5,
        nuriAreas: [NuriArea.art],
      ),
    );
    await sl<ContentRepository>().delete('b');
    await sl<ContentRepository>().delete('c');
    // 책 페이지 그림 파일이 없어 책은 검사에서 빠지도록 지운다 — 여기선 index 파일만 본다.
    await sl<ContentRepository>().delete('a');
    final preview = await RestoreValidator().validate(tmp);
    expect(preview.books, 0);
    final file = File('${tmp.path}/index/book_tags.json');
    final json = jsonDecode(await file.readAsString()) as Map;
    (json['data'] as List).first['topicIds'] = ['../bad'];
    await file.writeAsString(jsonEncode(json));
    await expectLater(RestoreValidator().validate(tmp), throwsA(anything));
  });

  test('방을 바꾸면 그 방 종류만 다시 읽고, 거르기 조건을 푼다', () async {
    // 책장을 읽은 뒤에 음원이 생겨도 방을 바꾸면 보인다 — 화면 목록을 거르지 않고 다시 읽는다.
    await sl<ContentRepository>().save(
      Content(
        id: 'song',
        type: ContentType.audio,
        title: '합성 동요',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    c.setFavoritesOnly(true);
    c.search('책');
    await c.selectRoom(LibraryRoom.music);
    expect(c.shelfItems.map((b) => b.id), ['song']);
    expect(c.favoritesOnly, isFalse);
    expect(c.query, isEmpty);
    // 플레이리스트 · 모아보기가 쓰는 책 목록은 방과 무관하게 책만 담는다.
    expect(c.books.map((b) => b.id), ['a', 'b', 'c']);
    await c.selectRoom(LibraryRoom.cinema);
    expect(c.shelfItems, isEmpty);
    await c.selectRoom(LibraryRoom.library);
    expect(c.shelfItems.map((b) => b.id), ['a', 'b', 'c']);
  });
}

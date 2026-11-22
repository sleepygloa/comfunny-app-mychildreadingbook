import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/book_tags.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/series.dart';
import '../../domain/entities/book_draft.dart';
import '../../domain/entities/topic.dart';
import '../../domain/enums/enums.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/repositories/reading_workspace_repositories.dart';

/// 책 분류와 저장 플레이리스트를 관리한다. 현재 재생목록에는 접근하지 않는다.
class CatalogViewModel extends ChangeNotifier {
  CatalogViewModel({
    required this.contents,
    required this.series,
    required this.playlists,
    required this.drafts,
    required this.topicRepository,
    required this.bookTags,
  });
  final ContentRepository contents;
  final SeriesRepository series;
  final PlaylistRepository playlists;
  final BookDraftRepository drafts;
  final TopicRepository topicRepository;
  final BookTagRepository bookTags;
  List<Content> books = [];

  /// 지금 고른 방. 앱을 켜면 늘 도서관에서 시작한다(오너 결정 — 도서관이 본채).
  LibraryRoom room = LibraryRoom.library;

  /// 책장 탭에 보일 목록 — 고른 방의 종류만. 도서관이면 [books] 와 같다.
  /// 플레이리스트 · 모아보기는 계속 [books](책)를 쓴다.
  List<Content> shelfItems = [];
  List<Series> seriesList = [];
  List<Playlist> lists = [];
  List<BookDraft> draftList = [];
  String query = '';
  String? publisher;

  /// 주제 사전. 저장한 적이 없으면 [Topic.defaults].
  List<Topic> topics = Topic.defaults;
  bool _topicsStored = false;
  Map<String, BookTags> _tags = {};

  /// 책장 거르기 — 고른 주제(하위 주제 포함) · 즐겨찾기만 · 나이.
  String? topicFilter;
  bool favoritesOnly = false;
  int? ageFilter;
  bool isBusy = false;
  Completer<void>? _idle;
  Future<void> waitUntilIdle() async {
    await _idle?.future;
  }

  String? error;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() => mutate(() async {});
  Future<void> mutate(Future<void> Function() action) async {
    if (isBusy) return;
    isBusy = true;
    _idle = Completer<void>();
    error = null;
    _notify();
    try {
      await action();
      // 방을 바꿀 때마다 저장소에서 다시 읽는다 — 화면에 남은 목록을 거르지 않는다(오너 결정).
      final all = await contents.getAll();
      books = all.where((b) => b.isBook).toList()..sort(compareBooks);
      shelfItems = room == LibraryRoom.library
          ? books
          : (all.where((b) => b.type == room.type).toList()
              ..sort(compareBooks));
      seriesList = await series.getAll();
      lists = await playlists.getAll();
      draftList = await drafts.getAll();
      final stored = await topicRepository.getAll();
      _topicsStored = stored.isNotEmpty;
      topics = _topicsStored ? stored : Topic.defaults;
      _tags = {for (final t in await bookTags.getAll()) t.contentId: t};
    } on Object {
      error = '목록을 저장하거나 불러오지 못했어요. 다시 시도해 주세요.';
    } finally {
      isBusy = false;
      _idle?.complete();
      _idle = null;
      _notify();
    }
  }

  static int compareBooks(Content a, Content b) {
    final volume = (a.volume ?? 2147483647).compareTo(b.volume ?? 2147483647);
    return volume != 0 ? volume : a.title.compareTo(b.title);
  }

  Series? seriesOf(Content b) =>
      seriesList.where((s) => s.id == b.seriesId).firstOrNull;
  String publisherOf(Content b) {
    final value = b.publisher?.trim();
    if (value != null && value.isNotEmpty) return value;
    final inherited = seriesOf(b)?.publisher?.trim();
    return inherited == null || inherited.isEmpty ? '미분류' : inherited;
  }

  String seriesTitle(Content b) => seriesOf(b)?.title ?? '단권 · 미분류';
  List<String> get publishers =>
      books.map(publisherOf).toSet().toList()..sort();
  List<Content> filter(Iterable<Content> source, {String? search}) {
    final q = (search ?? query).trim().toLowerCase();
    final wanted = topicFilter == null
        ? null
        : {topicFilter!, ...descendantsOf(topicFilter!).map((t) => t.id)};
    return source.where((b) {
      final t = tagsOf(b);
      if (publisher != null && publisherOf(b) != publisher) return false;
      if (favoritesOnly && !t.favorite) return false;
      if (ageFilter != null && !t.fitsAge(ageFilter!)) return false;
      if (wanted != null && !t.topicIds.any(wanted.contains)) return false;
      if (q.isEmpty) return true;
      // 주제 이름으로도 찾는다 — "대기오염"을 치면 그 주제가 붙은 책이 나온다.
      final topicNames = topicsOf(b).map((x) => x.name).join(' ');
      return '${b.title} ${publisherOf(b)} ${seriesTitle(b)} $topicNames'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  /// 거르기 조건이 하나라도 켜져 있는가. 켜져 있으면 책장이 거르기 줄을 계속 보인다.
  bool get hasActiveFilters =>
      publisher != null ||
      topicFilter != null ||
      favoritesOnly ||
      ageFilter != null;

  void selectTopic(String? id) {
    topicFilter = id;
    _notify();
  }

  void setFavoritesOnly(bool value) {
    favoritesOnly = value;
    _notify();
  }

  void selectAge(int? age) {
    ageFilter = age;
    _notify();
  }

  void clearFilters() {
    publisher = null;
    topicFilter = null;
    favoritesOnly = false;
    ageFilter = null;
    _notify();
  }

  // ── 주제 · 꼬리표 ──────────────────────────────────────────

  BookTags tagsOf(Content b) => _tags[b.id] ?? BookTags(contentId: b.id);
  Topic? topicById(String id) => topics.where((t) => t.id == id).firstOrNull;
  List<Topic> get rootTopics => topics.where((t) => t.isRoot).toList();

  /// [id] 아래의 모든 주제(손주까지). 사전이 꼬여 순환해도 멈추도록 방문 기록을 둔다.
  List<Topic> descendantsOf(String id) {
    final out = <Topic>[];
    final seen = <String>{id};
    void walk(String parent) {
      for (final t in topics.where((t) => t.parentId == parent)) {
        if (seen.add(t.id)) {
          out.add(t);
          walk(t.id);
        }
      }
    }

    walk(id);
    return out;
  }

  /// "과학 › 환경 › 대기오염". 사전에서 지워진 주제는 빈 문자열.
  String topicLabel(String id) {
    final names = <String>[];
    final seen = <String>{};
    Topic? t = topicById(id);
    while (t != null && seen.add(t.id)) {
      names.insert(0, t.name);
      t = t.parentId == null ? null : topicById(t.parentId!);
    }
    return names.join(' › ');
  }

  /// 책에 붙은 주제 중 사전에 남아 있는 것만.
  List<Topic> topicsOf(Content b) => [
    for (final id in tagsOf(b).topicIds)
      if (topicById(id) != null) topicById(id)!,
  ];

  /// 맨 위 주제(배지 색 · 모아보기 묶음 기준).
  Topic? rootOf(String id) {
    final seen = <String>{};
    Topic? t = topicById(id);
    while (t != null && t.parentId != null && seen.add(t.id)) {
      final parent = topicById(t.parentId!);
      // 부모가 사전에서 지워졌으면 지금 주제를 맨 위로 본다.
      if (parent == null) break;
      t = parent;
    }
    return t;
  }

  Future<void> saveTags(BookTags tags) => mutate(() async {
    // FLOW 1: 검증 — 책 id 없는 꼬리표는 어느 책 것인지 알 수 없다
    if (tags.contentId.isEmpty) return;
    // FLOW 2: 빈 꼬리표는 행을 남기지 않는다(파일이 책 수만큼 불어나지 않게)
    if (tags.isEmpty) {
      await bookTags.delete(tags.contentId);
    } else {
      await bookTags.save(tags);
    }
    // FLOW 9: mutate 가 목록을 다시 읽는다
  });

  Future<void> toggleFavorite(Content b) {
    final t = tagsOf(b);
    return saveTags(t.copyWith(favorite: !t.favorite));
  }

  /// 책을 지울 때 함께 부른다. [mutate] 안에서 쓰므로 여기서는 다시 감싸지 않는다.
  Future<void> deleteTagsOf(String contentId) => bookTags.delete(contentId);

  /// 주제를 하나 더한다. 같은 부모 아래 같은 이름이 있으면 그것을 돌려준다.
  Future<Topic?> addTopic(String name, {String? parentId}) async {
    // FLOW 1: 검증
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final same = topics
        .where((t) => t.parentId == parentId && t.name == trimmed)
        .firstOrNull;
    if (same != null) return same;
    final topic = Topic(
      id: const Uuid().v4(),
      name: trimmed,
      parentId: parentId,
      order: topics.where((t) => t.parentId == parentId).length,
    );
    await mutate(() async {
      // FLOW 2: 처음 저장할 때는 기본 사전을 먼저 파일로 옮긴다 —
      //         그러지 않으면 새 주제 하나만 남고 기본 사전이 사라진다.
      if (!_topicsStored) {
        for (final t in Topic.defaults) {
          await topicRepository.save(t);
        }
      }
      // FLOW 3: 새 주제 저장
      await topicRepository.save(topic);
      // FLOW 9: mutate 가 목록을 다시 읽는다
    });
    return topicById(topic.id);
  }

  /// 모아보기 — 꼬리표에서 매번 다시 계산한다(저장하지 않는다).
  List<BookCollection> get collections {
    final out = <BookCollection>[];
    void add(BookCollection g) {
      if (g.books.isNotEmpty) out.add(g);
    }

    add(
      BookCollection(
        id: 'favorite',
        kind: CollectionKind.favorite,
        title: '즐겨찾기',
        emoji: '⭐',
        books: books.where((b) => tagsOf(b).favorite).toList(),
      ),
    );
    for (final root in rootTopics) {
      final ids = {root.id, ...descendantsOf(root.id).map((t) => t.id)};
      add(
        BookCollection(
          id: 'topic-${root.id}',
          kind: CollectionKind.topic,
          title: '${root.name} 몰아보기',
          emoji: root.emoji.isEmpty ? '📚' : root.emoji,
          books: books
              .where((b) => tagsOf(b).topicIds.any(ids.contains))
              .toList(),
        ),
      );
    }
    for (var age = 3; age <= 8; age++) {
      add(
        BookCollection(
          id: 'age-$age',
          kind: CollectionKind.age,
          title: '$age세 몰아보기',
          emoji: '🎂',
          books: books.where((b) => tagsOf(b).fitsAge(age)).toList(),
        ),
      );
    }
    for (final area in NuriArea.values) {
      add(
        BookCollection(
          id: 'nuri-${area.name}',
          kind: CollectionKind.nuri,
          title: area.label,
          emoji: area.emoji,
          books: books
              .where((b) => tagsOf(b).nuriAreas.contains(area))
              .toList(),
        ),
      );
    }
    return out;
  }

  /// 방 고르기. 같은 방이면 아무것도 하지 않는다.
  Future<void> selectRoom(LibraryRoom value) async {
    // FLOW 1: 검증 — 같은 방을 다시 누르면 다시 읽지 않는다
    if (value == room) return;
    // FLOW 2: 방을 바꾸고 거르기 조건을 푼다 — 다른 방의 조건이 남으면 빈 목록처럼 보인다
    room = value;
    query = '';
    publisher = null;
    topicFilter = null;
    favoritesOnly = false;
    ageFilter = null;
    // FLOW 9: 그 방 목록을 다시 읽는다
    await load();
  }

  void search(String value) {
    query = value;
    _notify();
  }

  void selectPublisher(String? value) {
    publisher = value;
    _notify();
  }

  List<Content> booksFor(Playlist list) {
    final byId = {for (final b in books) b.id: b};
    return [
      for (final id in list.contentIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<void> createList(String title) => mutate(() async {
    if (title.trim().isEmpty) return;
    await playlists.save(
      Playlist(
        id: const Uuid().v4(),
        title: title.trim(),
        createdAt: DateTime.now(),
      ),
    );
  });
  Future<void> saveList(Playlist list) => mutate(() => playlists.save(list));
  Future<void> deleteList(String id) => mutate(() => playlists.delete(id));
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 모아보기 묶음 종류 — 화면에서 이 순서대로 제목을 달아 보인다.
enum CollectionKind {
  favorite('즐겨찾기'),
  topic('주제별'),
  age('나이별'),
  nuri('누리과정 5영역');

  const CollectionKind(this.label);
  final String label;
}

/// 조건으로 모인 책 묶음. 저장하지 않는다.
class BookCollection {
  const BookCollection({
    required this.id,
    required this.kind,
    required this.title,
    required this.emoji,
    required this.books,
  });
  final String id;
  final CollectionKind kind;
  final String title;
  final String emoji;
  final List<Content> books;
}

/// 제목을 눌러 고르는 세 방. 종류([ContentType])로 목록을 나눈다.
enum LibraryRoom {
  music(ContentType.audio, '작은 음악방', '🎵'),
  library(ContentType.pagedBook, '작은 도서관', '📚'),
  cinema(ContentType.video, '작은 영상관', '🎬');

  const LibraryRoom(this.type, this.label, this.emoji);
  final ContentType type;
  final String label;
  final String emoji;
}

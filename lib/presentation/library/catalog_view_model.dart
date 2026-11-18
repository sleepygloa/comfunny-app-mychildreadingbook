import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/content.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/series.dart';
import '../../domain/entities/book_draft.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/repositories/reading_workspace_repositories.dart';

/// 책 분류와 저장 플레이리스트를 관리한다. 현재 재생목록에는 접근하지 않는다.
class CatalogViewModel extends ChangeNotifier {
  CatalogViewModel({
    required this.contents,
    required this.series,
    required this.playlists,
    required this.drafts,
  });
  final ContentRepository contents;
  final SeriesRepository series;
  final PlaylistRepository playlists;
  final BookDraftRepository drafts;
  List<Content> books = [];
  List<Series> seriesList = [];
  List<Playlist> lists = [];
  List<BookDraft> draftList = [];
  String query = '';
  String? publisher;
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
      books = (await contents.getAll()).where((b) => b.isBook).toList()
        ..sort(compareBooks);
      seriesList = await series.getAll();
      lists = await playlists.getAll();
      draftList = await drafts.getAll();
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
    return source
        .where(
          (b) =>
              (publisher == null || publisherOf(b) == publisher) &&
              (q.isEmpty ||
                  '${b.title} ${publisherOf(b)} ${seriesTitle(b)}'
                      .toLowerCase()
                      .contains(q)),
        )
        .toList();
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

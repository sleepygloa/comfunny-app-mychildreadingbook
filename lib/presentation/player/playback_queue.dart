import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/content.dart';
import '../../domain/repositories/recent_playback_repository.dart';
import 'player_view_model.dart';

/// 저장 플레이리스트와 분리된 최근재생목록. ID/순서는 보존하고 오디오 소유자는 하나다.
class PlaybackQueue extends ChangeNotifier {
  PlaybackQueue({
    required this.createPlayer,
    this.resolveBook,
    this.recentRepository,
    this.releaseAudio,
  });
  final RecentPlaybackRepository? recentRepository;
  final Future<void> Function()? releaseAudio;
  bool _playRequested = false;
  bool backgroundEnabled = false;
  int _editingDepth = 0;
  int _controlEpoch = 0;
  bool get canPlay =>
      !_storageSuspended &&
      _editingDepth == 0 &&
      (_foreground || backgroundEnabled);
  final Future<Content?> Function(String)? resolveBook;
  final PlayerViewModel Function(Content) createPlayer;
  final List<Content> _items = [];
  List<Content> get items => List.unmodifiable(_items);
  PlayerViewModel? player;
  String? _currentId;
  String? get currentId => _currentId;
  int get currentIndex => _items.indexWhere((b) => b.id == _currentId);
  bool isBusy = false;
  bool _disposed = false;
  bool _storageSuspended = false;
  bool _foreground = true;
  Future<void> _pending = Future.value();
  Future<void> _pausePending = Future.value();
  String? error;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) {
    if (_storageSuspended) return Future.value();
    final result = _pending.then((_) async {
      if (_disposed || _storageSuspended) return;
      isBusy = true;
      error = null;
      _notify();
      try {
        await action();
        await recentRepository?.save(
          RecentPlayback(
            bookIds: _items.map((b) => b.id).toList(),
            currentId: _currentId,
          ),
        );
      } on Object {
        error = '최근재생목록을 변경하거나 저장하지 못했어요. 다시 시도해 주세요.';
      } finally {
        isBusy = false;
        _notify();
      }
    });
    _pending = result;
    return result;
  }

  /// stop 완료 후 호출한다. OS stop/skip도 복원한 최근목록을 덮지 못한다.
  Future<void> suspendStorage() async {
    _storageSuspended = true;
    _controlEpoch++;
    _playRequested = false;
    await _pending;
    await _pausePending;
  }

  /// 현재 최근목록이 손상돼도 복원 진입은 가능해야 하므로 저장을 수반하지 않는다.
  Future<void> prepareRestore() async {
    await suspendStorage();
    try {
      await _close();
      await releaseAudio?.call();
      error = null;
      _notify();
    } on Object {
      resumeStorage();
      rethrow;
    }
  }

  Future<void> reloadRestoredLibrary() async {
    if (!_storageSuspended || player != null) {
      throw StateError('queue not quiescent');
    }
    final saved = await recentRepository?.load();
    final books = <Content>[];
    if (saved != null && resolveBook != null) {
      for (final id in saved.bookIds) {
        final book = await resolveBook!(id);
        if (book != null && book.isBook && book.isPlayable) books.add(book);
      }
    }
    _items
      ..clear()
      ..addAll(books);
    _currentId = books.any((b) => b.id == saved?.currentId)
        ? saved?.currentId
        : null;
    error = null;
    _notify();
  }

  void resumeStorage() {
    _storageSuspended = false;
    _notify();
  }

  Future<void> restoreRecent() => _run(() async {
    if (recentRepository == null || resolveBook == null) return;
    if (player != null) return;
    final saved = await recentRepository!.load();
    _items.clear();
    for (final id in saved.bookIds) {
      final book = await resolveBook!(id);
      if (book != null && book.isBook && book.isPlayable) _items.add(book);
    }
    _currentId = _items.any((b) => b.id == saved.currentId)
        ? saved.currentId
        : null;
    // 목록만 복원한다. 앱을 여는 것만으로 소리를 시작하지 않는다.
  });

  Future<void> playAll(Iterable<Content> books) {
    final snapshot = _unique(books);
    _playRequested = canPlay;
    return _run(() async {
      if (snapshot.isEmpty || !canPlay) return;
      if (snapshot.length > 1000) {
        error = '최근재생목록에는 1,000권까지 담을 수 있어요.';
        return;
      }
      await _close();
      _items
        ..clear()
        ..addAll(snapshot);
      await _open(_items.first);
    });
  }

  List<Content> _unique(Iterable<Content> books) {
    final seen = <String>{};
    return books
        .where((b) => b.isBook && b.isPlayable && seen.add(b.id))
        .toList();
  }

  Future<void> append(Iterable<Content> books) {
    final snapshot = _unique(books);
    return _run(() async {
      final ids = _items.map((b) => b.id).toSet();
      final added = snapshot.where((b) => ids.add(b.id)).toList();
      if (_items.length + added.length > 1000) {
        error = '최근재생목록에는 1,000권까지 담을 수 있어요.';
        return;
      }
      _items.addAll(added);
    });
  }

  Future<void> select(String id) {
    _playRequested = canPlay;
    return _run(() async {
      if (!canPlay) return;
      final book = _items.where((b) => b.id == id).firstOrNull;
      if (book == null) return;
      await _close();
      await _open(book);
    });
  }

  Future<void> _open(Content book) async {
    final epoch = _controlEpoch;
    await _pausePending;
    if (_disposed) return;
    if (resolveBook != null) {
      final latest = await resolveBook!(book.id);
      if (_disposed) return;
      if (latest == null || !latest.isPlayable) {
        _items.removeWhere((b) => b.id == book.id);
        error = '이 책은 삭제됐거나 재생할 페이지가 없어요.';
        return;
      }
      book = latest;
      final index = _items.indexWhere((b) => b.id == book.id);
      if (index >= 0) _items[index] = book;
    }
    _currentId = book.id;
    final next = createPlayer(book);
    player = next;
    next.addListener(_notify);
    next.onBookComplete = () {
      if (!_disposed && identical(player, next) && canPlay && _playRequested) {
        unawaited(nextBook());
      }
    };
    _notify();
    if (canPlay && _playRequested && epoch == _controlEpoch) {
      await next.start();
    } else {
      await next.pause();
    }
  }

  Future<void> _close() async {
    await _pausePending;
    final old = player;
    player = null;
    _currentId = null;
    if (old == null) return;
    old.removeListener(_notify);
    old.onBookComplete = null;
    try {
      await old.leave();
    } finally {
      old.dispose();
    }
  }

  Future<void> nextBook() => _run(() async {
    if (!canPlay) return;
    final index = currentIndex;
    if (index < 0 || index + 1 >= _items.length) {
      await _releaseSession();
      return;
    }
    final next = _items[index + 1];
    await _close();
    await _open(next);
  });

  Future<void> remove(String id) => _run(() async {
    final index = _items.indexWhere((b) => b.id == id);
    if (index < 0) return;
    final wasCurrent = id == _currentId;
    if (wasCurrent) {
      await _close();
      await _releaseSession();
    }
    _items.removeAt(index);
    // 삭제는 재생 시작 의사가 아니므로 다음 항목을 자동 시작하지 않는다.
  });

  /// 게시 직후 구판 플레이어를 닫아 독서 화면의 직접 조작도 구판을 쓰지 않게 한다.
  Future<void> refreshBook(Content book) => _run(() async {
    final index = _items.indexWhere((b) => b.id == book.id);
    if (index < 0) return;
    _items[index] = book;
    if (_currentId == book.id) {
      await _close();
      _currentId = book.id;
    }
  });

  Future<void> clear() => _run(() async {
    _playRequested = false;
    await _close();
    await _releaseSession();
    _items.clear();
  });
  Future<void> reorder(int from, int to) => _run(() async {
    if (from < 0 || from >= _items.length || to < 0 || to >= _items.length) {
      return;
    }
    _items.insert(to, _items.removeAt(from));
  });

  Future<void> toggle({bool onlyPlay = false}) async {
    final epoch = _controlEpoch;
    if (!canPlay || isBusy) return;
    _playRequested = true;
    await _pausePending;
    if (_disposed || !canPlay || epoch != _controlEpoch || !_playRequested) {
      return;
    }
    final p = player;
    if (p == null) {
      if (_items.isNotEmpty) {
        await select(
          currentIndex >= 0 ? _items[currentIndex].id : _items.first.id,
        );
      }
      return;
    }
    if (!p.isPlaying && resolveBook != null) {
      final latest = await resolveBook!(p.content.id);
      if (_disposed ||
          !identical(player, p) ||
          !canPlay ||
          epoch != _controlEpoch ||
          !_playRequested) {
        return;
      }
      if (latest == null) {
        await remove(p.content.id);
        return;
      }
      if (latest.updatedAt != p.content.updatedAt) {
        await select(latest.id);
        return;
      }
    }
    if (p.isPlaying) {
      if (!onlyPlay) await pause();
    } else {
      await p.resume();
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    if (!value && !backgroundEnabled) {
      unawaited(pause());
    }
  }

  Future<void> pause() {
    _controlEpoch++;
    _playRequested = false;
    final current = player;
    // 오디오 포커스 반환이 끝나기 전에 새 재생이 시작되지 않게 한다.
    final result = _pausePending.then((_) async {
      await current?.pause();
      await _releaseSession();
    });
    _pausePending = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        error = '재생을 멈추지 못했어요. 재생 종료를 눌러 주세요.';
        _notify();
      },
    );
    return _pausePending;
  }

  Future<void> _releaseSession() async {
    try {
      await releaseAudio?.call();
    } on Object {
      error = '오디오 연결을 정리하지 못했어요. 재생을 종료한 뒤 다시 시도해 주세요.';
      _notify();
    }
  }

  Future<void> play() async {
    await toggle(onlyPlay: true);
  }

  Future<void> stop() {
    unawaited(pause());
    return _run(() async {
      await _close();
      await _releaseSession();
    });
  }

  Future<void> previousBook() => _run(() async {
    if (!canPlay || currentIndex <= 0) return;
    _playRequested = true;
    final previous = _items[currentIndex - 1];
    await _close();
    await _open(previous);
  });

  Future<void> nextPage() => _changePage(isNext: true);
  Future<void> previousPage() => _changePage(isNext: false);

  Future<void> _changePage({required bool isNext}) async {
    if (!canPlay || isBusy) return;
    final epoch = _controlEpoch;
    final current = player;
    _playRequested = true;
    await _pausePending;
    if (_disposed ||
        !canPlay ||
        epoch != _controlEpoch ||
        !_playRequested ||
        !identical(player, current)) {
      return;
    }
    if (isNext) {
      await current?.next();
    } else {
      await current?.previous();
    }
  }

  void setEditing(bool value, {bool notify = true}) {
    _editingDepth = value
        ? _editingDepth + 1
        : (_editingDepth - 1).clamp(0, 1000);
    if (value) unawaited(pause());
    if (notify) _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    final old = player;
    old?.removeListener(_notify);
    if (old != null) {
      old.onBookComplete = null;
      unawaited(old.leave().whenComplete(old.dispose));
    }
    player = null;
    super.dispose();
  }
}

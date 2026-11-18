import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/data/local/media_storage.dart';
import 'package:mychild_reading/data/services/page_audio_player.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/playlist.dart';
import 'package:mychild_reading/domain/entities/reading_event.dart';
import 'package:mychild_reading/domain/entities/series.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/domain/repositories/repositories.dart';
import 'package:mychild_reading/domain/repositories/book_authoring_repository.dart';
import 'package:mychild_reading/domain/repositories/reading_workspace_repositories.dart';
import 'package:mychild_reading/presentation/authoring/authoring_view_model.dart';
import 'package:mychild_reading/presentation/library/catalog_view_model.dart';
import 'package:mychild_reading/presentation/player/playback_queue.dart';
import 'package:mychild_reading/presentation/player/player_view_model.dart';
import 'package:mychild_reading/service_locator.dart';

class FakeAudio implements PageAudioPlayer {
  @override
  void Function()? onComplete;
  @override
  void Function(String)? onError;
  @override
  bool isPlaying = false;
  final calls = <String>[];
  @override
  Future<void> speak(String text) async {
    calls.add(text);
    isPlaying = true;
  }

  @override
  Future<void> playFile(String path) async {
    calls.add(path);
    isPlaying = true;
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
  }

  @override
  Future<void> resume() async {
    isPlaying = true;
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
  }

  @override
  Future<void> dispose() async {
    isPlaying = false;
  }

  void finish() {
    isPlaying = false;
    onComplete?.call();
  }
}

class Events implements ReadingEventRepository {
  @override
  Future<void> save(ReadingEvent e) async {}
  @override
  Future<List<ReadingEvent>> query({
    DateTime? from,
    DateTime? to,
    String? childId,
  }) async => [];
}

Content book(
  String id, {
  String publisher = '그레이트북스',
  String? series = 'series',
  int volume = 1,
  DateTime? updated,
}) => Content(
  id: id,
  type: ContentType.pagedBook,
  title: '책 $id',
  publisher: publisher,
  seriesId: series,
  volume: volume,
  createdAt: DateTime(2026),
  updatedAt: updated ?? DateTime(2026),
  pages: [
    BookPage(
      id: '$id-page',
      orderIndex: 0,
      imagePath: 'page.jpg',
      text: '이야기 $id',
    ),
  ],
);
Future<void> drain() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  late Directory tmp;
  late List<FakeAudio> engines;
  late PlaybackQueue queue;
  late CatalogViewModel catalog;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('music_nav_');
    await registerWith(tmp);
    engines = [];
    queue = PlaybackQueue(
      createPlayer: (b) {
        final audio = FakeAudio();
        engines.add(audio);
        return PlayerViewModel(
          content: b,
          audioPlayer: audio,
          mediaStorage: MediaStorage(tmp),
          readingEventRepository: Events(),
        );
      },
    );
    catalog = CatalogViewModel(
      contents: sl<ContentRepository>(),
      series: sl<SeriesRepository>(),
      playlists: sl<PlaylistRepository>(),
      drafts: sl<BookDraftRepository>(),
    );
  });
  tearDown(() async {
    queue.dispose();
    catalog.dispose();
    await drain();
    await resetLocator();
    await tmp.delete(recursive: true);
  });
  test('재생 완료는 다음 책으로 이어지고 마지막에서 멈춘다', () async {
    await queue.playAll([book('a'), book('b')]);
    expect(queue.currentId, 'a');
    engines.last.finish();
    await drain();
    expect(queue.currentId, 'b');
    expect(engines.first.isPlaying, isFalse);
    engines.last.finish();
    await drain();
    expect(queue.player!.isFinished, isTrue);
    expect(engines.length, 2);
  });
  test('순서 변경은 현재 책을 유지하고 다음 재생 순서에 반영된다', () async {
    await queue.playAll([book('a'), book('b'), book('c')]);
    await queue.reorder(2, 1);
    expect(queue.currentId, 'a');
    expect(queue.items.map((b) => b.id), ['a', 'c', 'b']);
    engines.first.finish();
    await drain();
    expect(queue.currentId, 'c');
  });
  test('저장 플레이리스트와 큐 순서 및 삭제는 독립이다', () async {
    final p = Playlist(
      id: 'list',
      title: '잠들기 전',
      createdAt: DateTime(2026),
      contentIds: ['a', 'b'],
    );
    await sl<PlaylistRepository>().save(p);
    await queue.playAll([book('a'), book('b')]);
    await queue.reorder(0, 1);
    await queue.remove('a');
    await queue.clear();
    expect((await sl<PlaylistRepository>().getAll()).single.contentIds, [
      'a',
      'b',
    ]);
  });
  test('추가는 현재 재생을 바꾸지 않고 중복 항목을 늘리지 않는다', () async {
    await queue.playAll([book('a')]);
    await queue.append([book('a'), book('b')]);
    expect(queue.currentId, 'a');
    expect(queue.items.length, 2);
    expect(engines.length, 1);
  });
  test('현재 책 제거는 오디오를 멈추고 다른 책을 임의로 시작하지 않는다', () async {
    await queue.playAll([book('a'), book('b')]);
    await queue.remove('a');
    expect(queue.player, isNull);
    expect(engines.single.isPlaying, isFalse);
    expect(queue.items.single.id, 'b');
    await queue.toggle();
    expect(queue.currentId, 'b');
  });
  test('앱 비활성화 후 완료 신호가 다음 책을 시작하지 않는다', () async {
    await queue.playAll([book('a'), book('b')]);
    queue.setForeground(false);
    await drain();
    engines.first.finish();
    await drain();
    expect(queue.currentId, 'a');
    expect(engines.length, 1);
    expect(queue.player!.isPlaying, isFalse);
  });
  test('저장 후 수정한 책은 큐에서 재개할 때 최신 판을 사용한다', () async {
    var latest = book('a');
    final custom = PlaybackQueue(
      resolveBook: (_) async => latest,
      createPlayer: (b) => PlayerViewModel(
        content: b,
        audioPlayer: FakeAudio(),
        mediaStorage: MediaStorage(tmp),
        readingEventRepository: Events(),
      ),
    );
    await custom.playAll([latest]);
    await custom.pause();
    latest = latest.copyWith(title: '수정 제목', updatedAt: DateTime(2026, 9));
    await custom.toggle();
    expect(custom.player!.content.title, '수정 제목');
    custom.dispose();
  });
  test('출판사 전집 검색과 권 번호 정렬, 미분류를 유지한다', () async {
    await sl<SeriesRepository>().save(
      const Series(id: 'series', title: '동물 친구', publisher: '그레이트북스'),
    );
    await sl<ContentRepository>().save(book('b', volume: 2));
    await sl<ContentRepository>().save(book('a'));
    await sl<ContentRepository>().save(book('c', publisher: '', series: null));
    await catalog.load();
    catalog.search('동물');
    expect(catalog.filter(catalog.books).map((b) => b.id), ['a', 'b']);
    catalog.search('');
    catalog.selectPublisher('미분류');
    expect(catalog.filter(catalog.books).single.id, 'c');
  });
  test('플레이리스트 CRUD를 다시 읽어도 책은 남는다', () async {
    await sl<ContentRepository>().save(book('a'));
    await catalog.createList('잠들기 전');
    final p = catalog.lists.single;
    await catalog.saveList(
      p.copyWith(title: '좋아하는 책', contentIds: ['a', 'missing']),
    );
    await catalog.load();
    expect(catalog.booksFor(catalog.lists.single).single.id, 'a');
    await catalog.deleteList(p.id);
    expect(catalog.lists, isEmpty);
    expect(await sl<ContentRepository>().getById('a'), isNotNull);
  });
  test('동시 플레이리스트 저장은 서로의 목록을 덮지 않는다', () async {
    final repo = sl<PlaylistRepository>();
    await Future.wait([
      for (var i = 0; i < 10; i++)
        repo.save(
          Playlist(id: 'p$i', title: '목록$i', createdAt: DateTime(2026)),
        ),
    ]);
    expect((await repo.getAll()).length, 10);
  });
  test('출판사 전집 번호는 초안 저장 복원되고 다음 권 번호를 제안한다', () async {
    final vm = AuthoringViewModel(
      sl<BookAuthoringRepository>(),
      seriesRepository: sl<SeriesRepository>(),
      contentRepository: sl<ContentRepository>(),
    );
    await vm.load(null);
    vm.updateTitle('테스트');
    vm.updateClassification(publisher: '아람', series: '우리 전집', volume: '3');
    expect(await vm.save(), isTrue);
    final id = vm.draft!.id;
    final seriesId = vm.draft!.content.seriesId!;
    vm.dispose();
    final next = AuthoringViewModel(
      sl<BookAuthoringRepository>(),
      seriesRepository: sl<SeriesRepository>(),
      contentRepository: sl<ContentRepository>(),
    );
    await next.load(id);
    expect(next.publisherInput, '아람');
    expect(next.seriesInput, '우리 전집');
    expect(next.volumeInput, '3');
    next.dispose();
    await sl<ContentRepository>().save(
      book('published').copyWith(seriesId: seriesId, volume: 3),
    );
    final added = AuthoringViewModel(
      sl<BookAuthoringRepository>(),
      seriesRepository: sl<SeriesRepository>(),
      contentRepository: sl<ContentRepository>(),
    );
    await added.load(null, seriesId: seriesId);
    expect(added.volumeInput, '4');
    expect(added.publisherInput, '아람');
    added.dispose();
  });
  test('잘못된 권 번호는 저장을 거절하고 입력을 유지한다', () async {
    final vm = AuthoringViewModel(
      sl<BookAuthoringRepository>(),
      seriesRepository: sl<SeriesRepository>(),
    );
    await vm.load(null);
    vm.updateClassification(volume: '-1');
    expect(await vm.save(), isFalse);
    expect(vm.volumeInput, '-1');
    expect(vm.error, isNotNull);
    vm.dispose();
  });
  test('게시 후 현재 VM을 폐기하여 독서 화면에서 구판을 재생할 수 없다', () async {
    await queue.playAll([book('a'), book('b')]);
    final old = queue.player!;
    await queue.refreshBook(
      book('a', updated: DateTime(2026, 9)).copyWith(title: '새 제목'),
    );
    expect(queue.player, isNull);
    await old.resume();
    expect(engines.first.isPlaying, isFalse);
    await queue.toggle();
    expect(queue.player!.content.title, '새 제목');
  });
}

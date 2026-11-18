import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/local/json_store.dart';
import 'package:mychild_reading/data/repositories/content_repository_impl.dart';
import 'package:mychild_reading/data/repositories/index_repositories.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/child_profile.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/playlist.dart';
import 'package:mychild_reading/domain/entities/reading_event.dart';
import 'package:mychild_reading/domain/entities/series.dart';
import 'package:mychild_reading/domain/enums/enums.dart';

/// 저장소 구현체 검증 — 실제 파일 IO.
void main() {
  late Directory tmp;
  late JsonStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mcr_repo_test_');
    store = JsonStore(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Content book(String id, {String? title, DateTime? updatedAt}) => Content(
        id: id,
        type: ContentType.pagedBook,
        title: title ?? '책 $id',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1),
      );

  group('ContentRepositoryImpl', () {
    test('저장 후 id 로 조회한다', () async {
      final repo = ContentRepositoryImpl(store);
      await repo.save(book('c1', title: '아기 돼지'));

      final out = await repo.getById('c1');
      expect(out, isNotNull);
      expect(out!.title, '아기 돼지');
    });

    test('없는 id 는 null', () async {
      final repo = ContentRepositoryImpl(store);
      expect(await repo.getById('nope'), isNull);
    });

    test('getAll 은 최근 갱신순으로 돌려준다', () async {
      final repo = ContentRepositoryImpl(store);
      await repo.save(book('old', updatedAt: DateTime.utc(2026, 9, 1)));
      await repo.save(book('new', updatedAt: DateTime.utc(2026, 9, 20)));
      await repo.save(book('mid', updatedAt: DateTime.utc(2026, 9, 10)));

      final out = await repo.getAll();
      expect(out.map((c) => c.id), ['new', 'mid', 'old']);
    });

    test('id 가 비면 저장을 거부한다', () async {
      final repo = ContentRepositoryImpl(store);
      expect(
        () => repo.save(book('')),
        throwsA(isA<AppException>().having(
          (e) => e.errorCode.code,
          'errorCode',
          ErrorCode.badRequest.code,
        )),
      );
    });

    test('같은 id 재저장은 덮어쓴다 (업서트)', () async {
      final repo = ContentRepositoryImpl(store);
      await repo.save(book('c1', title: '처음'));
      await repo.save(book('c1', title: '수정'));

      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.single.title, '수정');
    });

    test('삭제하면 미디어 파일까지 사라진다', () async {
      final repo = ContentRepositoryImpl(store);
      await repo.save(book('c1'));
      final img = File('${tmp.path}/library/c1/pages/page_000.jpg');
      await img.parent.create(recursive: true);
      await img.writeAsBytes([1, 2, 3]);

      await repo.delete('c1');

      expect(await repo.getById('c1'), isNull);
      expect(await img.exists(), isFalse);
    });

    test('data.json 없는 폴더는 건너뛰고 나머지를 살린다', () async {
      final repo = ContentRepositoryImpl(store);
      await repo.save(book('good'));
      // 저장 중 죽은 잔재를 흉내낸다 — 폴더만 있고 data.json 이 없다.
      await Directory('${tmp.path}/library/orphan').create(recursive: true);

      final out = await repo.getAll();
      expect(out.map((c) => c.id), ['good']);
    });

    test('페이지·트랙이 있는 책도 온전히 왕복한다', () async {
      final repo = ContentRepositoryImpl(store);
      final src = book('c1').copyWith(
        pages: const [
          BookPage(
            id: 'p0',
            orderIndex: 0,
            imagePath: 'pages/page_000.jpg',
            text: '첫 장',
          ),
        ],
      );
      await repo.save(src);

      final out = await repo.getById('c1');
      expect(out!.pageCount, 1);
      expect(out.pages.single.text, '첫 장');
      expect(out.isPlayable, isTrue);
    });
  });

  group('IndexRepositoryBase — 업서트·삭제 공통 동작', () {
    test('Series 업서트: 같은 id 는 교체', () async {
      final repo = SeriesRepositoryImpl(store);
      await repo.save(const Series(id: 's1', title: '처음'));
      await repo.save(const Series(id: 's1', title: '수정'));

      final all = await repo.getAll();
      expect(all.length, 1);
      expect(all.single.title, '수정');
    });

    test('Series 는 제목순 정렬', () async {
      final repo = SeriesRepositoryImpl(store);
      await repo.save(const Series(id: 'b', title: '나중'));
      await repo.save(const Series(id: 'a', title: '가장먼저'));

      final all = await repo.getAll();
      expect(all.map((s) => s.id), ['a', 'b']);
    });

    test('삭제는 해당 항목만 지운다', () async {
      final repo = SeriesRepositoryImpl(store);
      await repo.save(const Series(id: 's1', title: 'A'));
      await repo.save(const Series(id: 's2', title: 'B'));

      await repo.delete('s1');
      final all = await repo.getAll();
      expect(all.map((s) => s.id), ['s2']);
    });

    test('없는 id 삭제는 조용히 통과한다 (멱등)', () async {
      final repo = SeriesRepositoryImpl(store);
      await repo.save(const Series(id: 's1', title: 'A'));
      await expectLater(repo.delete('nope'), completes);
      expect((await repo.getAll()).length, 1);
    });

    test('id 가 비면 저장을 거부한다', () async {
      final repo = SeriesRepositoryImpl(store);
      expect(
        () => repo.save(const Series(id: '', title: 'x')),
        throwsA(isA<AppException>()),
      );
    });

    test('빈 저장소는 빈 리스트', () async {
      expect(await SeriesRepositoryImpl(store).getAll(), isEmpty);
    });

    test('Playlist 는 최근 생성순', () async {
      final repo = PlaylistRepositoryImpl(store);
      await repo.save(Playlist(
          id: 'p1', title: '옛것', createdAt: DateTime.utc(2026, 9, 1)));
      await repo.save(Playlist(
          id: 'p2', title: '새것', createdAt: DateTime.utc(2026, 9, 20)));

      expect((await repo.getAll()).map((p) => p.id), ['p2', 'p1']);
    });

    test('ChildProfile 왕복', () async {
      final repo = ChildProfileRepositoryImpl(store);
      await repo.save(ChildProfile(
        id: 'ch1',
        name: '첫째',
        birthDate: DateTime.utc(2020, 6, 15),
      ));

      final out = await repo.getById('ch1');
      expect(out!.name, '첫째');
      expect(out.birthDate, DateTime.utc(2020, 6, 15));
    });
  });

  group('ReadingEventRepositoryImpl — 기간·아이 필터', () {
    ReadingEvent ev(String id, DateTime at, {String? childId}) => ReadingEvent(
          id: id,
          contentId: 'c1',
          childId: childId,
          startedAt: at,
        );

    test('최근 기록이 먼저 온다', () async {
      final repo = ReadingEventRepositoryImpl(store);
      await repo.save(ev('e1', DateTime.utc(2026, 9, 1)));
      await repo.save(ev('e2', DateTime.utc(2026, 9, 20)));

      expect((await repo.getAll()).map((e) => e.id), ['e2', 'e1']);
    });

    test('기간으로 거른다', () async {
      final repo = ReadingEventRepositoryImpl(store);
      await repo.save(ev('sep01', DateTime.utc(2026, 9, 1)));
      await repo.save(ev('sep15', DateTime.utc(2026, 9, 15)));
      await repo.save(ev('oct01', DateTime.utc(2026, 10, 1)));

      final out = await repo.query(
        from: DateTime.utc(2026, 9, 10),
        to: DateTime.utc(2026, 9, 30),
      );
      expect(out.map((e) => e.id), ['sep15']);
    });

    test('아이별로 거른다', () async {
      final repo = ReadingEventRepositoryImpl(store);
      await repo.save(ev('a', DateTime.utc(2026, 9, 1), childId: 'ch1'));
      await repo.save(ev('b', DateTime.utc(2026, 9, 2), childId: 'ch2'));
      await repo.save(ev('c', DateTime.utc(2026, 9, 3))); // 미지정

      expect((await repo.query(childId: 'ch1')).map((e) => e.id), ['a']);
      // 인자를 비우면 전체
      expect((await repo.query()).length, 3);
    });

    test('재생 종료 시 같은 id 로 갱신한다', () async {
      final repo = ReadingEventRepositoryImpl(store);
      final started = ev('e1', DateTime.utc(2026, 9, 12, 20));
      await repo.save(started);

      await repo.save(started.copyWith(
        endedAt: DateTime.utc(2026, 9, 12, 20, 8),
        durationSec: 480,
        completed: true,
      ));

      final all = await repo.getAll();
      expect(all.length, 1); // 중복 추가가 아니라 갱신
      expect(all.single.isClosed, isTrue);
      expect(all.single.durationSec, 480);
      expect(all.single.completed, isTrue);
    });
  });
}

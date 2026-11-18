import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/local/json_store.dart';
import 'package:mychild_reading/data/repositories/content_repository_impl.dart';
import 'package:mychild_reading/data/repositories/reading_workspace_repositories.dart';
import 'package:mychild_reading/domain/entities/book_draft.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/reading_position.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/domain/repositories/reading_workspace_repositories.dart';
import 'package:mychild_reading/service_locator.dart';

void main() {
  late Directory directory;
  late JsonStore store;
  late BookDraftRepositoryImpl drafts;
  late ReadingPositionRepositoryImpl positions;
  final now = DateTime.utc(2026, 9, 19);
  Content book({
    String id = 'book-1',
    String title = '원본',
    List<BookPage> pages = const [],
  }) => Content(
    id: id,
    type: ContentType.pagedBook,
    title: title,
    pages: pages,
    createdAt: now,
    updatedAt: now,
  );
  BookDraft draft({
    String id = 'book-1',
    String title = '수정',
    AuthoringStep step = AuthoringStep.voice,
  }) => BookDraft(
    content: book(id: id, title: title),
    step: step,
    savedAt: now,
    sourceUpdatedAt: now,
  );
  ReadingPosition position({String id = 'book-1', String pageId = 'page-b'}) =>
      ReadingPosition(contentId: id, pageId: pageId, updatedAt: now);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mcr_workspace_');
    store = JsonStore(directory);
    drafts = BookDraftRepositoryImpl(store);
    positions = ReadingPositionRepositoryImpl(store);
  });
  tearDown(() async {
    await resetLocator();
    await directory.delete(recursive: true);
  });

  test('초안 저장과 삭제가 기존 책 JSON 및 미디어를 바꾸지 않는다', () async {
    final contents = ContentRepositoryImpl(store);
    await contents.save(book());
    final source = File('${directory.path}/library/book-1/data.json');
    final original = await source.readAsBytes();
    final media = File('${directory.path}/library/book-1/cover.jpg');
    await media.writeAsBytes([1, 2, 3]);
    await drafts.save(draft());
    expect((await drafts.getById('book-1'))!.content.title, '수정');
    expect((await contents.getAll()).single.title, '원본');
    await drafts.delete('book-1');
    expect(await source.readAsBytes(), original);
    expect(await media.readAsBytes(), [1, 2, 3]);
  });

  test('새 초안은 아이 책장 저장소에 나타나지 않는다', () async {
    await drafts.save(draft());
    expect(await ContentRepositoryImpl(store).getAll(), isEmpty);
  });

  test('저장소를 다시 만들어도 제작 단계와 편집 기준 시각을 복구한다', () async {
    await drafts.save(draft());
    final restored = await BookDraftRepositoryImpl(JsonStore(directory))
        .getById('book-1');
    expect(restored!.step, AuthoringStep.voice);
    expect(restored.sourceUpdatedAt, now);
    expect(restored.toJson(), draft().toJson());
  });

  test('구형 Content JSON과 새 작업 파일은 schemaVersion 1에서 공존한다', () async {
    final file = File('${directory.path}/library/book-1/data.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(book().toJson()));
    await drafts.save(draft());
    expect((await ContentRepositoryImpl(store).getById('book-1'))!.title, '원본');
    final envelope = jsonDecode(
      await File('${directory.path}/drafts/book-1/data.json').readAsString(),
    );
    expect(envelope['schemaVersion'], 1);
    expect(
      jsonDecode(await file.readAsString()).containsKey('schemaVersion'),
      isFalse,
    );
  });

  test('알 수 없는 제작 단계와 누락 선택 필드는 안전하게 읽는다', () {
    final data = draft().toJson()
      ..['step'] = 'futureStep'
      ..remove('sourceUpdatedAt');
    final restored = BookDraft.fromJson(data);
    expect(restored.step, AuthoringStep.cover);
    expect(restored.isRevision, isFalse);
    expect(restored.content.title, '수정');
  });

  test('동시 초안 저장은 호출 순서대로 완료되고 마지막 입력이 남는다', () async {
    await Future.wait(
      List.generate(12, (i) => drafts.save(draft(title: '수정 $i'))),
    );
    expect((await drafts.getById('book-1'))!.content.title, '수정 11');
    expect(
      await File('${directory.path}/drafts/book-1/data.json.tmp').exists(),
      isFalse,
    );
  });

  test('저장 실패 이후에도 다음 유효한 저장을 수행한다', () async {
    await expectLater(
      drafts.save(draft(id: '../escape')),
      throwsA(isA<AppException>()),
    );
    await drafts.save(draft());
    expect(await drafts.getById('book-1'), isNotNull);
  });

  test('저장 직후 기다리지 않고 목록을 요청해도 새 초안을 포함한다', () async {
    final saving = drafts.save(draft());
    final all = await drafts.getAll();
    await saving;
    expect(all.single.id, 'book-1');
  });

  for (final id in ['', '..', '../book', '/tmp/book', r'a\b', 'a/b']) {
    test('경로 식별자 $id 를 읽기 쓰기 삭제에서 거절한다', () async {
      await expectLater(positions.getById(id), throwsA(isA<AppException>()));
      await expectLater(
        positions.save(position(id: id)),
        throwsA(isA<AppException>()),
      );
      await expectLater(positions.delete(id), throwsA(isA<AppException>()));
    });
  }

  for (final payload in [
    '{broken',
    '{"schemaVersion":99,"data":{}}',
    '{"schemaVersion":1,"data":{"contentId":"other","pageId":"p"}}',
  ]) {
    test('손상 미래버전 식별자불일치 파일을 덮거나 삭제하지 않는다: $payload', () async {
      final file = File('${directory.path}/reading_positions/book-1/data.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(payload);
      await expectLater(
        positions.save(position()),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        positions.delete('book-1'),
        throwsA(isA<AppException>()),
      );
      expect(await file.readAsString(), payload);
    });
  }

  test('실제 파일 쓰기 실패가 저장 성공으로 처리되지 않는다', () async {
    await File('${directory.path}/drafts').writeAsString('디렉토리 생성 불가');
    await expectLater(
      drafts.save(draft()),
      throwsA(
        isA<AppException>().having(
          (e) => e.errorCode,
          "code",
          ErrorCode.storageFailure,
        ),
      ),
    );
    expect(await File('${directory.path}/drafts').readAsString(), '디렉토리 생성 불가');
  });

  test('페이지 위치 round-trip 및 순서 변경 후 id로 복구한다', () async {
    await positions.save(position());
    final restored = await ReadingPositionRepositoryImpl(JsonStore(directory))
        .getById('book-1');
    final content = book(
      pages: [
        const BookPage(id: 'page-a', orderIndex: 1, imagePath: 'a.jpg'),
        const BookPage(id: 'page-b', orderIndex: 0, imagePath: 'b.jpg'),
      ],
    );
    expect(restored!.toJson(), position().toJson());
    expect(restored.resolvePageIndex(content), 0);
    expect(
      restored.resolvePageIndex(
        content.copyWith(
          pages: [
            content.pages[0].copyWith(orderIndex: 0),
            content.pages[1].copyWith(orderIndex: 1),
          ],
        ),
      ),
      1,
    );
  });

  test('읽던 페이지 삭제는 첫 페이지, 빈 책은 위치 없음이다', () {
    expect(position().resolvePageIndex(book()), isNull);
    final content = book(
      pages: [const BookPage(id: 'new', orderIndex: 0, imagePath: 'new.jpg')],
    );
    expect(position().resolvePageIndex(content), 0);
    expect(position(id: 'other').resolvePageIndex(content), 0);
  });

  test('빈 페이지 id 저장을 거절하고 없는 위치 삭제는 멱등이다', () async {
    await expectLater(
      positions.save(position(pageId: ' ')),
      throwsA(isA<AppException>()),
    );
    await positions.delete('missing');
    await positions.delete('missing');
    expect(await positions.getById('missing'), isNull);
  });

  test('저장 호출 후 중첩 목록 변경은 이미 요청한 저장에 섞이지 않는다', () async {
    final pages = <BookPage>[];
    final snapshot = BookDraft(
      content: book(pages: pages),
      savedAt: now,
    );
    final saving = drafts.save(snapshot);
    pages.add(
      const BookPage(id: 'later', orderIndex: 0, imagePath: 'later.jpg'),
    );
    await saving;
    expect((await drafts.getById('book-1'))!.content.pages, isEmpty);
  });

  test('문법은 정상이나 pages 자료형이 손상된 초안도 보존한다', () async {
    final payload = draft().toJson();
    (payload['content'] as Map)['pages'] = {'recoverable': '원문'};
    final file = File('${directory.path}/drafts/book-1/data.json');
    await file.parent.create(recursive: true);
    final original = jsonEncode({'schemaVersion': 1, 'data': payload});
    await file.writeAsString(original);
    await expectLater(drafts.save(draft()), throwsA(isA<AppException>()));
    await expectLater(drafts.delete('book-1'), throwsA(isA<AppException>()));
    expect(await file.readAsString(), original);
  });

  test('실제 DI 등록 경로에서 두 저장소를 singleton으로 사용한다', () async {
    await registerWith(directory);
    expect(
      identical(sl<BookDraftRepository>(), sl<BookDraftRepository>()),
      isTrue,
    );
    await sl<BookDraftRepository>().save(draft());
    await sl<ReadingPositionRepository>().save(position());
    await resetLocator();
    await registerWith(directory);
    expect(
      (await sl<BookDraftRepository>().getById('book-1'))!.step,
      AuthoringStep.voice,
    );
    expect(
      (await sl<ReadingPositionRepository>().getById('book-1'))!.pageId,
      'page-b',
    );
  });
}

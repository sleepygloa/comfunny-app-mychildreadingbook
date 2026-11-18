import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/data/local/authoring_media_store.dart';
import 'package:mychild_reading/data/local/json_store.dart';
import 'package:mychild_reading/data/repositories/book_authoring_repository_impl.dart';
import 'package:mychild_reading/data/repositories/content_repository_impl.dart';
import 'package:mychild_reading/data/repositories/reading_workspace_repositories.dart';
import 'package:mychild_reading/domain/entities/audio_track.dart';
import 'package:mychild_reading/domain/entities/book_draft.dart';
import 'package:mychild_reading/domain/entities/book_page.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/presentation/authoring/authoring_view_model.dart';

void main() {
  late Directory dir;
  late BookAuthoringRepositoryImpl author;
  late ContentRepositoryImpl contents;
  late BookDraftRepositoryImpl drafts;
  late AuthoringMediaStore media;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mcr_author_');
    final store = JsonStore(dir);
    contents = ContentRepositoryImpl(store);
    drafts = BookDraftRepositoryImpl(store);
    media = AuthoringMediaStore(dir);
    author = BookAuthoringRepositoryImpl(
      contents: contents,
      revisions: contents,
      drafts: drafts,
      media: media,
    );
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<String> source(String name) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes([1, 2, 3]);
    return f.path;
  }

  Future<BookDraft> ready() async {
    final d = await author.create('작은 곰');
    final image = await author.importMedia(
      d.id,
      await source('photo.jpg'),
      'jpg',
    );
    final voice = await author.importMedia(
      d.id,
      await source('voice.m4a'),
      'm4a',
    );
    return d.copyWith(
      content: d.content.copyWith(
        seriesId: 'series',
        volume: 1,
        pages: [
          BookPage(
            id: 'p1',
            orderIndex: 0,
            imagePath: image,
            tracks: [
              AudioTrack(
                id: 'a1',
                source: AudioSource.parentRecording,
                path: voice,
                createdAt: DateTime.now(),
              ),
            ],
          ),
        ],
      ),
      step: AuthoringStep.preview,
    );
  }

  test('전집 또는 번호 누락은 책장 저장을 거절하고 초안을 보존한다', () async {
    for (final field in ['seriesId', 'volume']) {
      final d = await ready();
      final json = d.toJson();
      final content = Map<String, Object?>.from(json['content']! as Map);
      content[field] = null;
      json['content'] = content;
      await expectLater(
        author.publish(BookDraft.fromJson(json)),
        throwsA(isA<AppException>()),
      );
      expect(await drafts.getById(d.id), isNotNull);
      expect(await contents.getById(d.id), isNull);
    }
  });
  test('표지 교체는 본문과 분리되며 저장과 재편집에서 사진을 유지한다', () async {
    final d = await ready();
    await author.save(d);
    final vm = AuthoringViewModel(author);
    await vm.load(d.id);
    await vm.setCoverPhoto(await source('cover.jpg'));
    final firstCover = vm.draft!.content.coverPath;
    await vm.setCoverPhoto(await source('new-cover.jpg'));
    expect(vm.draft!.content.coverPath, isNot(firstCover));
    expect(
      vm.draft!.content.pages.single.toJson(),
      d.content.pages.single.toJson(),
    );
    await vm.save();
    final book = await author.publish(vm.draft!);
    expect(await media.hasFile('library', book.id, book.coverPath!), isTrue);
    final reopened = await author.open(book.id);
    expect(
      await media.hasFile('drafts', book.id, reopened.content.coverPath!),
      isTrue,
    );
    expect(reopened.content.pageCount, 1);
    vm.dispose();
  });

  test('한 권을 제작 게시하고 완성본의 사진과 음성을 읽는다', () async {
    final d = await ready();
    final result = await author.publish(d);
    expect((await contents.getAll()).single.title, '작은 곰');
    expect(
      await media.hasFile('library', d.id, result.pages.single.imagePath),
      isTrue,
    );
    expect(
      await media.hasFile(
        'library',
        d.id,
        result.pages.single.tracks.single.path!,
      ),
      isTrue,
    );
    expect(await drafts.getById(d.id), isNull);
    expect(await Directory('${dir.path}/drafts/${d.id}').exists(), isFalse);
  });
  test('수정 초안 폐기는 기존 책 및 원본 미디어를 유지한다', () async {
    final book = await author.publish(await ready());
    final original = await File('${dir.path}/library/${book.id}/data.json')
        .readAsBytes();
    final d = await author.open(book.id);
    expect(d.sourceUpdatedAt, book.updatedAt);
    expect(d.content.pages.single.imagePath, startsWith('assets/'));
    await author.discard(book.id);
    expect(
      await File('${dir.path}/library/${book.id}/data.json').readAsBytes(),
      original,
    );
    expect(
      await media.hasFile('library', book.id, book.pages.single.imagePath),
      isTrue,
    );
    expect(await Directory('${dir.path}/drafts/${book.id}').exists(), isFalse);
  });
  test('사진 누락 게시 실패는 기존 책과 수정 초안을 보존한다', () async {
    final book = await author.publish(await ready());
    final d = await author.open(book.id);
    await (await media.file(
      'drafts',
      book.id,
      d.content.pages.single.imagePath,
    )).delete();
    await expectLater(author.publish(d), throwsA(isA<AppException>()));
    expect((await contents.getById(book.id))!.toJson(), book.toJson());
    expect(await drafts.getById(book.id), isNotNull);
  });
  test('편집 중 원본 변경은 조건부 게시를 거절한다', () async {
    final book = await author.publish(await ready());
    final d = await author.open(book.id);
    await contents.save(
      book.copyWith(
        title: '다른 수정',
        updatedAt: book.updatedAt.add(const Duration(seconds: 1)),
      ),
    );
    await expectLater(
      author.publish(d),
      throwsA(
        isA<AppException>().having(
          (e) => e.errorCode,
          'code',
          ErrorCode.conflict,
        ),
      ),
    );
    expect((await contents.getById(book.id))!.title, '다른 수정');
    expect(await drafts.getById(book.id), isNotNull);
  });
  test('기기 음성 준비와 무관하게 사진 책을 저장한다', () async {
    final d = await ready();
    final page = d.content.pages.single.copyWith(
      text: '안녕',
      tracks: [
        AudioTrack(
          id: 'tts',
          source: AudioSource.deviceTts,
          createdAt: DateTime.now(),
        ),
      ],
    );
    final book = await author.publish(
      d.copyWith(content: d.content.copyWith(pages: [page])),
    );
    expect(book.pages.single.tracks.single.source, AudioSource.deviceTts);
    expect((await contents.getAll()).single.id, book.id);
  });
  test('미디어 경로 순회와 링크를 거절한다', () async {
    await expectLater(
      media.file('drafts', 'book', '../outside'),
      throwsA(isA<AppException>()),
    );
    final target = Directory('${dir.path}/outside');
    await target.create();
    await Directory('${dir.path}/drafts').create();
    await Link('${dir.path}/drafts/book').create(target.path);
    await expectLater(
      media.file('drafts', 'book', 'photo.jpg'),
      throwsA(isA<AppException>()),
    );
  });
  test('중복 게시 요청은 하나만 반영하고 이후 요청은 원본을 바꾸지 않는다', () async {
    final d = await ready();
    final first = author.publish(d);
    final second = author.publish(d);
    await expectLater(second, throwsA(isA<AppException>()));
    final published = await first;
    expect((await contents.getAll()).single.toJson(), published.toJson());
  });
  test('제작 VM은 사진 순서와 글 녹음을 저장하고 다시 연다', () async {
    final vm = AuthoringViewModel(author);
    await vm.load(null);
    vm.updateTitle('우리 책');
    await vm.addPhoto(await source('a.jpg'));
    await vm.addPhoto(await source('b.jpg'));
    final id = vm.draft!.id;
    final page = vm.draft!.content.pages.first.id;
    vm.setText(page, '작은 곰');
    vm.reorder(0, 1);
    await vm.attachRecording(page, await source('v.m4a'));
    vm.setStep(AuthoringStep.voice);
    expect(await vm.save(), isTrue);
    vm.dispose();
    final restored = AuthoringViewModel(author);
    await restored.load(id);
    expect(restored.draft!.step, AuthoringStep.voice);
    expect(restored.draft!.content.orderedPages.last.id, page);
    expect(restored.draft!.content.orderedPages.last.text, '작은 곰');
    expect(restored.isDirty, isFalse);
    restored.dispose();
  });
  test('연속 촬영은 매 장을 즉시 저장하고 재열기에서 순서를 유지한다', () async {
    final vm = AuthoringViewModel(author);
    await vm.load(null);
    final id = vm.draft!.id;
    expect(await vm.capturePage(await source('left-right-1.jpg')), isTrue);
    expect((await drafts.getById(id))!.content.pageCount, 1);
    expect(await vm.capturePage(await source('left-right-2.jpg')), isTrue);
    final before = vm.draft!.content.orderedPages.map((p) => p.id).toList();
    expect(await vm.capturePage('${dir.path}/missing.jpg'), isFalse);
    expect(vm.draft!.content.pageCount, 2);
    final reopened = await author.open(id);
    expect(reopened.content.orderedPages.map((p) => p.id), before);
    expect(reopened.content.orderedPages.map((p) => p.orderIndex), [0, 1]);
    expect(reopened.content.coverPath, isNull);
    vm.dispose();
  });

  test('음성 없는 사진 책 저장과 PNG 교체는 기존 음성 및 페이지 ID를 보존한다', () async {
    final d = await ready();
    final noVoice = d.copyWith(
      content: d.content.copyWith(
        pages: [d.content.pages.single.copyWith(tracks: [])],
      ),
    );
    final photoBook = await author.publish(noVoice);
    expect(photoBook.pages.single.tracks, isEmpty);
    final second = await ready();
    await author.save(second);
    final vm = AuthoringViewModel(author);
    await vm.load(second.id);
    await vm.replacePagePhoto(
      second.content.pages.single.id,
      await source('cropped.png'),
    );
    expect(vm.error, isNull);
    final result = await author.publish(vm.draft!);
    expect(result.pages.single.id, second.content.pages.single.id);
    expect(result.pages.single.imagePath, endsWith('.png'));
    expect(
      result.pages.single.tracks.single.id,
      second.content.pages.single.tracks.single.id,
    );
    expect(
      await media.hasFile(
        'library',
        result.id,
        result.pages.single.tracks.single.path!,
      ),
      isTrue,
    );
    vm.dispose();
  });

  test('미완성 책 게시 오류 후 VM 입력을 유지한다', () async {
    final vm = AuthoringViewModel(author);
    await vm.load(null);
    vm.updateTitle('아직 사진 없음');
    expect(await vm.publish(), isNull);
    expect(vm.error, isNotNull);
    expect(vm.draft!.content.title, '아직 사진 없음');
    expect(vm.isBusy, isFalse);
    vm.dispose();
  });
}

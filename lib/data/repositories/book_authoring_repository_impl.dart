import '../../domain/repositories/pending_writes.dart';

import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../core/app_logger.dart';
import '../../core/error_codes.dart';
import '../../domain/entities/audio_track.dart';
import '../../domain/entities/book_draft.dart';
import '../../domain/entities/book_page.dart';
import '../../domain/entities/content.dart';
import '../../domain/enums/enums.dart';
import '../../domain/repositories/book_authoring_repository.dart';
import '../../domain/repositories/reading_workspace_repositories.dart';
import '../../domain/repositories/repositories.dart';
import '../local/authoring_media_store.dart';

class BookAuthoringRepositoryImpl
    implements BookAuthoringRepository, PendingWrites {
  BookAuthoringRepositoryImpl({
    required this.contents,
    required this.revisions,
    required this.drafts,
    required this.media,
  });

  final ContentRepository contents;
  final ContentRevisionRepository revisions;
  final BookDraftRepository drafts;
  final AuthoringMediaStore media;
  Future<void> _pending = Future<void>.value();
  @override
  Future<void> waitForWrites() => _pending;

  Future<T> _run<T>(Future<T> Function() action) => media.gate.write(() {
    final result = _pending.then((_) async {
      try {
        return await action();
      } on FileSystemException catch (error) {
        throw AppException(
          ErrorCode.storageFailure,
          detail: '제작 파일 처리 실패',
          cause: error,
        );
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  });

  BookDraft _snapshot(BookDraft draft) => BookDraft.fromJson(
    Map<String, Object?>.from(jsonDecode(jsonEncode(draft.toJson())) as Map),
  );

  @override
  Future<BookDraft> create(String title) => _run(() async {
    final now = DateTime.now();
    final draft = BookDraft(
      content: Content(
        id: const Uuid().v4(),
        type: ContentType.pagedBook,
        title: title.trim(),
        createdAt: now,
        updatedAt: now,
      ),
      savedAt: now,
    );
    await drafts.save(draft);
    return draft;
  });

  @override
  Future<BookDraft> open(String contentId) => _run(() async {
    media.validateId(contentId);
    final existing = await drafts.getById(contentId);
    if (existing != null) return existing;
    final source = await contents.getById(contentId);
    if (source == null || !source.isBook) {
      throw const AppException(ErrorCode.notFound, detail: '편집할 책이 없습니다');
    }
    // FLOW 1: 원본의 미디어를 모두 복제한 뒤 초안 참조를 확정한다.
    final content = await _copyContent(
      source,
      'library',
      'drafts',
      'assets/${const Uuid().v4()}',
    );
    final draft = BookDraft(
      content: content,
      savedAt: DateTime.now(),
      sourceUpdatedAt: source.updatedAt,
    );
    // FLOW 9: 실패한 복제는 초안으로 노출하지 않는다.
    await drafts.save(draft);
    return draft;
  });

  @override
  Future<void> save(BookDraft draft) {
    final snapshot = _snapshot(draft);
    return _run(() => drafts.save(snapshot));
  }

  @override
  Future<String> importMedia(
    String contentId,
    String sourcePath,
    String extension,
  ) => _run(() async {
    if (await drafts.getById(contentId) == null) {
      throw const AppException(ErrorCode.notFound, detail: '먼저 초안을 만들어 주세요');
    }
    return media.importFile(contentId, sourcePath, extension);
  });

  @override
  Future<void> discard(String contentId) => _run(() async {
    await drafts.delete(contentId);
    await media.deleteDraftFiles(contentId);
  });

  @override
  Future<Content> publish(BookDraft draft) {
    final snapshot = _snapshot(draft);
    return _run(() async {
      // FLOW 1: 실패해도 사용자가 마지막으로 작성한 내용을 다시 열 수 있게 보존한다.
      if (await drafts.getById(snapshot.id) == null) {
        throw const AppException(ErrorCode.notFound, detail: '초안이 없습니다');
      }
      await drafts.save(snapshot);
      await _validate(snapshot.content);
      // FLOW 2: 새 미디어 묶음 완성 전에는 기존 data.json을 만지지 않는다.
      final content = await _copyContent(
        snapshot.content,
        'drafts',
        'library',
        'revisions/${const Uuid().v4()}',
      );
      var now = DateTime.now();
      final expected = snapshot.sourceUpdatedAt;
      if (expected != null && !now.isAfter(expected)) {
        now = expected.add(const Duration(microseconds: 1));
      }
      final published = content.copyWith(updatedAt: now);
      // FLOW 3: 원본이 바뀌었으면 조건부 쓰기가 거절한다.
      await revisions.saveRevision(published, expectedUpdatedAt: expected);
      // FLOW 9: 게시 성공을 초안 정리 실패로 되돌리지 않는다.
      try {
        await drafts.delete(snapshot.id);
        await media.deleteDraftFiles(snapshot.id);
      } on Object catch (_) {
        AppLogger.w('게시 완료 후 초안 정리 실패. 원본은 게시되었습니다.');
      }
      return published;
    });
  }

  Future<void> _validate(Content content) async {
    media.validateId(content.id);
    if ((content.seriesId ?? '').trim().isEmpty || (content.volume ?? 0) < 1) {
      throw const AppException(
        ErrorCode.badRequest,
        detail: '전집과 1 이상의 책 번호를 입력해 주세요.',
      );
    }
    if (!content.isBook ||
        content.title.trim().isEmpty ||
        content.pages.isEmpty ||
        content.pages.map((p) => p.id).toSet().length != content.pages.length) {
      throw const AppException(
        ErrorCode.badRequest,
        detail: '제목과 페이지를 확인해 주세요',
      );
    }
    for (final page in content.pages) {
      if (page.id.isEmpty ||
          !await media.hasFile('drafts', content.id, page.imagePath)) {
        throw const AppException(ErrorCode.badRequest, detail: '페이지 사진이 필요합니다');
      }
    }
  }

  Future<Content> _copyContent(
    Content content,
    String from,
    String to,
    String prefix,
  ) async {
    final mapped = <String, String>{};
    Future<String> copyPath(String path) async {
      if (mapped.containsKey(path)) return mapped[path]!;
      final extension = path.split('.').last;
      if (!['jpg', 'jpeg', 'png', 'm4a', 'wav', 'mp3'].contains(extension)) {
        throw const AppException(
          ErrorCode.badRequest,
          detail: '지원하지 않는 미디어 형식',
        );
      }
      final target = '$prefix/${const Uuid().v4()}.$extension';
      await media.copy(
        await media.file(from, content.id, path),
        await media.file(to, content.id, target),
      );
      mapped[path] = target;
      return target;
    }

    final pages = <BookPage>[];
    for (final page in content.orderedPages) {
      final tracks = <AudioTrack>[];
      for (final track in page.tracks) {
        tracks.add(
          track.hasFile
              ? track.copyWith(path: await copyPath(track.path!))
              : track,
        );
      }
      pages.add(
        page.copyWith(
          imagePath: await copyPath(page.imagePath),
          tracks: tracks,
          orderIndex: pages.length,
        ),
      );
    }
    return content.copyWith(
      pages: pages,
      coverPath: content.coverPath == null
          ? null
          : await copyPath(content.coverPath!),
    );
  }
}

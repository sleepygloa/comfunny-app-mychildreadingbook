import '../../domain/repositories/pending_writes.dart';

import 'dart:io';
import 'dart:convert';

import '../../core/error_codes.dart';
import '../../domain/entities/book_draft.dart';
import '../../domain/entities/reading_position.dart';
import '../../domain/repositories/reading_workspace_repositories.dart';
import '../local/app_paths.dart';
import '../local/json_store.dart';

/// 새 작업 파일에만 적용한다. 손상/미래 버전 파일을 빈 신규 파일처럼 덮지 않는다.
///
/// DI singleton 내 변경을 직렬화하여 같은 .tmp 파일의 쓰기 경합을 방지한다.
abstract class _WorkspaceRepository<T> implements PendingWrites {
  _WorkspaceRepository(this.store, this.directory);

  final JsonStore store;
  final String directory;
  Future<void> _pending = Future<void>.value();
  @override
  Future<void> waitForWrites() => _pending;

  String idOf(T item);
  T fromJson(Map<String, Object?> json);
  Map<String, Object?> toJson(T item);
  bool isValid(T item);
  bool isRawValid(Map<String, Object?> json);

  String _path(String id) {
    // FLOW 1: 식별자를 경로로 쓰므로 점·구분자·절대경로를 허용하지 않는다.
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const AppException(ErrorCode.badRequest, detail: '잘못된 콘텐츠 id');
    }
    return '$directory/$id/data.json';
  }

  Future<T?> _read(String id) async {
    final path = _path(id);
    final json = await store.readMap(path);
    if (json == null) {
      if (await store.exists(path)) {
        throw const AppException(
          ErrorCode.storageFailure,
          detail: '작업 파일이 손상되어 보존했습니다',
        );
      }
      return null;
    }
    if (!isRawValid(json)) {
      throw const AppException(
        ErrorCode.storageFailure,
        detail: '작업 파일 자료형이 손상되어 보존했습니다',
      );
    }
    final item = fromJson(json);
    if (idOf(item) != id || !isValid(item)) {
      throw const AppException(
        ErrorCode.storageFailure,
        detail: '작업 파일 식별자 또는 필수값 불일치',
      );
    }
    return item;
  }

  Future<T?> getById(String id) async {
    await _pending;
    return _read(id);
  }

  Future<void> _mutate(Future<void> Function() action) => store.gate.write(() {
    final result = _pending.then((_) async {
      try {
        await action();
      } on FileSystemException catch (error) {
        throw AppException(
          ErrorCode.storageFailure,
          detail: '작업 파일 변경 실패',
          cause: error,
        );
      }
    });
    // 실패를 호출자에게 전달하되 다음 저장까지 영구 차단하지 않는다.
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  });

  Future<void> save(T item) async {
    // FLOW 1: 호출 시점에 중첩 목록까지 복사한다. 대기 중 편집을 섞지 않는다.
    final snapshot = Map<String, Object?>.from(
      jsonDecode(jsonEncode(toJson(item))) as Map,
    );
    final frozen = fromJson(snapshot);
    final id = idOf(frozen);
    final path = _path(id);
    if (!isValid(frozen) || !isRawValid(snapshot)) {
      throw const AppException(ErrorCode.badRequest, detail: '작업 데이터 필수값 누락');
    }
    return _mutate(() async {
      // FLOW 2: 미래 버전/손상 원본이면 저장을 중단한다.
      await _read(id);
      // FLOW 9: 호출 시점 스냅샷을 원자적으로 교체한다.
      await store.writeMap(path, snapshot);
    });
  }

  Future<void> delete(String id) => _mutate(() async {
    // FLOW 1: 미래 버전/손상 파일은 이 앱이 해석할 수 없으므로 보존한다.
    await _read(id);
    // FLOW 9: 작업 메타만 삭제. 완성본/미디어 삭제는 별도 소유권 계약이다.
    await store.delete(_path(id));
  });
}

class BookDraftRepositoryImpl extends _WorkspaceRepository<BookDraft>
    implements BookDraftRepository {
  BookDraftRepositoryImpl(JsonStore store) : super(store, AppPaths.draftsDir);

  @override
  String idOf(BookDraft item) => item.id;
  @override
  BookDraft fromJson(Map<String, Object?> json) => BookDraft.fromJson(json);
  @override
  Map<String, Object?> toJson(BookDraft item) => item.toJson();
  @override
  bool isValid(BookDraft item) => item.content.isBook && item.id.isNotEmpty;

  @override
  bool isRawValid(Map<String, Object?> json) {
    final content = json['content'];
    if (content is! Map ||
        !_date(json['savedAt']) ||
        (json['sourceUpdatedAt'] != null && !_date(json['sourceUpdatedAt'])) ||
        (json['step'] != null && json['step'] is! String)) {
      return false;
    }
    if (content['id'] is! String ||
        content['title'] is! String ||
        content['type'] != 'pagedBook' ||
        !_date(content['createdAt']) ||
        !_date(content['updatedAt'])) {
      return false;
    }
    final pages = content['pages'];
    if (pages is! List) return false;
    for (final page in pages) {
      if (page is! Map ||
          page['id'] is! String ||
          page['imagePath'] is! String ||
          page['orderIndex'] is! int ||
          (page['text'] != null && page['text'] is! String)) {
        return false;
      }
      final tracks = page['tracks'];
      if (tracks is! List) return false;
      for (final track in tracks) {
        if (track is! Map ||
            track['id'] is! String ||
            track['source'] is! String ||
            !_date(track['createdAt']) ||
            (track['path'] != null && track['path'] is! String) ||
            (track['durationMs'] != null && track['durationMs'] is! int)) {
          return false;
        }
      }
    }
    return content['tags'] is List &&
        (content['tags'] as List).every((tag) => tag is String);
  }

  @override
  Future<List<BookDraft>> getAll() async {
    // 한 초안이 손상되면 부모 화면이 오류를 표시하도록 전파한다.
    // 조용히 숨기면 사용자가 저장한 초안이 없어진 것으로 오해한다.
    await _pending;
    final ids = await store.listSubdirectories(AppPaths.draftsDir);
    final drafts = <BookDraft>[];
    for (final id in ids) {
      final draft = await getById(id);
      if (draft != null) drafts.add(draft);
    }
    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }
}

class ReadingPositionRepositoryImpl
    extends _WorkspaceRepository<ReadingPosition>
    implements ReadingPositionRepository {
  ReadingPositionRepositoryImpl(JsonStore store)
    : super(store, AppPaths.readingPositionsDir);

  @override
  String idOf(ReadingPosition item) => item.contentId;
  @override
  ReadingPosition fromJson(Map<String, Object?> json) =>
      ReadingPosition.fromJson(json);
  @override
  Map<String, Object?> toJson(ReadingPosition item) => item.toJson();
  @override
  bool isRawValid(Map<String, Object?> json) =>
      json['contentId'] is String &&
      json['pageId'] is String &&
      _date(json['updatedAt']);

  @override
  bool isValid(ReadingPosition item) =>
      item.contentId.isNotEmpty && item.pageId.trim().isNotEmpty;
}

// 새 작업 파일은 손상된 시각을 epoch로 바꿔 덮어쓰지 않는다.
bool _date(Object? value) =>
    value is String && DateTime.tryParse(value) != null;

import '../../domain/repositories/pending_writes.dart';
import '../../core/app_logger.dart';
import '../../core/error_codes.dart';
import '../../domain/entities/content.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/repositories/book_authoring_repository.dart';
import '../local/app_paths.dart';
import '../local/json_store.dart';

/// 콘텐츠 저장소 구현 — 콘텐츠별 `library/{id}/data.json`.
///
/// 왜 콘텐츠마다 파일을 나누나: 한 파일에 전부 담으면 책 하나를 고칠 때마다 전체를
/// 다시 써야 한다. 페이지 사진이 늘면 파일이 커지고, 쓰다가 죽으면 **전부** 잃는다.
/// 콘텐츠별로 나누면 손상 범위가 그 책 하나로 갇힌다.
class ContentRepositoryImpl
    implements ContentRepository, ContentRevisionRepository, PendingWrites {
  ContentRepositoryImpl(this._store);

  final JsonStore _store;
  Future<void> _pending = Future<void>.value();
  @override
  Future<void> waitForWrites() => _pending;

  Future<void> _change(Future<void> Function() action) => _store.gate.write(() {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  });

  @override
  Future<void> saveRevision(
    Content content, {
    required DateTime? expectedUpdatedAt,
  }) {
    final snapshot = content.toJson();
    return _change(() async {
      final path = AppPaths.contentDataFile(content.id);
      final json = await _store.readMap(path);
      if (json == null && await _store.exists(path)) {
        throw const AppException(
          ErrorCode.storageFailure,
          detail: '원본 책을 읽을 수 없습니다',
        );
      }
      final current = json == null ? null : Content.fromJson(json);
      if ((current == null && expectedUpdatedAt != null) ||
          (current != null &&
              (expectedUpdatedAt == null ||
                  current.updatedAt != expectedUpdatedAt))) {
        throw const AppException(
          ErrorCode.conflict,
          detail: '편집 중 원본 책이 변경되었습니다',
        );
      }
      await _store.writeMap(path, snapshot);
    });
  }

  @override
  Future<List<Content>> getAll() async {
    // FLOW 1: library/ 하위 폴더 목록을 얻는다. 폴더명 = contentId
    final ids = await _store.listSubdirectories(AppPaths.libraryDir);
    final out = <Content>[];

    // FLOW 2: 폴더마다 data.json 을 읽는다
    for (final id in ids) {
      try {
        final json = await _store.readMap(AppPaths.contentDataFile(id));
        if (json == null) {
          // 폴더는 있는데 data.json 이 없다 — 저장 중 죽은 잔재일 수 있다.
          AppLogger.w('data.json 없는 콘텐츠 폴더: $id');
          continue;
        }
        out.add(Content.fromJson(json));
      } on AppException catch (e) {
        // FLOW 3: 한 책이 미래 스키마여도 나머지는 보여준다.
        //         전체를 막으면 사용자가 앱을 아예 못 쓴다.
        AppLogger.w('콘텐츠 로드 건너뜀: $id (${e.errorCode.code})');
      }
    }

    // FLOW 9: 최근 갱신순. 사용자가 방금 만든 책이 위에 오는 것이 기대에 맞다.
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  @override
  Future<Content?> getById(String id) async {
    final json = await _store.readMap(AppPaths.contentDataFile(id));
    if (json == null) return null;
    return Content.fromJson(json);
  }

  @override
  Future<void> save(Content content) => _change(() async {
    // FLOW 1: 최소 검증 — id 없는 콘텐츠는 경로를 만들 수 없다
    if (content.id.isEmpty) {
      throw const AppException(
        ErrorCode.badRequest,
        detail: 'content.id 가 비었다',
      );
    }
    // FLOW 2: 원자적 저장 (JsonStore 가 임시파일 → rename)
    await _store.writeMap(
      AppPaths.contentDataFile(content.id),
      content.toJson(),
    );
  });

  @override
  Future<void> delete(String id) => _change(() async {
    // 콘텐츠 폴더를 통째로 지운다 — data.json·페이지 이미지·오디오·영상이 함께 사라진다.
    // 폴더 단위로 두었기 때문에 고아 미디어가 남지 않는다.
    await _store.deleteDirectory(AppPaths.contentDir(id));
    AppLogger.i('콘텐츠 삭제: $id');
  });
}

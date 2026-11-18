import '../../domain/repositories/pending_writes.dart';
import '../../core/error_codes.dart';
import '../../domain/repositories/recent_playback_repository.dart';
import '../local/json_store.dart';

/// 책은 복제하지 않고 ID만 보관한다. 복원 시 원본 저장소의 최신 책을 조회한다.
class RecentPlaybackRepositoryImpl
    implements RecentPlaybackRepository, PendingWrites {
  RecentPlaybackRepositoryImpl(this.store);
  final JsonStore store;
  static const path = 'index/recent_playback.json';
  Future<void> _pending = Future.value();
  @override
  Future<void> waitForWrites() => _pending;

  @override
  Future<RecentPlayback> load() async {
    final raw = await store.readMap(path);
    if (raw == null) {
      if (await store.exists(path)) _invalid();
      return RecentPlayback(bookIds: []);
    }
    final ids = raw['bookIds'];
    final current = raw['currentId'];
    if (ids is! List ||
        ids.length > 1000 ||
        ids.any(
          (id) => id is! String || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id),
        ) ||
        ids.toSet().length != ids.length ||
        (current != null && (current is! String || !ids.contains(current)))) {
      _invalid();
    }
    return RecentPlayback(
      bookIds: ids.cast<String>(),
      currentId: current as String?,
    );
  }

  @override
  Future<void> save(RecentPlayback value) => store.gate.write(() {
    final task = _pending.then((_) async {
      // 해석 못 하는 기존 파일은 새 목록으로 덮지 않는다.
      await load();
      if (value.bookIds.length > 1000 ||
          value.bookIds.toSet().length != value.bookIds.length ||
          value.bookIds.any(
            (id) => !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id),
          ) ||
          (value.currentId != null &&
              !value.bookIds.contains(value.currentId))) {
        _invalid();
      }
      await store.writeMap(path, {
        'bookIds': value.bookIds,
        'currentId': value.currentId,
      });
    });
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  });

  Never _invalid() => throw const AppException(ErrorCode.storageFailure);
}

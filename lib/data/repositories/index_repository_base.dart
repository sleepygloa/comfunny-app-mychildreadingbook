import '../../domain/repositories/pending_writes.dart';

import 'dart:convert';

import '../../core/error_codes.dart';
import '../local/json_store.dart';

/// `index/*.json` 하나에 리스트로 저장되는 엔티티들의 공통 구현.
///
/// 왜 제네릭 베이스를 두나: 전집·플레이리스트·아이·목소리 프로필은 저장 방식이 완전히
/// 같다(파일 하나에 리스트, id 로 업서트/삭제). 4~5번 복사하면 한 곳만 고치고 나머지를
/// 빼먹는 실수가 생긴다.
///
/// 왜 콘텐츠는 이걸 안 쓰나: 콘텐츠는 파일을 개별로 나눠 손상 범위를 가둔다
/// ([ContentRepositoryImpl] 참조). 인덱스 항목들은 작아서 한 파일로 충분하다.
abstract class IndexRepositoryBase<T> implements PendingWrites {
  IndexRepositoryBase(this.store, this.filePath);

  final JsonStore store;
  Future<void> _pending = Future.value();
  @override
  Future<void> waitForWrites() => _pending;

  Future<void> _enqueue(Future<void> Function() action) => store.gate.write(() {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object _) {});
    return result;
  });

  /// `index/xxx.json`
  final String filePath;

  /// JSON → 엔티티.
  T fromJson(Map<String, Object?> json);

  /// 엔티티 → JSON.
  Map<String, Object?> toJson(T item);

  /// 업서트·삭제의 기준이 되는 식별자.
  String idOf(T item);

  /// 정렬 기준. `null` 이면 저장 순서를 유지한다.
  int Function(T a, T b)? get comparator => null;

  Future<List<T>> getAll() async {
    final rows = await store.readList(filePath);
    final out = rows.map(fromJson).toList();
    final cmp = comparator;
    if (cmp != null) out.sort(cmp);
    return out;
  }

  Future<T?> getById(String id) async {
    final all = await getAll();
    for (final item in all) {
      if (idOf(item) == id) return item;
    }
    return null;
  }

  /// 같은 id 가 있으면 교체, 없으면 추가.
  Future<void> save(T item) {
    final snapshot = fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(toJson(item))) as Map),
    );
    return _enqueue(() => _save(snapshot));
  }

  Future<void> _save(T item) async {
    // FLOW 1: 검증 — id 없는 항목은 업서트 대상을 특정할 수 없다
    if (idOf(item).isEmpty) {
      throw const AppException(ErrorCode.badRequest, detail: 'id 가 비었다');
    }
    // FLOW 2: 현재 목록을 읽어 교체 또는 추가
    final all = await getAll();
    final id = idOf(item);
    final index = all.indexWhere((e) => idOf(e) == id);
    if (index >= 0) {
      all[index] = item;
    } else {
      all.add(item);
    }
    // FLOW 9: 전량 원자적 저장
    await store.writeList(filePath, all.map(toJson).toList());
  }

  Future<void> delete(String id) => _enqueue(() => _delete(id));

  Future<void> _delete(String id) async {
    final all = await getAll();
    final remained = all.where((e) => idOf(e) != id).toList();
    // 변경이 없으면 파일을 다시 쓰지 않는다 — 불필요한 IO 를 줄인다.
    if (remained.length == all.length) return;
    await store.writeList(filePath, remained.map(toJson).toList());
  }
}

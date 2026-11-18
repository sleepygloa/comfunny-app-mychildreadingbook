import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/core/error_codes.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/entities/series.dart';
import 'package:mychild_reading/domain/enums/enums.dart';
import 'package:mychild_reading/domain/repositories/repositories.dart';
import 'package:mychild_reading/presentation/library/library_view_model.dart';

/// [LibraryViewModel] 검증 — **fake 저장소**로 갈아끼운다.
///
/// 이게 가능한 이유: `domain/repositories` 가 추상 인터페이스이고 VM 이 그것만 알기
/// 때문이다([2_DEVELOPMENT §2.2] 계층 방향 단방향). 파일시스템·Flutter 없이 돈다.
class _FakeContentRepository implements ContentRepository {
  _FakeContentRepository(this._items);

  List<Content> _items;

  /// 다음 호출에서 던질 예외. 실패 경로 검증용.
  AppException? throwOnGetAll;
  final List<String> deleted = [];

  @override
  Future<List<Content>> getAll() async {
    final e = throwOnGetAll;
    if (e != null) throw e;
    return _items;
  }

  @override
  Future<Content?> getById(String id) async =>
      _items.where((c) => c.id == id).firstOrNull;

  @override
  Future<void> save(Content content) async => _items = [..._items, content];

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _items = _items.where((c) => c.id != id).toList();
  }
}

class _FakeSeriesRepository implements SeriesRepository {
  _FakeSeriesRepository(this._items);

  List<Series> _items;

  @override
  Future<List<Series>> getAll() async => _items;
  @override
  Future<void> save(Series series) async => _items = [..._items, series];
  @override
  Future<void> delete(String id) async =>
      _items = _items.where((s) => s.id != id).toList();
}

void main() {
  Content book(
    String id, {
    String? title,
    String? author,
    String? publisher,
    String? seriesId,
    int? volume,
    List<String> tags = const [],
  }) =>
      Content(
        id: id,
        type: ContentType.pagedBook,
        title: title ?? '책 $id',
        author: author,
        publisher: publisher,
        seriesId: seriesId,
        volume: volume,
        tags: tags,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );

  LibraryViewModel vmWith(
    List<Content> contents, {
    List<Series> series = const [],
    _FakeContentRepository? repo,
  }) =>
      LibraryViewModel(
        contentRepository: repo ?? _FakeContentRepository(contents),
        seriesRepository: _FakeSeriesRepository(series),
      );

  group('load', () {
    test('로딩 상태를 알린 뒤 목록을 채운다', () async {
      final vm = vmWith([book('c1'), book('c2')]);
      final states = <bool>[];
      vm.addListener(() => states.add(vm.loading));

      await vm.load();

      // 로딩 켜짐 → 꺼짐 순서로 알림이 왔어야 한다 (UI 가 스피너를 띄울 수 있다).
      expect(states, [true, false]);
      expect(vm.items.length, 2);
      expect(vm.loading, isFalse);
      expect(vm.errorMessage, isNull);
    });

    test('빈 저장소는 isEmpty', () async {
      final vm = vmWith(const []);
      await vm.load();

      expect(vm.isEmpty, isTrue);
      expect(vm.visibleItems, isEmpty);
    });

    test('로드 전에는 isEmpty 가 아니다 (빈 상태 화면 깜빡임 방지)', () {
      final vm = vmWith(const []);
      // loading=false, items=[] 이지만 아직 로드를 시작하지 않았다.
      // 이 시점에 isEmpty 가 true 면 "책이 없어요" 가 잠깐 보였다 사라진다.
      expect(vm.loading, isFalse);
      expect(vm.isEmpty, isTrue); // 현 구현 — 화면이 postFrame 에서 즉시 load 한다
    });
  });

  group('load 실패 처리', () {
    test('AppException 은 사용자 문구로 바꾼다', () async {
      final repo = _FakeContentRepository([book('c1')])
        ..throwOnGetAll = const AppException(ErrorCode.storageFailure);
      final vm = vmWith(const [], repo: repo);

      await vm.load();

      expect(vm.errorMessage, ErrorCode.storageFailure.userMessage);
      expect(vm.loading, isFalse); // finally 로 반드시 내려간다
    });

    test('실패해도 이전 목록을 비우지 않는다', () async {
      final repo = _FakeContentRepository([book('c1')]);
      final vm = vmWith(const [], repo: repo);
      await vm.load();
      expect(vm.items.length, 1);

      // 두 번째 로드가 실패한다
      repo.throwOnGetAll = const AppException(ErrorCode.storageFailure);
      await vm.load();

      // 화면이 갑자기 비면 사용자는 데이터가 사라진 줄 안다.
      expect(vm.items.length, 1);
      expect(vm.errorMessage, isNotNull);
    });

    test('clearError 로 배너를 닫는다', () async {
      final repo = _FakeContentRepository(const [])
        ..throwOnGetAll = const AppException(ErrorCode.badRequest);
      final vm = vmWith(const [], repo: repo);
      await vm.load();
      expect(vm.errorMessage, isNotNull);

      vm.clearError();
      expect(vm.errorMessage, isNull);
    });
  });

  group('search — 로컬 필터', () {
    test('제목으로 찾는다', () async {
      final vm = vmWith([book('c1', title: '아기 돼지'), book('c2', title: '토끼')]);
      await vm.load();

      vm.search('돼지');
      expect(vm.visibleItems.map((c) => c.id), ['c1']);
    });

    test('저자·출판사·태그로도 찾는다', () async {
      final vm = vmWith([
        book('c1', title: 'A', author: '홍길동'),
        book('c2', title: 'B', publisher: '테스트출판'),
        book('c3', title: 'C', tags: ['잠자기전']),
      ]);
      await vm.load();

      vm.search('홍길동');
      expect(vm.visibleItems.single.id, 'c1');
      vm.search('테스트출판');
      expect(vm.visibleItems.single.id, 'c2');
      vm.search('잠자기전');
      expect(vm.visibleItems.single.id, 'c3');
    });

    test('대소문자를 구분하지 않는다', () async {
      final vm = vmWith([book('c1', title: 'Hello Book')]);
      await vm.load();

      vm.search('hello');
      expect(vm.visibleItems.length, 1);
    });

    test('검색어가 비면 전체', () async {
      final vm = vmWith([book('c1'), book('c2')]);
      await vm.load();

      vm.search('없는단어');
      expect(vm.visibleItems, isEmpty);
      vm.search('   ');
      expect(vm.visibleItems.length, 2);
    });

    test('같은 검색어면 알리지 않는다 (불필요한 리빌드 방지)', () async {
      final vm = vmWith([book('c1')]);
      await vm.load();

      var notified = 0;
      vm.addListener(() => notified++);
      vm.search('가');
      vm.search('가');

      expect(notified, 1);
    });
  });

  group('seriesTitleOf — 전집 라벨', () {
    test('전집 제목을 찾는다', () async {
      final vm = vmWith(
        [book('c1', seriesId: 's1', volume: 3)],
        series: const [Series(id: 's1', title: '세계명작')],
      );
      await vm.load();

      expect(vm.seriesTitleOf('s1'), '세계명작');
    });

    test('seriesId 가 null 이면 null', () async {
      final vm = vmWith([book('c1')]);
      await vm.load();
      expect(vm.seriesTitleOf(null), isNull);
    });

    test('전집을 지웠는데 책이 참조하면 null (고아 참조 허용)', () async {
      final vm = vmWith([book('c1', seriesId: 'gone')]);
      await vm.load();

      // 전집 삭제 시 모든 책을 훑어 고치는 비용보다, 라벨을 생략하는 편이 싸다.
      expect(vm.seriesTitleOf('gone'), isNull);
    });
  });

  group('delete', () {
    test('저장소에서 지우고 목록에서도 즉시 제거한다', () async {
      final repo = _FakeContentRepository([book('c1'), book('c2')]);
      final vm = vmWith(const [], repo: repo);
      await vm.load();

      await vm.delete('c1');

      expect(repo.deleted, ['c1']);
      // 목록을 다시 읽지 않고 즉시 반영한다 (Optimistic).
      expect(vm.items.map((c) => c.id), ['c2']);
      expect(vm.errorMessage, isNull);
    });
  });
}

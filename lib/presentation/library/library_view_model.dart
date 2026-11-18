import 'package:flutter/foundation.dart';

import '../../core/app_logger.dart';
import '../../core/error_codes.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/series.dart';
import '../../domain/repositories/repositories.dart';

/// 책장 화면의 상태. `[B-02]` `[현행]` = **provider `ChangeNotifier`**.
///
/// 규약 ([2_DEVELOPMENT §2.4]):
/// - 화면당 ViewModel 하나
/// - `build()` 안에서 상태를 바꾸지 않는다
/// - 스트림·타이머는 `dispose()` 에서 해제한다 (이 VM 은 없다)
class LibraryViewModel extends ChangeNotifier {
  LibraryViewModel({
    required ContentRepository contentRepository,
    required SeriesRepository seriesRepository,
  }) : _contents = contentRepository,
       _series = seriesRepository;

  final ContentRepository _contents;
  final SeriesRepository _series;

  List<Content> _items = const [];
  List<Series> _seriesList = const [];
  bool _loading = false;
  String? _errorMessage;
  String _query = '';

  /// 저장소가 돌려준 원본 목록 (최근 갱신순).
  List<Content> get items => _items;

  /// 전집 목록. 그룹핑 라벨에 쓴다.
  List<Series> get seriesList => _seriesList;

  bool get loading => _loading;

  /// 사용자에게 보여줄 오류. `null` 이면 정상.
  String? get errorMessage => _errorMessage;

  String get query => _query;

  /// 검색어를 적용한 목록. **검색은 로컬 필터다** — 네트워크가 없다.
  List<Content> get visibleItems {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((c) {
      return c.title.toLowerCase().contains(q) ||
          (c.author ?? '').toLowerCase().contains(q) ||
          (c.publisher ?? '').toLowerCase().contains(q) ||
          c.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  bool get isEmpty => !_loading && _items.isEmpty;

  /// 전집 id → 제목. 없는 전집을 참조하는 책도 있을 수 있어 `null` 을 허용한다.
  String? seriesTitleOf(String? seriesId) {
    if (seriesId == null) return null;
    for (final s in _seriesList) {
      if (s.id == seriesId) return s.title;
    }
    // 전집을 지웠는데 책이 아직 참조하는 경우. 고아 참조를 허용하는 설계다.
    return null;
  }

  /// 책장을 불러온다. 화면 진입·되돌아옴·당겨서 새로고침에서 호출한다.
  Future<void> load() async {
    // FLOW 1: 로딩 상태를 먼저 알린다 — UI 가 즉시 스피너를 띄운다
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // FLOW 2: 로컬 조회 (네트워크 없음). 전집은 라벨용이라 함께 읽는다
      _items = await _contents.getAll();
      _seriesList = await _series.getAll();
    } on AppException catch (e) {
      // FLOW 3: 알려진 실패는 사용자 문구로 바꾼다
      _errorMessage = e.errorCode.userMessage;
      AppLogger.w('책장 로드 실패: $e');
    } on Object catch (e, st) {
      // FLOW 4: 예상 못 한 실패도 화면을 비우지 않는다 — 이전 목록을 유지한다
      _errorMessage = ErrorCode.storageFailure.userMessage;
      AppLogger.e('책장 로드 중 예외', error: e, stackTrace: st);
    } finally {
      // FLOW 9: 성공·실패 모두 로딩을 내린다
      _loading = false;
      notifyListeners();
    }
  }

  void search(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  /// 책을 지운다. 미디어 파일까지 함께 사라진다.
  Future<void> delete(String contentId) async {
    try {
      await _contents.delete(contentId);
      // 목록을 다시 읽지 않고 로컬에서 제거한다 — 즉시 반영(Optimistic).
      _items = _items.where((c) => c.id != contentId).toList();
      _errorMessage = null;
    } on AppException catch (e) {
      _errorMessage = e.errorCode.userMessage;
      AppLogger.w('삭제 실패: $e');
    }
    notifyListeners();
  }

  /// 오류 배너를 닫는다.
  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}

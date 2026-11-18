import '../entities/book_draft.dart';
import '../entities/reading_position.dart';

/// 공개된 책과 독립된 제작 저장소. 삭제해도 완성본은 유지한다.
abstract class BookDraftRepository {
  Future<List<BookDraft>> getAll();
  Future<BookDraft?> getById(String contentId);
  Future<void> save(BookDraft draft);
  Future<void> delete(String contentId);
}

/// 책별 마지막 위치. 아이 프로필별 위치는 다자녀 단계에서 확장한다.
abstract class ReadingPositionRepository {
  Future<ReadingPosition?> getById(String contentId);
  Future<void> save(ReadingPosition position);
  Future<void> delete(String contentId);
}

import '../entities/book_draft.dart';
import '../entities/content.dart';

/// 미디어 복제와 초안/완성본 전환을 하나의 제작 경계로 묶는다.
abstract class BookAuthoringRepository {
  Future<BookDraft> create(String title);
  Future<BookDraft> open(String contentId);
  Future<void> save(BookDraft draft);
  Future<String> importMedia(
    String contentId,
    String sourcePath,
    String extension,
  );
  Future<Content> publish(BookDraft draft);
  Future<void> discard(String contentId);
}

/// 기존 편집이 일어난 책을 오래된 초안으로 덮지 않도록 조건부 교체한다.
abstract class ContentRevisionRepository {
  Future<void> saveRevision(
    Content content, {
    required DateTime? expectedUpdatedAt,
  });
}

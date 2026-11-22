import 'package:flutter_test/flutter_test.dart';
import 'package:mychild_reading/domain/entities/book_tags.dart';
import 'package:mychild_reading/domain/entities/topic.dart';
import 'package:mychild_reading/domain/entities/content.dart';
import 'package:mychild_reading/domain/enums/enums.dart';

/// 합성 데이터만 쓴다. 실제 책 · 아이 정보 없음.
void main() {
  group('Topic', () {
    test('round-trip 은 값을 그대로 돌려준다', () {
      const t = Topic(
        id: 'science-environment-air',
        name: '대기오염',
        parentId: 'science-environment',
        emoji: '🌫️',
        order: 2,
      );
      final back = Topic.fromJson(t.toJson());
      expect(back.toJson(), t.toJson());
      expect(back.isRoot, isFalse);
    });
    test('없는 필드 · 다른 타입은 기본값으로 읽는다', () {
      final t = Topic.fromJson({
        'id': 'x',
        'name': 3,
        'order': 'a',
        'extra': 1,
      });
      expect(t.name, '');
      expect(t.order, 0);
      expect(t.parentId, isNull);
    });
    test('기본 사전은 id 가 겹치지 않고 부모가 모두 사전 안에 있다', () {
      final ids = Topic.defaults.map((t) => t.id).toSet();
      expect(ids.length, Topic.defaults.length);
      for (final t in Topic.defaults) {
        expect(t.parentId == null || ids.contains(t.parentId), isTrue);
        // 백업 검사(RestoreValidator)의 id 규칙과 같아야 복원이 거절되지 않는다.
        expect(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(t.id), isTrue);
      }
    });
  });

  group('BookTags', () {
    test('round-trip 은 값을 그대로 돌려준다', () {
      const tags = BookTags(
        contentId: 'book-1',
        topicIds: ['science', 'science-space'],
        favorite: true,
        ageMin: 5,
        ageMax: 7,
        nuriAreas: [NuriArea.communication, NuriArea.nature],
      );
      final back = BookTags.fromJson(tags.toJson());
      expect(back.toJson(), tags.toJson());
      expect(back.nuriAreas, [NuriArea.communication, NuriArea.nature]);
    });
    test('모르는 누리과정 영역 · 잘못된 나이 · 중복 주제는 걸러 읽는다', () {
      final t = BookTags.fromJson({
        'id': 'b',
        'topicIds': ['a', 'a', 3],
        'ageMin': 8,
        'ageMax': 4,
        'nuriAreas': ['nature', 'future-area'],
        'favorite': 'yes',
      });
      expect(t.topicIds, ['a']);
      expect((t.ageMin, t.ageMax), (4, 8));
      expect(t.nuriAreas, [NuriArea.nature]);
      expect(t.favorite, isFalse);
      expect(BookTags.fromJson({'id': 'b', 'ageMin': 99}).ageMin, isNull);
    });
    test('나이를 정하지 않은 책은 어느 나이 모아보기에도 들어가지 않는다', () {
      expect(const BookTags(contentId: 'b').fitsAge(7), isFalse);
      const t = BookTags(contentId: 'b', ageMin: 5, ageMax: 7);
      expect([4, 5, 7, 8].map(t.fitsAge), [false, true, true, false]);
      expect(t.ageLabel, '5~7세');
      expect(
        const BookTags(contentId: 'b', ageMin: 6, ageMax: 6).ageLabel,
        '6세',
      );
    });
    test('꼬리표가 없으면 비어 있다', () {
      expect(const BookTags(contentId: 'b').isEmpty, isTrue);
      expect(const BookTags(contentId: 'b', favorite: true).isEmpty, isFalse);
    });
  });

  test('음원(audio) 종류는 round-trip 되고 아직 재생할 수 없다', () {
    final song = Content(
      id: 'song',
      type: ContentType.audio,
      title: '합성 동요',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final back = Content.fromJson(song.toJson());
    expect(back.type, ContentType.audio);
    expect(back.isAudio, isTrue);
    expect(back.isPlayable, isFalse);
  });
}

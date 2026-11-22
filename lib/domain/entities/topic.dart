import '../../core/json_codec.dart';

/// 책 주제 사전의 한 칸. 예: 과학 › 환경 › 대기오염. id 는 백업 검사 규칙상 영문·숫자·`-`·`_` 만 쓴다. `index/topics.json` 에 저장된다.
///
/// 왜 책 안에 이름을 직접 적지 않고 사전을 두나: "환경"을 "자연·환경"으로 바꾸면
/// 그 주제가 붙은 모든 책이 한 번에 바뀌어야 한다. 책은 [id] 만 참조한다(left join).
/// 왜 [parentId] 한 칸만 두나: 3단(대·중·소)까지는 부모를 따라 올라가면 충분하다.
class Topic {
  const Topic({
    required this.id,
    required this.name,
    this.parentId,
    this.emoji = '',
    this.order = 0,
  });

  final String id;
  final String name;
  final String? parentId;

  /// 아이가 글자 대신 알아보는 그림 하나. 비어 있으면 화면이 기본 아이콘을 쓴다.
  final String emoji;

  /// 같은 부모 안에서의 순서. 작을수록 앞.
  final int order;

  bool get isRoot => parentId == null;

  Topic copyWith({String? name, String? emoji, int? order}) => Topic(
    id: id,
    name: name ?? this.name,
    parentId: parentId,
    emoji: emoji ?? this.emoji,
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => compactMap({
    'id': id,
    'name': name,
    'parentId': parentId,
    'emoji': emoji,
    'order': order,
  });

  factory Topic.fromJson(Map<String, Object?> json) => Topic(
    id: asString(json['id']),
    name: asString(json['name']),
    parentId: asStringOrNull(json['parentId']),
    emoji: asString(json['emoji']),
    order: asInt(json['order']),
  );

  /// 처음 설치했을 때 보이는 기본 사전. 부모가 더하거나 이름을 바꿀 수 있다.
  ///
  /// 왜 코드에 두나: 빈 사전으로 시작하면 "주제 정하기"를 처음 연 보호자가 무엇을 넣을지 모른다.
  /// 파일에는 보호자가 처음 주제를 저장할 때 함께 기록된다(그 전에는 파일이 없다).
  static const defaults = <Topic>[
    Topic(id: 'science', name: '과학', emoji: '🔬', order: 0),
    Topic(
      id: 'science-nature',
      name: '자연',
      parentId: 'science',
      emoji: '🌳',
      order: 0,
    ),
    Topic(
      id: 'science-environment',
      name: '환경',
      parentId: 'science',
      emoji: '🌍',
      order: 1,
    ),
    Topic(
      id: 'science-environment-air',
      name: '대기오염',
      parentId: 'science-environment',
      emoji: '🌫️',
      order: 0,
    ),
    Topic(
      id: 'science-space',
      name: '우주',
      parentId: 'science',
      emoji: '🚀',
      order: 2,
    ),
    Topic(
      id: 'science-animals',
      name: '동물',
      parentId: 'science',
      emoji: '🐻',
      order: 3,
    ),
    Topic(id: 'life', name: '생활', emoji: '🏠', order: 1),
    Topic(
      id: 'life-habits',
      name: '생활습관',
      parentId: 'life',
      emoji: '🪥',
      order: 0,
    ),
    Topic(
      id: 'life-safety',
      name: '안전',
      parentId: 'life',
      emoji: '🚸',
      order: 1,
    ),
    Topic(id: 'feelings', name: '마음', emoji: '💛', order: 2),
    Topic(
      id: 'feelings-friends',
      name: '친구',
      parentId: 'feelings',
      emoji: '🤝',
      order: 0,
    ),
    Topic(
      id: 'feelings-family',
      name: '가족',
      parentId: 'feelings',
      emoji: '👨‍👩‍👧',
      order: 1,
    ),
    Topic(id: 'story', name: '옛이야기', emoji: '🏯', order: 3),
    Topic(id: 'math', name: '수학', emoji: '🔢', order: 4),
  ];
}

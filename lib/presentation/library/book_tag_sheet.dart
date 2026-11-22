import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/book_tags.dart';
import '../../domain/entities/content.dart';
import '../../domain/entities/topic.dart';
import 'catalog_view_model.dart';

/// 책 한 권의 주제 · 나이 · 누리과정 · 즐겨찾기를 고르는 시트.
///
/// 왜 저장 버튼을 두나: 칩을 누를 때마다 저장하면 파일을 여러 번 다시 쓰고,
/// 잘못 누른 것을 되돌릴 방법이 없다. 다 고른 뒤 한 번 저장한다.
Future<void> showBookTagSheet(BuildContext context, Content book) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<CatalogViewModel>(),
        child: BookTagSheet(book: book),
      ),
    );

class BookTagSheet extends StatefulWidget {
  const BookTagSheet({super.key, required this.book});
  final Content book;
  @override
  State<BookTagSheet> createState() => _BookTagSheetState();
}

class _BookTagSheetState extends State<BookTagSheet> {
  late BookTags tags = context.read<CatalogViewModel>().tagsOf(widget.book);
  late bool hasAge = tags.ageMin != null || tags.ageMax != null;
  late RangeValues ages = RangeValues(
    (tags.ageMin ?? 5).toDouble(),
    (tags.ageMax ?? tags.ageMin ?? 7).toDouble(),
  );

  void _toggleTopic(String id) => setState(() {
    final ids = [...tags.topicIds];
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    tags = tags.copyWith(topicIds: ids);
  });

  void _toggleArea(NuriArea area) => setState(() {
    final areas = [...tags.nuriAreas];
    areas.contains(area) ? areas.remove(area) : areas.add(area);
    tags = tags.copyWith(
      nuriAreas: [
        for (final a in NuriArea.values)
          if (areas.contains(a)) a,
      ],
    );
  });

  Future<void> _addTopic(CatalogViewModel c) async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => _NewTopicDialog(roots: c.rootTopics),
    );
    if (result == null || !mounted) return;
    final topic = await c.addTopic(result.$1, parentId: result.$2);
    if (topic != null && mounted) _toggleTopic(topic.id);
  }

  Future<void> _save(CatalogViewModel c) async {
    final saved = tags.copyWith(
      ageMin: () => hasAge ? ages.start.round() : null,
      ageMax: () => hasAge ? ages.end.round() : null,
    );
    await c.saveTags(saved);
    if (mounted && c.error == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CatalogViewModel>();
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Column(
          children: [
            ListTile(
              title: Text(widget.book.title, style: theme.textTheme.titleLarge),
              subtitle: const Text('주제 · 나이 · 누리과정 정하기'),
              trailing: FilledButton(
                onPressed: c.isBusy ? null : () => _save(c),
                child: const Text('저장'),
              ),
            ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(c.error!),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(
                      tags.favorite ? Icons.star : Icons.star_border,
                      color: const Color(0xFFF2B33D),
                    ),
                    title: const Text('즐겨찾기'),
                    value: tags.favorite,
                    onChanged: (v) =>
                        setState(() => tags = tags.copyWith(favorite: v)),
                  ),
                  const Divider(),
                  Text('주제', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final root in c.rootTopics) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final t in [root, ...c.descendantsOf(root.id)])
                          FilterChip(
                            label: Text(
                              '${t.emoji.isEmpty ? '' : '${t.emoji} '}${c.topicLabel(t.id)}',
                            ),
                            selected: tags.topicIds.contains(t.id),
                            onSelected: (_) => _toggleTopic(t.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: c.isBusy ? null : () => _addTopic(c),
                      icon: const Icon(Icons.add),
                      label: const Text('주제 추가'),
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('권장 나이', style: theme.textTheme.titleMedium),
                    subtitle: Text(
                      hasAge
                          ? '${ages.start.round()}~${ages.end.round()}세'
                          : '정하지 않으면 나이별 모아보기에 나오지 않아요.',
                    ),
                    value: hasAge,
                    onChanged: (v) => setState(() => hasAge = v),
                  ),
                  if (hasAge)
                    RangeSlider(
                      min: 1,
                      max: 10,
                      divisions: 9,
                      values: ages,
                      labels: RangeLabels(
                        '${ages.start.round()}세',
                        '${ages.end.round()}세',
                      ),
                      onChanged: (v) => setState(() => ages = v),
                    ),
                  const Divider(),
                  Text('누리과정 영역', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final area in NuriArea.values)
                        FilterChip(
                          label: Text('${area.emoji} ${area.label}'),
                          selected: tags.nuriAreas.contains(area),
                          onSelected: (_) => _toggleArea(area),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewTopicDialog extends StatefulWidget {
  const _NewTopicDialog({required this.roots});
  final List<Topic> roots;
  @override
  State<_NewTopicDialog> createState() => _NewTopicDialogState();
}

class _NewTopicDialogState extends State<_NewTopicDialog> {
  final _name = TextEditingController();
  String? _parent;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('주제 추가'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(labelText: '이름 (예: 대기오염)'),
        ),
        DropdownButtonFormField<String?>(
          initialValue: _parent,
          decoration: const InputDecoration(labelText: '어디 아래에 둘까요'),
          items: [
            const DropdownMenuItem(value: null, child: Text('맨 위 (새 큰 주제)')),
            for (final r in widget.roots)
              DropdownMenuItem(
                value: r.id,
                child: Text('${r.emoji} ${r.name}'),
              ),
          ],
          onChanged: (v) => setState(() => _parent = v),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          if (name.isNotEmpty) Navigator.pop(context, (name, _parent));
        },
        child: const Text('추가'),
      ),
    ],
  );
}

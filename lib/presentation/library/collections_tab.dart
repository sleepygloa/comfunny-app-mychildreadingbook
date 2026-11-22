import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/library_shell.dart';
import '../player/floating_player.dart';
import 'catalog_view_model.dart';

/// 모아보기 탭 — 꼬리표로 저절로 만들어지는 목록(즐겨찾기 · 주제 · 나이 · 누리과정).
///
/// 왜 저장하지 않나: 플레이리스트는 보호자가 손으로 고른 순서가 있지만, 모아보기는
/// "과학 주제가 붙은 책 전부"처럼 조건이다. 저장하면 책에 주제를 붙일 때마다 목록도
/// 고쳐야 하고 둘이 어긋난다. 그래서 열 때마다 꼬리표에서 다시 계산한다.
class CollectionsTab extends StatelessWidget {
  const CollectionsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<CatalogViewModel>();
    final groups = c.collections;
    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 16),
              child: Column(
                children: [
                  Text('🗂️', style: TextStyle(fontSize: 56)),
                  SizedBox(height: 20),
                  Text(
                    '아직 모아볼 책이 없어요',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 12),
                  Text(
                    '책 메뉴의 "주제 · 나이 정하기"나 표지의 별을 누르면\n여기에 저절로 모여요.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          for (final section in CollectionKind.values)
            if (groups.any((g) => g.kind == section)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(
                  section.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final g in groups.where((g) => g.kind == section))
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Text(
                      g.emoji,
                      style: const TextStyle(fontSize: 34),
                    ),
                    title: Text(g.title),
                    subtitle: Text('${g.books.length}권'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => CollectionDetail(id: g.id),
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: '${g.title} 전체 재생',
                      icon: const Icon(Icons.play_circle_outline),
                      onPressed: () => playBooks(context, g.books),
                    ),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}

/// 모아보기 하나를 연 화면. 꼬리표가 바뀌면 바로 다시 계산된다.
class CollectionDetail extends StatelessWidget {
  const CollectionDetail({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<CatalogViewModel>();
    final g = c.collections.where((g) => g.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(g == null ? '모아보기' : '${g.emoji} ${g.title}')),
      body: g == null
          ? const Center(child: Text('이 모아보기에 남은 책이 없어요.'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: () => playBooks(context, g.books),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('전체 재생 (${g.books.length}권)'),
                  ),
                ),
                const SizedBox(height: 12),
                for (final book in g.books) BookRow(book: book),
              ],
            ),
      bottomNavigationBar: const FloatingPlayer(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/repositories/book_authoring_repository.dart';
import '../../service_locator.dart';
import 'catalog_view_model.dart';

/// 책장 메뉴에서 여는 초안 목록. 책 관리는 책장 항목 메뉴에 모은다.
class ParentLibraryScreen extends StatelessWidget {
  const ParentLibraryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<CatalogViewModel>();
    return Scaffold(
      appBar: AppBar(title: const Text('만들던 책')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (c.error != null) Text(c.error!),
          if (c.draftList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('저장한 초안이 없어요. 책장 + 버튼에서 새 책을 만들어 주세요.'),
            ),
          for (final draft in c.draftList)
            Card(
              child: ListTile(
                title: Text(
                  draft.content.title.isEmpty ? '제목 없는 책' : draft.content.title,
                ),
                subtitle: Text('${draft.content.pageCount}쪽 · 이어 만들기'),
                onTap: () async {
                  await context.push('/content/${draft.id}/edit');
                  await c.load();
                },
                trailing: IconButton(
                  tooltip: '초안 삭제',
                  onPressed: c.isBusy
                      ? null
                      : () async {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('초안을 버릴까요?'),
                              content: const Text(
                                '초안 사진과 녹음이 삭제돼요. 책장의 완성된 책은 유지돼요.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('취소'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('버리기'),
                                ),
                              ],
                            ),
                          );
                          if (yes == true) {
                            await c.mutate(
                              () => sl<BookAuthoringRepository>().discard(
                                draft.id,
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

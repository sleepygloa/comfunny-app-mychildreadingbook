import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'playback_queue.dart';

/// 최근재생목록 탭과 플로팅 확장 화면이 같은 목록·명령을 사용한다.
class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key, this.expandedPlayer = false});
  final bool expandedPlayer;
  @override
  Widget build(BuildContext context) {
    final q = context.watch<PlaybackQueue>();
    return Column(
      children: [
        if (q.isBusy) const LinearProgressIndicator(),
        if (q.error != null || q.player?.errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(q.error ?? q.player!.errorMessage!),
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            buildDefaultDragHandles: false,
            itemCount: q.items.length,
            onReorderItem: q.reorder,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (expandedPlayer) ...[
                  Text(
                    q.player?.content.title ?? '함께 듣는 이야기',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const PlaybackControls(),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${q.items.length}권 · 최근재생목록',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: q.isBusy || q.items.isEmpty
                          ? null
                          : () async {
                              final yes = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('최근재생목록을 비울까요?'),
                                  content: const Text(
                                    '재생이 멈춰요. 책과 저장한 플레이리스트는 그대로 남아요.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('취소'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('비우기'),
                                    ),
                                  ],
                                ),
                              );
                              if (yes == true) await q.clear();
                            },
                      child: const Text('비우기'),
                    ),
                  ],
                ),
                const Text('마지막으로 담은 재생 순서예요. 손잡이를 끌어 바꿀 수 있어요.'),
                if (q.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text('책장이나 플레이리스트에서 듣고 싶은 책을 재생해 보세요.'),
                  ),
                const SizedBox(height: 12),
              ],
            ),
            itemBuilder: (context, i) {
              final book = q.items[i];
              return Card(
                key: ValueKey(book.id),
                color: q.currentId == book.id
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null,
                child: ListTile(
                  leading: ReorderableDragStartListener(
                    index: i,
                    enabled: !q.isBusy,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                  title: Text(book.title),
                  subtitle: Text(
                    q.currentId == book.id
                        ? '지금 듣는 책 · ${book.pageCount}쪽'
                        : '${book.pageCount}쪽',
                  ),
                  onTap: q.isBusy || !q.canPlay
                      ? null
                      : () => q.select(book.id),
                  trailing: IconButton(
                    tooltip: '${book.title} 최근재생목록에서 제거',
                    onPressed: q.isBusy ? null : () => q.remove(book.id),
                    icon: const Icon(Icons.close),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({super.key});
  @override
  Widget build(BuildContext context) {
    final q = context.watch<PlaybackQueue>();
    final p = q.player;
    final enabled = !q.isBusy && q.canPlay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p != null)
          Text(
            '${p.index + 1} / ${p.pageCount}쪽 · ${p.isPlaying ? '듣는 중' : '일시정지'}',
          ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: '이전 책',
              onPressed: enabled && q.currentIndex > 0 ? q.previousBook : null,
              icon: const Icon(Icons.skip_previous),
            ),
            FilledButton.icon(
              onPressed: enabled && q.items.isNotEmpty ? q.toggle : null,
              icon: Icon(p?.isPlaying == true ? Icons.pause : Icons.play_arrow),
              label: Text(p?.isPlaying == true ? '일시정지' : '재생'),
            ),
            IconButton(
              tooltip: '다음 책',
              onPressed:
                  enabled &&
                      q.currentIndex >= 0 &&
                      q.currentIndex + 1 < q.items.length
                  ? q.nextBook
                  : null,
              icon: const Icon(Icons.skip_next),
            ),
            IconButton(
              tooltip: '재생 종료',
              onPressed: q.isBusy || p == null ? null : q.stop,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
            TextButton(
              onPressed: p == null
                  ? null
                  : () {
                      // 모달을 닫고 같은 플레이어가 제공하는 독서 화면을 연다.
                      final router = GoRouter.of(context);
                      if (ModalRoute.of(context) is ModalBottomSheetRoute) {
                        Navigator.pop(context);
                      }
                      router.push('/reader');
                    },
              child: const Text('책 펼치기'),
            ),
          ],
        ),
      ],
    );
  }
}

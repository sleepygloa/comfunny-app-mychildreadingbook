import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'playback_queue.dart';
import 'queue_panel.dart';

/// 탭/플레이리스트 상세에서 같은 큐를 제어하는 플로팅 카드.
class FloatingPlayer extends StatelessWidget {
  const FloatingPlayer({super.key});
  @override
  Widget build(BuildContext context) {
    final q = context.watch<PlaybackQueue>();
    if (q.items.isEmpty) return const SizedBox.shrink();
    final p = q.player;
    void expand() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ChangeNotifierProvider.value(
          value: q,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: const QueuePanel(expandedPlayer: true),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Material(
          elevation: 5,
          shadowColor: Theme.of(context).colorScheme.primary
              .withValues(alpha: .2),
          borderRadius: BorderRadius.circular(26),
          color: Theme.of(context).colorScheme.primaryContainer,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: expand,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_stories, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p?.content.title ?? '이야기 ${q.items.length}권',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          p == null
                              ? '눌러서 이어 듣기'
                              : '${p.index + 1} / ${p.pageCount}쪽 · ${p.isPlaying ? '듣는 중' : '일시정지'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: p?.isPlaying == true ? '일시정지' : '재생',
                    onPressed: q.isBusy || !q.canPlay ? null : q.toggle,
                    icon: Icon(
                      p?.isPlaying == true
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: '플로팅 플레이어 펼치기',
                    onPressed: expand,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

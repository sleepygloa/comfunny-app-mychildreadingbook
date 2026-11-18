import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'playback_queue.dart';
import 'player_screen.dart';
import 'player_view_model.dart';
import 'queue_panel.dart';
import 'floating_player.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('최근재생목록')),
    body: const SafeArea(child: QueuePanel()),
    bottomNavigationBar: const FloatingPlayer(),
  );
}

class QueueReader extends StatelessWidget {
  const QueueReader({super.key});
  @override
  Widget build(BuildContext context) {
    final q = context.watch<PlaybackQueue>();
    final p = q.player;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('책 읽기')),
        body: const Center(child: Text('최근재생목록에서 책을 선택해 주세요.')),
      );
    }
    return ChangeNotifierProvider<PlayerViewModel>.value(
      value: p,
      child: PlayerScreen(key: ValueKey(p), managedByQueue: true),
    );
  }
}

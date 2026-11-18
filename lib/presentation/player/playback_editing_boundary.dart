import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'playback_queue.dart';

/// 편집 중에는 알림/헤드셋에서도 재생을 시작하지 않아 녹음과 소리가 겹치지 않는다.
class PlaybackEditingBoundary extends StatefulWidget {
  const PlaybackEditingBoundary({super.key, required this.child});
  final Widget child;
  @override
  State<PlaybackEditingBoundary> createState() =>
      _PlaybackEditingBoundaryState();
}

class _PlaybackEditingBoundaryState extends State<PlaybackEditingBoundary> {
  PlaybackQueue? _queue;
  @override
  void initState() {
    super.initState();
    _queue = context.read<PlaybackQueue>();
    _queue?.setEditing(true, notify: false);
  }

  @override
  void dispose() {
    _queue?.setEditing(false, notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

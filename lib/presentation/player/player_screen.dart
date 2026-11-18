import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/media_storage.dart';
import '../../domain/entities/book_page.dart';
import '../../domain/enums/enums.dart';
import '../../service_locator.dart';
import '../common/error_banner.dart';
import 'player_view_model.dart';
import 'playback_queue.dart';

/// 통합 플레이어 — **아이가 보는 화면**이다.
///
/// 설계 원칙:
/// - **그림이 주인공** — 페이지 이미지를 최대로 키우고 컨트롤은 아래로 물린다
/// - **큰 버튼** — 아이가 직접 넘기고 멈춘다
/// - 화면을 켜 둔다 — 재생 중 화면이 꺼지면 아이가 당황한다
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, this.managedByQueue = false});
  final bool managedByQueue;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  /// VM 참조를 미리 잡아 둔다.
  ///
  /// **왜 필요한가:** `dispose()` 에서 `context.read` 를 쓰면 안 된다 — 그 시점의 위젯은
  /// 이미 트리에서 분리돼 조상 조회가 안전하지 않다. 위젯 테스트에서 실제로
  /// 테스트가 끝나지 않고 멈췄다(2026-09-15).
  PlayerViewModel? _vm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _vm = context.read<PlayerViewModel>();
      if (!widget.managedByQueue) _vm!.start();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.managedByQueue &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused)) {
      _vm?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 화면을 떠나면 오디오를 멈추고 독서 기록을 닫는다.
    // dispose 는 동기라 await 할 수 없다 — leave() 가 비동기 작업을 맡는다.
    if (!widget.managedByQueue) _vm?.leave();
    _vm = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlayerViewModel>();

    return Scaffold(
      // 그림에 집중하도록 어둡게. 자기 전에 보는 화면이기도 하다.
      backgroundColor: const Color(0xFF191D2B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF191D2B),
        foregroundColor: const Color(0xFFF6F1E7),
        title: Text(
          vm.content.title.isEmpty ? '(제목 없음)' : vm.content.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (vm.availableSources.length > 1) _SourceMenu(vm: vm),
          _RepeatButton(vm: vm),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (vm.errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: ErrorBanner(
                  message: vm.errorMessage!,
                  onClose: vm.clearError,
                ),
              ),
            // 그림이 남는 공간을 전부 차지한다.
            Expanded(
              child: _PageView(
                vm: vm,
                queue: widget.managedByQueue
                    ? context.read<PlaybackQueue>()
                    : null,
              ),
            ),
            _TextStrip(vm: vm),
            _Controls(
              vm: vm,
              queue: widget.managedByQueue
                  ? context.read<PlaybackQueue>()
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// 페이지 그림. 좌우 스와이프로 넘길 수 있다.
class _PageView extends StatelessWidget {
  const _PageView({required this.vm, this.queue});
  final PlaybackQueue? queue;

  final PlayerViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.pageCount == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '읽을 페이지가 없어요.\n먼저 페이지를 추가해 주세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFB9BFCE), fontSize: 17),
          ),
        ),
      );
    }

    final page = vm.currentPage;
    if (page == null) return const SizedBox.shrink();

    return GestureDetector(
      // 스와이프로 넘긴다. 아이가 종이책을 넘기는 동작과 같다.
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          (queue?.nextPage ?? vm.next)();
        }
        if (v > 200) {
          (queue?.previousPage ?? vm.previous)();
        }
      },
      child: Center(
        child: _PageImage(contentId: vm.content.id, page: page),
      ),
    );
  }
}

class _PageImage extends StatelessWidget {
  const _PageImage({required this.contentId, required this.page});

  final String contentId;
  final BookPage page;

  @override
  Widget build(BuildContext context) {
    final abs = sl<MediaStorage>().absolutePathOf(contentId, page.imagePath);
    final file = File(abs);

    // 파일이 없으면 깨진 이미지 대신 안내를 보여준다.
    if (!file.existsSync()) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 64,
              color: Color(0xFF929BAD),
            ),
            SizedBox(height: 16),
            Text(
              '이 페이지의 사진을 찾을 수 없어요.',
              style: TextStyle(color: Color(0xFFB9BFCE)),
            ),
          ],
        ),
      );
    }

    return InteractiveViewer(
      // 아이가 그림을 확대해 볼 수 있게.
      maxScale: 4,
      child: Image.file(
        file,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(
          Icons.broken_image_outlined,
          size: 64,
          color: Color(0xFF929BAD),
        ),
      ),
    );
  }
}

/// 페이지 본문. 지금 읽는 문장을 보호자도 볼 수 있게.
class _TextStrip extends StatelessWidget {
  const _TextStrip({required this.vm});

  final PlayerViewModel vm;

  @override
  Widget build(BuildContext context) {
    final page = vm.currentPage;
    if (page == null || !page.hasText) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 120),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: SingleChildScrollView(
        child: Text(
          page.text!,
          style: const TextStyle(
            color: Color(0xFFF6F1E7),
            fontSize: 18,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.vm, this.queue});
  final PlaybackQueue? queue;

  final PlayerViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          // 진행 표시 — 몇 장 중 몇 장인지.
          Row(
            children: [
              Text(
                '${vm.index + 1} / ${vm.pageCount}',
                style: const TextStyle(color: Color(0xFFB9BFCE)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LinearProgressIndicator(
                  value: vm.progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF51586A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BigIcon(
                icon: Icons.skip_previous,
                tooltip: '이전 장',
                onPressed: vm.hasPrevious
                    ? (queue?.previousPage ?? vm.previous)
                    : null,
              ),
              _BigIcon(
                icon: vm.isPlaying ? Icons.pause_circle : Icons.play_circle,
                tooltip: vm.isPlaying ? '멈춤' : '재생',
                size: 72,
                onPressed: vm.pageCount == 0
                    ? null
                    : (queue?.toggle ?? (vm.isPlaying ? vm.pause : vm.resume)),
              ),
              _BigIcon(
                icon: Icons.skip_next,
                tooltip: '다음 장',
                onPressed: vm.hasNext ? (queue?.nextPage ?? vm.next) : null,
              ),
            ],
          ),
          if (vm.isFinished)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '다 읽었어요! 🎉',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 아이 손가락 기준 큰 버튼.
class _BigIcon extends StatelessWidget {
  const _BigIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 56,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: size,
    color: const Color(0xFFF6F1E7),
    disabledColor: const Color(0xFF51586A),
    icon: Icon(icon),
  );
}

/// 목소리 전환. 부모 녹음 ↔ 기기 TTS ↔ AI 목소리.
class _SourceMenu extends StatelessWidget {
  const _SourceMenu({required this.vm});

  final PlayerViewModel vm;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AudioSource?>(
      tooltip: '목소리 선택',
      icon: const Icon(Icons.record_voice_over_outlined),
      initialValue: vm.preferredSource,
      onSelected: vm.selectSource,
      itemBuilder: (_) => [
        const PopupMenuItem<AudioSource?>(
          value: null,
          child: Text('자동 (부모 목소리 우선)'),
        ),
        ...vm.availableSources.map(
          (s) => PopupMenuItem<AudioSource?>(
            value: s,
            child: Text(sourceLabel(s)),
          ),
        ),
      ],
    );
  }

  /// 사용자에게 보여줄 트랙 이름. enum 이름을 그대로 노출하지 않는다.
  static String sourceLabel(AudioSource s) => switch (s) {
    AudioSource.parentRecording => '부모 목소리 (녹음)',
    AudioSource.aiClonedVoice => '부모 목소리 (AI)',
    AudioSource.aiNarration => 'AI 나레이션',
    AudioSource.deviceTts => '기기 목소리',
  };
}

class _RepeatButton extends StatelessWidget {
  const _RepeatButton({required this.vm});

  final PlayerViewModel vm;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (vm.repeatMode) {
      PlayerRepeatMode.none => (Icons.repeat, '반복 없음'),
      PlayerRepeatMode.book => (Icons.repeat_on_outlined, '책 반복'),
      PlayerRepeatMode.page => (Icons.repeat_one_on_outlined, '한 장 반복'),
    };

    return IconButton(
      tooltip: label,
      icon: Icon(icon),
      onPressed: () {
        // none → book → page → none 순환
        final next = switch (vm.repeatMode) {
          PlayerRepeatMode.none => PlayerRepeatMode.book,
          PlayerRepeatMode.book => PlayerRepeatMode.page,
          PlayerRepeatMode.page => PlayerRepeatMode.none,
        };
        vm.setRepeatMode(next);
      },
    );
  }
}

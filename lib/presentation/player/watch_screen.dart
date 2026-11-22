import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_logger.dart';
import '../../core/error_codes.dart';
import '../../domain/repositories/repositories.dart';
import '../../service_locator.dart';
import 'playback_queue.dart';
import 'player_screen.dart';
import 'player_view_model.dart';

/// 화면 보호 — 안드로이드에서 캡처 · 녹화 막기(FLAG_SECURE)와 화면 켜 두기.
///
/// 왜 네이티브인가: 플러터에는 캡처를 막는 기본 기능이 없다. 새 패키지 대신 이미 있는
/// MainActivity 채널 방식을 따른다(의존성 0). iOS 는 채널이 없어 조용히 넘어간다.
class ScreenGuard {
  ScreenGuard._();
  static const _channel = MethodChannel('mychild_reading/screen');

  /// [secure] 가 false 면 화면만 켜 두고 캡처 · 미러링은 막지 않는다(설정 › TV 미러링 허용).
  static Future<void> watchMode(bool on, {bool secure = true}) async {
    try {
      await _channel.invokeMethod<void>('watchMode', {
        'on': on,
        'secure': secure,
      });
    } on MissingPluginException {
      // iOS · 테스트 — 채널이 없다. 캡처 막기는 안드로이드만 한다.
    } on PlatformException catch (e) {
      AppLogger.w('${ErrorCode.screenGuardFailure} 화면 보호 전환 실패: ${e.code}');
    }
  }
}

/// `/watch` — 재생 큐의 지금 책을 영상처럼 보여 준다. 책이 끝나면 큐가 다음 책으로 넘긴다.
class WatchReader extends StatelessWidget {
  const WatchReader({super.key});
  @override
  Widget build(BuildContext context) {
    final q = context.watch<PlaybackQueue>();
    final p = q.player;
    return WatchScreen(
      key: ValueKey(p),
      player: p,
      onNext: q.nextPage,
      onPrevious: q.previousPage,
      onToggle: q.toggle,
    );
  }
}

/// 영상처럼 보기 — 차 · 태블릿 · TV 용 가로 전체 화면.
///
/// - 그림만 크게, 버튼 없음. 페이지는 목소리가 끝나면 저절로 넘어간다(플레이어의 기존 흐름).
/// - **아이 잠금:** 뒤로 가기를 막고, 오른쪽 위 자물쇠를 [unlockHold] 동안 눌러야 나간다.
/// - 안드로이드에서는 화면을 켜 두고, 설정에서 미러링을 허용하지 않았으면 캡처 · 녹화 · 미러링을 막는다([ScreenGuard]).
class WatchScreen extends StatefulWidget {
  const WatchScreen({
    super.key,
    required this.player,
    required this.onNext,
    required this.onPrevious,
    required this.onToggle,
  });
  final PlayerViewModel? player;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function({bool onlyPlay}) onToggle;

  /// 아이가 우연히 누르는 시간보다 충분히 길게.
  static const unlockHold = Duration(seconds: 2);

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: WatchScreen.unlockHold,
  )..addStatusListener(_onHoldStatus);

  /// 잠금 안내를 잠깐 보인다(아이가 화면을 두드렸을 때).
  bool _hint = false;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    // FLOW 1: 가로 · 전체 화면 · 화면 보호를 켠다
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _guard();
  }

  Future<void> _guard() async {
    final allow = await sl<WatchSettingsRepository>().allowMirroring();
    // 설정을 읽는 사이에 화면을 떠났으면 켜지 않는다.
    if (!mounted) return;
    await ScreenGuard.watchMode(true, secure: !allow);
  }

  @override
  void dispose() {
    // FLOW 9: 나갈 때 되돌린다 — 다른 화면이 가로로 굳으면 보호자가 당황한다
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ScreenGuard.watchMode(false);
    _hintTimer?.cancel();
    _hold.dispose();
    super.dispose();
  }

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showHint() {
    _hintTimer?.cancel();
    setState(() => _hint = true);
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    return PopScope(
      // 아이 잠금 — 뒤로 가기 버튼으로 나가지 않는다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showHint();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (p == null)
              const Center(
                child: Text(
                  '재생할 책이 없어요.',
                  style: TextStyle(color: Colors.white70, fontSize: 20),
                ),
              )
            else
              ChangeNotifierProvider<PlayerViewModel>.value(
                value: p,
                child: _WatchPage(
                  onNext: widget.onNext,
                  onPrevious: widget.onPrevious,
                  onTap: () {
                    widget.onToggle(onlyPlay: false);
                    _showHint();
                  },
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(child: _lockButton()),
            ),
            if (_hint)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x99000000),
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        '나가려면 🔒 를 꾹 누르고 있어요',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _lockButton() => Semantics(
    button: true,
    label: '영상처럼 보기 나가기 — 길게 누르기',
    child: GestureDetector(
      onTapDown: (_) => _hold.forward(from: 0),
      onTapUp: (_) => _hold.reverse(),
      onTapCancel: () => _hold.reverse(),
      child: SizedBox(
        width: 52,
        height: 52,
        child: AnimatedBuilder(
          animation: _hold,
          builder: (_, _) => Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _hold.value,
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: const Color(0x33FFFFFF),
              ),
              const Icon(Icons.lock_outline, color: Colors.white70),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WatchPage extends StatelessWidget {
  const _WatchPage({
    required this.onNext,
    required this.onPrevious,
    required this.onTap,
  });
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlayerViewModel>();
    final page = vm.currentPage;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) onNext();
        if (v > 200) onPrevious();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (page != null)
            Center(
              child: PageImage(
                contentId: vm.content.id,
                page: page,
                zoomable: false,
              ),
            ),
          if (!vm.isPlaying)
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 96,
                color: Color(0xCCFFFFFF),
              ),
            ),
          Positioned(
            left: 16,
            bottom: 12,
            child: Text(
              vm.pageCount == 0 ? '' : '${vm.index + 1} / ${vm.pageCount}',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

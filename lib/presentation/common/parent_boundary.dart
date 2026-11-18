import 'package:flutter/material.dart';

/// 우발 조작 방지용 확인이다. 계정 인증이나 강한 아동 잠금으로 취급하지 않는다.
class ParentBoundary extends StatefulWidget {
  const ParentBoundary({
    super.key,
    required this.child,
    this.initiallyConfirmed = false,
  });
  final bool initiallyConfirmed;
  final Widget child;
  @override
  State<ParentBoundary> createState() => _ParentBoundaryState();
}

class _ParentBoundaryState extends State<ParentBoundary>
    with WidgetsBindingObserver {
  late bool _confirmed = widget.initiallyConfirmed;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      setState(() => _confirmed = false);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // 편집 VM을 없애지 않고 가려서 입력을 보존한다.
      Offstage(
        offstage: !_confirmed,
        child: ExcludeFocus(excluding: !_confirmed, child: widget.child),
      ),
      if (!_confirmed)
        Scaffold(
          appBar: AppBar(title: const Text('부모 공간')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_stories_outlined, size: 42),
                    const SizedBox(height: 24),
                    Text(
                      '부모님과 함께\n열어 주세요.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    const Text('책을 만들고 목소리를 담는 공간이에요.'),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: () => setState(() => _confirmed = true),
                      child: const Text('부모 공간 열기'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

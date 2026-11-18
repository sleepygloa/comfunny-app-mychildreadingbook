import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'photo_edit_screen.dart';

/// 표지는 단일 촬영, 본문은 가로 연속 촬영하며 각 장을 즉시 초안에 보관한다.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    this.onPageCaptured,
    this.createCamera,
    this.reviewPhoto,
  });

  final Future<bool> Function(String path)? onPageCaptured;
  @visibleForTesting
  final Future<String?> Function(BuildContext context, String path)?
  reviewPhoto;
  @visibleForTesting
  final Future<CameraController> Function()? createCamera;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  // 카메라와 화면 방향은 전역 자원: 빠른 닫기/재진입도 같은 큐를 공유한다.
  static Future<void>? _cameraTasks;
  static _CaptureScreenState? _owner;
  static CameraController? _activeCamera;
  static void _enqueue(Future<void> Function() action) {
    late final Future<void> next;
    next = (_cameraTasks ?? Future<void>.value())
        .then((_) => action())
        .whenComplete(() {
          if (identical(_cameraTasks, next)) _cameraTasks = null;
        });
    _cameraTasks = next;
  }

  String? _error;
  String? _pendingPhoto;
  bool _busy = false;
  bool _reviewing = false;
  bool _cameraUnavailable = false;
  bool _allowExit = false;
  bool _confirmingExit = false;
  bool _suspended = false;
  int _generation = 0;
  int _count = 0;
  bool get _continuous => widget.onPageCaptured != null;

  @override
  void initState() {
    super.initState();
    _owner = this;
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<CameraController> _createCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('no camera');
    return CameraController(
      cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      ),
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );
  }

  void _open() {
    if (_camera != null || _reviewing) return;
    final generation = ++_generation;
    // 초기화 도중 앱이 비활성화돼도 이전 카메라 해제 후에만 다시 연다.
    _enqueue(() async {
      if (!mounted || _suspended || generation != _generation) return;
      CameraController? controller;
      try {
        final previous = _activeCamera;
        _activeCamera = null;
        await previous?.dispose();
        await SystemChrome.setPreferredOrientations(
          _continuous ? [DeviceOrientation.landscapeLeft] : [],
        );
        if (!mounted || _suspended || generation != _generation) return;
        controller = await (widget.createCamera ?? _createCamera)();
        await controller.initialize();
        if (_continuous) {
          await controller.lockCaptureOrientation(
            DeviceOrientation.landscapeLeft,
          );
        }
        if (!mounted || _suspended || generation != _generation) {
          await controller.dispose();
          return;
        }
        setState(() {
          _activeCamera = controller;
          _cameraUnavailable = false;
          _camera = controller;
          _error = null;
        });
      } on Object {
        try {
          await controller?.dispose();
        } on Object {
          // 초기화 실패 뒤에도 다시 열기/화면 종료를 허용한다.
        }
        if (mounted && generation == _generation) {
          setState(() {
            _cameraUnavailable = true;
            _error = '카메라를 열지 못했어요. 카메라 권한을 확인해 주세요.';
          });
        }
      }
    });
  }

  void _close() {
    _generation++;
    final controller = _camera;
    _camera = null;
    _enqueue(() async {
      try {
        if (identical(_activeCamera, controller)) {
          _activeCamera = null;
          await controller?.dispose();
        }
      } on Object {
        // 닫기 실패가 이후 카메라 초기화를 막지 않게 한다.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _suspended = true;
      _close();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _suspended = false;
      _open();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _close();
    // 이전 화면 정리가 새 촬영 화면의 방향 설정을 덮어쓰지 않게 한다.
    _enqueue(() async {
      try {
        if (!identical(_owner, this)) return;
        _owner = null;
        await SystemChrome.setPreferredOrientations([]);
      } on Object {
        // 방향 복원 실패가 다음 카메라 실행을 막지 않게 한다.
      }
    });
    super.dispose();
  }

  Future<void> _capture() async {
    if (_busy || _suspended) return;
    if (_pendingPhoto == null && _camera?.value.isInitialized != true) return;
    if (_pendingPhoto == null &&
        _continuous &&
        MediaQuery.orientationOf(context) != Orientation.landscape) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pendingPhoto == null) {
        final raw = await _camera!.takePicture();
        if (!mounted) return;
        _reviewing = true;
        _close();
        try {
          _pendingPhoto = widget.reviewPhoto != null
              ? await widget.reviewPhoto!(context, raw.path)
              : await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PhotoEditScreen(path: raw.path),
                  ),
                );
        } finally {
          _reviewing = false;
          if (mounted && !_suspended) _open();
        }
        if (_pendingPhoto == null) return;
      }
      if (!mounted) return;
      if (!_continuous) {
        final path = _pendingPhoto;
        setState(() => _allowExit = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, path);
        });
        return;
      }
      final saved = await widget.onPageCaptured!(_pendingPhoto!);
      if (!mounted) return;
      setState(() {
        if (saved) {
          _count++;
          _pendingPhoto = null;
        } else {
          _error = '사진을 보관하지 못했어요. 저장 재시도를 눌러 주세요.';
        }
      });
    } on Object {
      if (mounted) setState(() => _error = '촬영 또는 보관에 실패했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leavePending() async {
    if (_busy || _confirmingExit || _pendingPhoto == null) return;
    _confirmingExit = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('마지막 사진을 제외하고 나갈까요?'),
        content: const Text('보관에 실패한 마지막 사진만 제외돼요. 이미 보관한 사진은 유지돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 촬영'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('제외하고 나가기'),
          ),
        ],
      ),
    );
    _confirmingExit = false;
    if (!mounted || leave != true) return;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final canCapture =
        !_busy &&
        !_suspended &&
        (_pendingPhoto != null ||
            (_camera?.value.isInitialized == true &&
                (!_continuous || landscape)));
    final controls = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_continuous)
            Text('$_count장 보관됨', semanticsLabel: '$_count장 촬영 보관 완료'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canCapture ? _capture : null,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_pendingPhoto != null ? '저장 재시도' : '사진 찍기'),
          ),
        ],
      ),
    );
    return PopScope(
      canPop: _allowExit || (!_busy && _pendingPhoto == null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leavePending();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_continuous ? '내용 연속 촬영 · $_count장' : '표지 촬영'),
          actions: [
            if (_continuous)
              TextButton(
                onPressed: _busy || _pendingPhoto != null
                    ? null
                    : () => Navigator.pop(context),
                child: const Text('완료'),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_continuous)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text('책을 펼쳐 왼쪽·오른쪽을 함께 찍으세요. 책장을 넘기며 계속 촬영할 수 있어요.'),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_camera == null && (_error != null || _cameraUnavailable))
                TextButton(
                  onPressed: _suspended ? null : _open,
                  child: const Text('카메라 다시 열기'),
                ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: _continuous && !landscape
                            ? const Text('휴대폰을 가로로 돌려 주세요.')
                            : _camera?.value.isInitialized == true
                            ? CameraPreview(_camera!)
                            : _error == null && !_cameraUnavailable
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.no_photography_outlined),
                      ),
                    ),
                    if (landscape)
                      SizedBox(
                        width: 180,
                        child: SingleChildScrollView(child: controls),
                      ),
                  ],
                ),
              ),
              if (!landscape) controls,
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'photo_processing.dart';

/// 네 모서리로 영역을 정한다. 그림책 색을 보존하는 선택형 밝기/대비 보정이다.
class PhotoEditScreen extends StatefulWidget {
  const PhotoEditScreen({super.key, required this.path});
  final String path;
  @override
  State<PhotoEditScreen> createState() => _PhotoEditScreenState();
}

class _PhotoEditScreenState extends State<PhotoEditScreen> {
  ui.Image? _image;
  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1);
  bool _enhanced = true;
  double _brightness = .09;
  bool _saving = false;
  bool _allowExit = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final image = await PhotoProcessing.load(widget.path);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } on Object {
      if (mounted) setState(() => _error = '사진을 열지 못했어요. 돌아가서 다시 촬영해 주세요.');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _move(int corner, Offset delta, Size size) {
    var l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;
    if (corner == 0 || corner == 3) {
      l = (l + delta.dx / size.width).clamp(0, r - .08);
    } else {
      r = (r + delta.dx / size.width).clamp(l + .08, 1);
    }
    if (corner < 2) {
      t = (t + delta.dy / size.height).clamp(0, b - .08);
    } else {
      b = (b + delta.dy / size.height).clamp(t + .08, 1);
    }
    setState(() => _crop = Rect.fromLTRB(l, t, r, b));
  }

  Future<void> _apply() async {
    if (_saving || _image == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // 화면이 외부에서 제거돼도 인코딩이 끝날 때까지 이미지를 소유한다.
    final image = _image!.clone();
    File? file;
    try {
      final bytes = await PhotoProcessing.render(
        image,
        _crop,
        enhanced: _enhanced,
        brightness: _brightness,
      );
      final directory = await getTemporaryDirectory();
      file = File('${directory.path}/book-scan-${const Uuid().v4()}.png');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        await file.delete();
        return;
      }
      setState(() => _allowExit = true);
      final path = file.path;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, path);
      });
    } on Object {
      if (file != null) {
        try {
          await file.delete();
        } on Object {
          /* 원본은 유지한다. */
        }
      }
      if (mounted) setState(() => _error = '사진을 보정하지 못했어요. 다시 적용해 주세요.');
    } finally {
      image.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _canvas() => LayoutBuilder(
    builder: (context, constraints) {
      final image = _image!;
      final scale = math.min(
        (constraints.maxWidth - 40) / image.width,
        (constraints.maxHeight - 40) / image.height,
      );
      final size = Size(
        image.width * math.max(.01, scale),
        image.height * math.max(.01, scale),
      );
      final rect = Rect.fromLTRB(
        _crop.left * size.width,
        _crop.top * size.height,
        _crop.right * size.width,
        _crop.bottom * size.height,
      );
      return Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ColorFiltered(
                  colorFilter: PhotoProcessing.filter(
                    enhanced: _enhanced,
                    brightness: _brightness,
                  ),
                  child: RawImage(image: image, fit: BoxFit.fill),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _CropMask(rect)),
                ),
              ),
              for (final entry in [
                rect.topLeft,
                rect.topRight,
                rect.bottomRight,
                rect.bottomLeft,
              ].asMap().entries)
                Positioned(
                  left: entry.value.dx - 24,
                  top: entry.value.dy - 24,
                  child: Semantics(
                    label: '자르기 모서리 ${entry.key + 1}',
                    child: GestureDetector(
                      key: ValueKey('crop-corner-${entry.key}'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: _saving
                          ? null
                          : (details) => _move(entry.key, details.delta, size),
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: SizedBox(width: 20, height: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _controls() => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('네 모서리를 움직여 책 영역을 맞춰 주세요.'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('원본 색상'),
                selected: !_enhanced,
                onSelected: _saving
                    ? null
                    : (_) => setState(() {
                        _enhanced = false;
                        _brightness = 0;
                      }),
              ),
              ChoiceChip(
                label: const Text('문서 보정'),
                selected: _enhanced,
                onSelected: _saving
                    ? null
                    : (_) => setState(() {
                        _enhanced = true;
                        _brightness = .09;
                      }),
              ),
            ],
          ),
          const Text('밝기'),
          Slider(
            value: _brightness,
            min: -.2,
            max: .3,
            onChanged: _saving
                ? null
                : (value) => setState(() => _brightness = value),
          ),
          TextButton(
            onPressed: _saving
                ? null
                : () => setState(() => _crop = const Rect.fromLTRB(0, 0, 1, 1)),
            child: const Text('전체 영역'),
          ),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving || _allowExit,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('영역 조정 · 보정'),
        actions: [
          TextButton(
            onPressed: _image == null || _saving ? null : _apply,
            child: Text(_saving ? '처리 중…' : '적용'),
          ),
        ],
      ),
      body: SafeArea(
        child: _image == null
            ? Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Text(_error!),
              )
            : LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth > constraints.maxHeight
                    ? Row(
                        children: [
                          Expanded(child: _canvas()),
                          SizedBox(width: 230, child: _controls()),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: _canvas()),
                          _controls(),
                        ],
                      ),
              ),
      ),
    ),
  );
}

class _CropMask extends CustomPainter {
  const _CropMask(this.rect);
  final Rect rect;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(path, Paint()..color = Colors.black54);
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropMask oldDelegate) => rect != oldDelegate.rect;
}

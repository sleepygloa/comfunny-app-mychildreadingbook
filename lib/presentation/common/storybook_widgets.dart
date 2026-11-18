import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 테마에 맞춘 작은 종이책 캐릭터. 외부 이미지나 개인정보를 사용하지 않는다.
class BookFriend extends StatelessWidget {
  const BookFriend({
    super.key,
    this.size = 80,
    this.color = const Color(0xFFEAB5A5),
  });
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BookFriendPainter(color)),
    ),
  );
}

class _BookFriendPainter extends CustomPainter {
  _BookFriendPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    final paint = Paint()..isAntiAlias = true;
    paint.color = const Color(0xFF5A4566).withValues(alpha: .10);
    canvas.drawOval(const Rect.fromLTWH(15, 83, 72, 9), paint);
    paint.color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(17, 15, 66, 69),
        const Radius.circular(14),
      ),
      paint,
    );
    paint.color = const Color(0xFFFFF8E8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(27, 13, 58, 65),
        const Radius.circular(11),
      ),
      paint,
    );
    paint.color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(22, 12, 60, 60),
        const Radius.circular(11),
      ),
      paint,
    );
    paint.color = const Color(0xFF574363).withValues(alpha: .20);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(23, 17, 4, 48),
        const Radius.circular(2),
      ),
      paint,
    );
    paint.color = const Color(0xFF47354D);
    canvas.drawCircle(const Offset(44, 39), 2.7, paint);
    canvas.drawCircle(const Offset(65, 39), 2.7, paint);
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(48, 43, 13, 11),
      0,
      math.pi,
      false,
      paint,
    );
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFC7717F).withValues(alpha: .55);
    canvas.drawOval(const Rect.fromLTWH(34, 45, 10, 5), paint);
    canvas.drawOval(const Rect.fromLTWH(66, 45, 10, 5), paint);
    paint.color = const Color(0xFF6350A0);
    canvas.drawPath(
      Path()
        ..moveTo(64, 12)
        ..lineTo(64, 28)
        ..lineTo(69, 24)
        ..lineTo(74, 28)
        ..lineTo(74, 12)
        ..close(),
      paint,
    );
    paint.color = const Color(0xFFC09343);
    for (final p in [const Offset(10, 27), const Offset(91, 52)]) {
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy - 5)
          ..lineTo(p.dx + 2, p.dy - 1)
          ..lineTo(p.dx + 6, p.dy)
          ..lineTo(p.dx + 2, p.dy + 2)
          ..lineTo(p.dx, p.dy + 6)
          ..lineTo(p.dx - 2, p.dy + 2)
          ..lineTo(p.dx - 5, p.dy)
          ..lineTo(p.dx - 2, p.dy - 1)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BookFriendPainter oldDelegate) =>
      oldDelegate.color != color;
}

class StoryWelcome extends StatefulWidget {
  const StoryWelcome({
    super.key,
    required this.title,
    required this.subtitle,
    this.isPlaylist = false,
  });
  final String title, subtitle;
  final bool isPlaylist;
  @override
  State<StoryWelcome> createState() => _StoryWelcomeState();
}

class _StoryWelcomeState extends State<StoryWelcome> {
  int _greetings = 0;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final friend = Semantics(
      button: true,
      label: '책 친구 인사',
      child: Tooltip(
        message: '톡, 인사해 볼까요?',
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => setState(() => _greetings++),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _greetings.toDouble()),
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 700),
            builder: (context, value, child) => Transform.rotate(
              angle: reduced ? 0 : math.sin(value * math.pi * 2) * .16,
              child: child,
            ),
            child: BookFriend(
              size: 86,
              color: widget.isPlaylist
                  ? const Color(0xFFADCFC4)
                  : const Color(0xFFEAB5A5),
            ),
          ),
        ),
      ),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.isPlaylist ? '차곡차곡, 우리 이야기' : '마음이 자라는 작은 책방',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            letterSpacing: .3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.title,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
        ),
        const SizedBox(height: 8),
        Text(widget.subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
          bottomLeft: Radius.circular(10),
          bottomRight: Radius.circular(30),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [const Color(0xFF34304A), const Color(0xFF293C40)]
              : widget.isPlaylist
              ? [const Color(0xFFE6F3E9), const Color(0xFFF5F1DF)]
              : [const Color(0xFFFFE9DB), const Color(0xFFFFF5DE)],
        ),
        border: Border.all(
          color: dark ? const Color(0xFF565168) : Colors.white,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(16) > 22
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [friend, words],
              )
            : Row(
                children: [
                  Expanded(child: words),
                  const SizedBox(width: 8),
                  friend,
                ],
              ),
      ),
    );
  }
}

/// 선택 시 한 번만 튀어 오르는 탭. 위치/이름은 기존 내비게이션을 유지한다.
class StoryTabIcon extends StatelessWidget {
  const StoryTabIcon({super.key, required this.icon, required this.selected});
  final IconData icon;
  final bool selected;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: selected ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    curve: Curves.easeOutBack,
    builder: (_, value, _) => Transform.translate(
      offset: Offset(0, -2 * value),
      child: Transform.scale(scale: 1 + .10 * value, child: Icon(icon)),
    ),
  );
}

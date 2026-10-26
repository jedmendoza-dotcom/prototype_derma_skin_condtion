import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'smart_image.dart';

/// Picture side of the login / register card.
/// Shows a photo if the asset exists, otherwise a blue gradient, with an
/// animated dot-grid "scan" effect on top.
class PicturePanel extends StatefulWidget {
  final String asset;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> chips;
  final bool compact;

  const PicturePanel({
    super.key,
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.chips = const [],
    this.compact = false,
  });

  @override
  State<PicturePanel> createState() => _PicturePanelState();
}

class _PicturePanelState extends State<PicturePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan =
      AnimationController(vsync: this, duration: const Duration(seconds: 5))
        ..repeat();

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  Widget _badge() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fade(Colors.white, .18),
        border: Border.all(color: fade(Colors.white, .4)),
      ),
      child: Icon(widget.icon, color: Colors.white, size: 24),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (widget.compact) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            _badge(),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _badge(),
            const SizedBox(height: 22),
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.subtitle,
              style: TextStyle(
                color: fade(Colors.white, .85),
                fontSize: 15.5,
                height: 1.5,
              ),
            ),
            if (widget.chips.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in widget.chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: fade(Colors.white, .16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: fade(Colors.white, .3)),
                      ),
                      child: Text(
                        c,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryDark, AppColors.primary, AppColors.accent],
            ),
          ),
        ),
        Positioned.fill(
          child: SmartImage(asset: widget.asset, fallback: const SizedBox.shrink()),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  fade(AppColors.primaryDark, .30),
                  fade(AppColors.primaryDark, .85),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _ScanPainter(_scan)),
          ),
        ),
        content,
      ],
    );
  }
}

class _ScanPainter extends CustomPainter {
  final Animation<double> t;
  _ScanPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = fade(Colors.white, .20);
    const gap = 26.0;
    for (double y = gap / 2; y < size.height; y += gap) {
      for (double x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1.4, dot);
      }
    }

    final y = size.height * t.value;
    final band = Rect.fromLTWH(0, y - 70, size.width, 70);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fade(AppColors.accent, 0), fade(Colors.white, .28)],
        ).createShader(band),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, y - 1.5, size.width, 3),
      Paint()..color = fade(Colors.white, .7),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanPainter oldDelegate) => false;
}

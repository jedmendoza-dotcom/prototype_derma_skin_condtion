import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Soft blue gradient with two glowing blobs, shared by every page.
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEAF3FC), Color(0xFFF7FBFF), Color(0xFFE6F6FB)],
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -100,
          child: _Blob(size: 380, color: fade(AppColors.primary, .14)),
        ),
        Positioned(
          bottom: -140,
          left: -120,
          child: _Blob(size: 420, color: fade(AppColors.accent, .16)),
        ),
        child,
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, fade(color, 0)]),
        ),
      ),
    );
  }
}

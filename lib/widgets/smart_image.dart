import 'package:flutter/material.dart';

/// Shows an asset image, or [fallback] when the file does not exist yet.
class SmartImage extends StatelessWidget {
  final String asset;
  final Widget fallback;
  final BoxFit fit;

  const SmartImage({
    super.key,
    required this.asset,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

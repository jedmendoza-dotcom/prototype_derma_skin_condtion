import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'picture_panel.dart';

/// White rounded card with a picture panel on one side and [form] on the other.
/// On phones the picture collapses into a slim banner above the form.
class AuthLayout extends StatelessWidget {
  final Widget form;
  final bool panelOnLeft;
  final String asset;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> chips;

  const AuthLayout({
    super.key,
    required this.form,
    required this.panelOnLeft,
    required this.asset,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.chips = const [],
  });

  PicturePanel _panel({bool compact = false}) => PicturePanel(
        asset: asset,
        title: title,
        subtitle: subtitle,
        icon: icon,
        chips: chips,
        compact: compact,
      );

  @override
  Widget build(BuildContext context) {
    final topInset = barInset(context);

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final cardWidth = wide
            ? math.min(c.maxWidth - 64, 1040.0)
            : math.min(c.maxWidth - 32, 520.0);
        final half = cardWidth / 2;

        final Widget body;
        if (wide) {
          body = ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 580),
            child: Stack(
              children: [
                Positioned(
                  left: panelOnLeft ? 0 : null,
                  right: panelOnLeft ? null : 0,
                  top: 0,
                  bottom: 0,
                  width: half,
                  child: _panel(),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: panelOnLeft ? half : 0,
                    right: panelOnLeft ? 0 : half,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(44, 40, 44, 40),
                    child: form,
                  ),
                ),
              ],
            ),
          );
        } else {
          body = Column(
            children: [
              SizedBox(height: 96, child: _panel(compact: true)),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                child: form,
              ),
            ],
          );
        }

        final card = DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: fade(AppColors.primary, .14),
                blurRadius: 50,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: body,
          ),
        );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, topInset + 24, 16, 40),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, c.maxHeight - topInset - 64),
            ),
            child: Center(child: SizedBox(width: cardWidth, child: card)),
          ),
        );
      },
    );
  }
}

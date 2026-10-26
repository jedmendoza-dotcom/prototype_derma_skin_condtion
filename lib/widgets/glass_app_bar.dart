import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Translucent "frosted glass" app bar: HOME / LOGIN / REGISTER.
/// Page indexes: 0 = home, 1 = login, 2 = register.
class GlassAppBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final String? username;
  final VoidCallback onLogout;

  const GlassAppBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.username,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 760;
    final loggedIn = username != null;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.only(
            top: media.padding.top,
            left: wide ? 32 : 16,
            right: wide ? 32 : 8,
          ),
          decoration: BoxDecoration(
            color: fade(Colors.white, .72),
            border: Border(
              bottom: BorderSide(color: fade(AppColors.primary, .10)),
            ),
          ),
          child: SizedBox(
            height: kBarHeight,
            child: Row(
              children: [
                _Logo(onTap: () => onSelect(0)),
                const Spacer(),
                if (wide) ...[
                  _NavButton(
                    label: 'HOME',
                    selected: index == 0,
                    onTap: () => onSelect(0),
                  ),
                  if (!loggedIn) ...[
                    const SizedBox(width: 6),
                    _NavButton(
                      label: 'LOGIN',
                      selected: index == 1,
                      onTap: () => onSelect(1),
                    ),
                    const SizedBox(width: 6),
                    _NavButton(
                      label: 'REGISTER',
                      selected: index == 2,
                      onTap: () => onSelect(2),
                    ),
                  ] else ...[
                    const SizedBox(width: 14),
                    _UserChip(username: username!),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text(
                        'LOGOUT',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ] else
                  _MobileMenu(
                    loggedIn: loggedIn,
                    onSelect: onSelect,
                    onLogout: onLogout,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final VoidCallback onTap;
  const _Logo({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.accent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: fade(AppColors.primary, .35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.health_and_safety_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
                children: [
                  TextSpan(text: 'Derma', style: TextStyle(color: AppColors.ink)),
                  TextSpan(
                    text: 'Screen',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: fade(AppColors.primary, .35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 280),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: selected ? Colors.white : AppColors.ink,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

class _UserChip extends StatelessWidget {
  final String username;
  const _UserChip({required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: fade(AppColors.primary, .08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.primary,
            child: Text(
              username.isEmpty ? '?' : username[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            username,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _MobileMenu extends StatelessWidget {
  final bool loggedIn;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _MobileMenu({
    required this.loggedIn,
    required this.onSelect,
    required this.onLogout,
  });

  PopupMenuItem<int> _item(int value, String label, IconData icon) {
    return PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.menu_rounded, size: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (v) {
        if (v == -1) {
          onLogout();
        } else {
          onSelect(v);
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<int>>[
        _item(0, 'Home', Icons.home_outlined),
        if (!loggedIn) ...[
          _item(1, 'Login', Icons.login_rounded),
          _item(2, 'Register', Icons.person_add_alt_1_outlined),
        ] else
          _item(-1, 'Logout', Icons.logout_rounded),
      ],
    );
  }
}

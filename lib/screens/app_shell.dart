import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_app_bar.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'register_page.dart';

/// Keeps the glass app bar fixed while the page underneath changes with a
/// fade + soft blur + slight zoom transition.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _auth = AuthService();
  int _index = 0; // 0 home, 1 login, 2 register
  String? _user;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final u = await _auth.restoreSession();
    if (mounted && u != null) setState(() => _user = u);
  }

  void _go(int i) {
    if (i == _index) return;
    if (_user != null && i != 0) return; // signed-in users don't need these
    setState(() => _index = i);
  }

  void _onLoggedIn(String username) {
    setState(() {
      _user = username;
      _index = 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Signed in as $username'),
      ),
    );
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (!mounted) return;
    setState(() {
      _user = null;
      _index = 0;
    });
  }

  Widget _page() {
    switch (_index) {
      case 1:
        return LoginPage(
          key: const ValueKey('login'),
          onNavigate: _go,
          onLoggedIn: _onLoggedIn,
        );
      case 2:
        return RegisterPage(
          key: const ValueKey('register'),
          onNavigate: _go,
        );
      default:
        return HomePage(
          key: const ValueKey('home'),
          onNavigate: _go,
          username: _user,
        );
    }
  }

  Widget _transition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        child: AnimatedBuilder(
          animation: curved,
          child: child,
          builder: (context, c) {
            final sigma = (1 - curved.value) * 6;
            if (sigma < 0.05) return c!;
            return ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: c,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: _transition,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, if (current != null) current],
                ),
                child: _page(),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GlassAppBar(
                index: _index,
                onSelect: _go,
                username: _user,
                onLogout: _logout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

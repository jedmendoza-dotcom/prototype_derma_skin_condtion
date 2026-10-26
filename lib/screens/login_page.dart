import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/login_guard.dart';
import '../widgets/auth_layout.dart';
import '../widgets/password_field.dart';

class LoginPage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  final ValueChanged<String> onLoggedIn;

  const LoginPage({
    super.key,
    required this.onNavigate,
    required this.onLoggedIn,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService();
  final _guard = LoginGuard();

  bool _remember = false;
  bool _loading = false;
  String? _error;
  DateTime? _lockedUntil;
  Timer? _timer;

  bool get _locked =>
      _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now());

  Duration get _left =>
      _locked ? _lockedUntil!.difference(DateTime.now()) : Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadLock();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadLock() async {
    final until = await _guard.activeLock();
    if (!mounted || until == null) return;
    setState(() => _lockedUntil = until);
    _startTicker();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_locked) {
        setState(() {});
        return;
      }
      t.cancel();
      await _guard.activeLock(); // clears the expired lock and the counter
      if (!mounted) return;
      setState(() {
        _lockedUntil = null;
        _error = null;
      });
    });
  }

  Future<void> _submit() async {
    if (_locked || _loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await _auth.login(
      _username.text.trim(),
      _password.text,
      remember: _remember,
    );
    if (!mounted) return;

    if (res.ok) {
      await _guard.reset();
      if (!mounted) return;
      widget.onLoggedIn(res.username ?? _username.text.trim());
      return;
    }

    // Server down / rate limited: tell the user, but don't count it.
    if (res.networkError) {
      setState(() {
        _loading = false;
        _error = res.message;
      });
      return;
    }

    final f = await _guard.registerFailure();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (f.lockedUntil != null) {
        _lockedUntil = f.lockedUntil;
        _error = null;
        _password.clear();
      } else {
        final n = f.attemptsLeft;
        _error = 'Incorrect username or password. '
            '$n attempt${n == 1 ? '' : 's'} left.';
      }
    });
    if (f.lockedUntil != null) _startTicker();
  }

  String get _countdown {
    final s = (_left.inMilliseconds / 1000).ceil();
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Widget _banner() {
    if (_locked) {
      return _Notice(
        key: const ValueKey('lock'),
        color: AppColors.danger,
        icon: Icons.lock_clock_rounded,
        title: 'Too many failed attempts',
        message: 'Sign-in is locked for your security. '
            'Try again in $_countdown.',
      );
    }
    if (_error != null) {
      return _Notice(
        key: ValueKey(_error),
        color: AppColors.danger,
        icon: Icons.error_outline_rounded,
        message: _error!,
      );
    }
    return const SizedBox.shrink(key: ValueKey('none'));
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    final busy = locked || _loading;

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Welcome back',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to continue your skin screening.',
            style: TextStyle(color: AppColors.muted, fontSize: 15),
          ),
          const SizedBox(height: 26),
          TextFormField(
            controller: _username,
            enabled: !busy,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter your username' : null,
          ),
          const SizedBox(height: 16),
          PasswordField(
            controller: _password,
            label: 'Password',
            enabled: !busy,
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter your password' : null,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _banner(),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: busy ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : Text(locked ? 'Locked for $_countdown' : 'Sign in'),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'New to DermaScreen?',
                style: TextStyle(color: AppColors.muted),
              ),
              TextButton(
                onPressed: () => widget.onNavigate(2),
                child: const Text(
                  'Create an account',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (AuthService.useMock)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Demo account: demo / Demo@1234',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 8),
          _RememberMe(
            value: _remember,
            enabled: !busy,
            onChanged: (v) => setState(() => _remember = v),
          ),
        ],
      ),
    );

    return AuthLayout(
      form: form,
      panelOnLeft: true,
      asset: 'assets/images/login.jpg',
      title: 'Healthy skin starts with a check-up',
      subtitle:
          'Sign in to run a screening, review your results and get guidance '
          'on your next steps.',
      icon: Icons.verified_user_rounded,
      chips: const ['Secure sign-in', 'Private results'],
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String? title;
  final String message;

  const _Notice({
    super.key,
    required this.color,
    required this.icon,
    required this.message,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: fade(color, .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: fade(color, .35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: color,
                        fontSize: 14.5,
                      ),
                    ),
                  Text(
                    message,
                    style: const TextStyle(fontSize: 13.5, height: 1.45),
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

/// Small pill at the bottom of the form: "Remember me for 7 days".
class _RememberMe extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _RememberMe({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: value ? fade(AppColors.primary, .09) : const Color(0xFFF7FAFE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: value ? fade(AppColors.primary, .35) : AppColors.line,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.devices_rounded,
            size: 22,
            color: value ? AppColors.primary : AppColors.muted,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Remember me for 7 days',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  'Only on your own device',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

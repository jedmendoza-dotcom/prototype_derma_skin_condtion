import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/validators.dart';
import '../services/auth_service.dart';
import '../widgets/auth_layout.dart';
import '../widgets/human_check.dart';
import '../widgets/password_field.dart';

class RegisterPage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const RegisterPage({super.key, required this.onNavigate});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _middle = TextEditingController();
  final _contact = TextEditingController();
  final _age = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _auth = AuthService();

  bool _human = false;
  bool _humanError = false;
  bool _consent = false;
  bool _consentError = false;
  bool _loading = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _first,
      _last,
      _middle,
      _contact,
      _age,
      _username,
      _password,
      _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    setState(() {
      _humanError = !_human;
      _consentError = !_consent;
    });
    if (!formOk || !_human || !_consent) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final res = await _auth.register(
      RegisterData(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        middleName: _middle.text.trim(),
        contact: _contact.text.replaceAll(RegExp(r'[\s-]'), ''),
        age: int.parse(_age.text.trim()),
        username: _username.text.trim(),
        password: _password.text,
      ),
    );
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (res.ok) {
        _done = true;
      } else {
        _error = res.message;
      }
    });
  }

  Widget _nameField(
    TextEditingController c,
    String label, {
    bool required = true,
  }) {
    return TextFormField(
      controller: c,
      enabled: !_loading,
      textInputAction: TextInputAction.next,
      textCapitalization: TextCapitalization.words,
      autocorrect: false,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÀ-ÿ .'\-]")),
        LengthLimitingTextInputFormatter(40),
      ],
      decoration: InputDecoration(
        labelText: required ? label : '$label (optional)',
      ),
      validator: (v) => Validators.name(v, label: label, required: required),
    );
  }

  Widget _formBody() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Create your account',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Join DermaScreen to start screening and keep track of your results.',
            style: TextStyle(color: AppColors.muted, fontSize: 15),
          ),
          const SizedBox(height: 24),
          _Pair(
            left: _nameField(_first, 'First name'),
            right: _nameField(_last, 'Last name'),
          ),
          const SizedBox(height: 14),
          _Pair(
            left: _nameField(_middle, 'Middle name', required: false),
            right: TextFormField(
              controller: _age,
              enabled: !_loading,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              decoration: const InputDecoration(labelText: 'Age'),
              validator: Validators.age,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _contact,
            enabled: !_loading,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ \-]')),
              LengthLimitingTextInputFormatter(16),
            ],
            decoration: const InputDecoration(
              labelText: 'Contact number',
              hintText: '09XX XXX XXXX',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: Validators.contact,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _username,
            enabled: !_loading,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
              LengthLimitingTextInputFormatter(20),
            ],
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            validator: Validators.username,
          ),
          const SizedBox(height: 14),
          PasswordField(
            controller: _password,
            label: 'Password',
            enabled: !_loading,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            validator: Validators.password,
          ),
          PasswordStrengthMeter(password: _password.text),
          const SizedBox(height: 14),
          PasswordField(
            controller: _confirm,
            label: 'Confirm password',
            enabled: !_loading,
            textInputAction: TextInputAction.done,
            validator: (v) => Validators.confirm(v, _password.text),
          ),
          const SizedBox(height: 18),
          HumanCheck(
            hasError: _humanError,
            onChanged: (v) => setState(() {
              _human = v;
              if (v) _humanError = false;
            }),
          ),
          if (_humanError)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Please complete the human check',
                style: TextStyle(color: AppColors.danger, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 14),
          _Consent(
            value: _consent,
            hasError: _consentError,
            onChanged: (v) => setState(() {
              _consent = v;
              if (v) _consentError = false;
            }),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            alignment: Alignment.topCenter,
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: fade(AppColors.danger, .08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: fade(AppColors.danger, .35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.danger,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : const Text('Create account'),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Already have an account?',
                style: TextStyle(color: AppColors.muted),
              ),
              TextButton(
                onPressed: () => widget.onNavigate(1),
                child: const Text(
                  'Sign in',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _success() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fade(AppColors.success, .12),
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 48,
                color: AppColors.success,
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Account created!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'Welcome, ${_first.text.trim()}. Your account is ready. '
            'Sign in to start screening.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 15.5, height: 1.5),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => widget.onNavigate(1),
            child: const Text('Go to login'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      form: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _done
            ? KeyedSubtree(key: const ValueKey('done'), child: _success())
            : KeyedSubtree(key: const ValueKey('form'), child: _formBody()),
      ),
      panelOnLeft: false,
      asset: 'assets/images/register.jpg',
      title: 'Create your DermaScreen account',
      subtitle:
          'Register to screen common skin conditions from a photo and your '
          'symptoms.',
      icon: Icons.person_add_alt_1_rounded,
      chips: const ['Photo-based screening', 'Symptom check', 'Next-step guidance'],
    );
  }
}

/// Two fields side by side, stacked on very narrow screens.
class _Pair extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _Pair({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 14), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _Consent extends StatelessWidget {
  final bool value;
  final bool hasError;
  final ValueChanged<bool> onChanged;

  const _Consent({
    required this.value,
    required this.hasError,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onChanged(!value),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
              ),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'I agree to the collection and processing of my personal '
                    'data in line with the Data Privacy Act of 2012 (RA 10173).',
                    style: TextStyle(fontSize: 13.5, height: 1.45),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasError)
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text(
              'Please accept to continue',
              style: TextStyle(color: AppColors.danger, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

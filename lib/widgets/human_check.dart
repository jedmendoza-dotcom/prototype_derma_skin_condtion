import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

enum _Stage { idle, checking, challenge, verified }

/// "I'm not a robot" box: tick it, then solve a quick random sum.
///
/// NOTE: this only stops casual misuse of the UI. Real bot protection must be
/// verified on the server (Cloudflare Turnstile / hCaptcha / reCAPTCHA).
class HumanCheck extends StatefulWidget {
  final ValueChanged<bool> onChanged;
  final bool hasError;

  const HumanCheck({super.key, required this.onChanged, this.hasError = false});

  @override
  State<HumanCheck> createState() => _HumanCheckState();
}

class _HumanCheckState extends State<HumanCheck> {
  final _rng = Random.secure();
  final _answerCtrl = TextEditingController();

  _Stage _stage = _Stage.idle;
  int _a = 0;
  int _b = 0;
  bool _plus = true;
  String? _message;

  int get _answer => _plus ? _a + _b : _a - _b;

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  void _newChallenge() {
    var a = 3 + _rng.nextInt(10);
    var b = 2 + _rng.nextInt(9);
    final plus = _rng.nextBool();
    if (!plus && b > a) {
      final t = a;
      a = b;
      b = t;
    }
    _a = a;
    _b = b;
    _plus = plus;
    _answerCtrl.clear();
  }

  Future<void> _start() async {
    if (_stage != _Stage.idle) return;
    setState(() {
      _stage = _Stage.checking;
      _message = null;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _newChallenge();
    setState(() => _stage = _Stage.challenge);
  }

  void _verify() {
    if (int.tryParse(_answerCtrl.text.trim()) == _answer) {
      setState(() {
        _stage = _Stage.verified;
        _message = null;
      });
      widget.onChanged(true);
    } else {
      setState(() {
        _message = 'Not quite. Here is a new one.';
        _newChallenge();
      });
    }
  }

  Widget _leading() {
    switch (_stage) {
      case _Stage.idle:
        return InkWell(
          onTap: _start,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.muted, width: 1.8),
            ),
          ),
        );
      case _Stage.checking:
        return const SizedBox(
          width: 26,
          height: 26,
          child: Padding(
            padding: EdgeInsets.all(3),
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        );
      case _Stage.challenge:
        return Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary, width: 1.8),
          ),
        );
      case _Stage.verified:
        return const Icon(
          Icons.check_circle_rounded,
          color: AppColors.success,
          size: 28,
        );
    }
  }

  String get _label {
    switch (_stage) {
      case _Stage.idle:
        return "I'm not a robot";
      case _Stage.checking:
        return 'Checking...';
      case _Stage.challenge:
        return 'Prove you are human';
      case _Stage.verified:
        return 'Verified. You are human';
    }
  }

  Widget _challengeBody() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'What is $_a ${_plus ? '+' : '-'} $_b ?',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _answerCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  onSubmitted: (_) => _verify(),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _verify,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(84, 44),
                  textStyle:
                      const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                child: const Text('Verify'),
              ),
            ],
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verified = _stage == _Stage.verified;
    final borderColor = widget.hasError && !verified
        ? AppColors.danger
        : (verified ? AppColors.success : AppColors.line);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: widget.hasError && !verified ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _leading(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                  ),
                ),
              ),
              const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
                  SizedBox(height: 2),
                  Text(
                    'Human check',
                    style: TextStyle(fontSize: 10, color: AppColors.muted),
                  ),
                ],
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _stage == _Stage.challenge
                ? _challengeBody()
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

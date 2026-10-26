import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/skin_conditions.dart';
import '../widgets/fade_in_up.dart';
import '../widgets/smart_image.dart';

class HomePage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  final String? username;

  const HomePage({super.key, required this.onNavigate, this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _conditionsKey = GlobalKey();

  void _learnMore() {
    final ctx = _conditionsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
    );
  }

  void _startScreening() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('The screening module is coming soon.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(top: barInset(context)),
      child: Column(
        children: [
          _Section(
            child: _Hero(
              username: widget.username,
              onRegister: () => widget.onNavigate(2),
              onLearn: _learnMore,
              onStart: _startScreening,
            ),
          ),
          const _Section(child: _HowItWorks()),
          _Section(key: _conditionsKey, child: const _Conditions()),
          const _Section(child: _Disclaimer()),
          const _Footer(),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final Widget child;
  const _Section({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
          child: child,
        ),
      ),
    );
  }
}

// ───────────────────────── HERO ─────────────────────────

class _Hero extends StatelessWidget {
  final String? username;
  final VoidCallback onRegister;
  final VoidCallback onLearn;
  final VoidCallback onStart;

  const _Hero({
    required this.username,
    required this.onRegister,
    required this.onLearn,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final text = _HeroText(
          wide: wide,
          username: username,
          onRegister: onRegister,
          onLearn: onLearn,
          onStart: onStart,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 11, child: FadeInUp(child: text)),
              const SizedBox(width: 48),
              const Expanded(flex: 10, child: _HeroVisual()),
            ],
          );
        }
        return Column(
          children: [
            FadeInUp(child: text),
            const SizedBox(height: 32),
            const _HeroVisual(),
          ],
        );
      },
    );
  }
}

class _HeroText extends StatelessWidget {
  final bool wide;
  final String? username;
  final VoidCallback onRegister;
  final VoidCallback onLearn;
  final VoidCallback onStart;

  const _HeroText({
    required this.wide,
    required this.username,
    required this.onRegister,
    required this.onLearn,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final loggedIn = username != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: fade(AppColors.primary, .09),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                loggedIn ? 'Signed in as $username' : 'AI-powered skin screening',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: wide ? 56 : 36,
              fontWeight: FontWeight.w800,
              height: 1.08,
              letterSpacing: -1.2,
              color: AppColors.ink,
            ),
            children: const [
              TextSpan(text: 'Know your skin.\n'),
              TextSpan(
                text: 'Catch concerns early.',
                style: TextStyle(color: AppColors.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'DermaScreen helps you check common skin conditions from a photo and '
          'your reported symptoms, then guides you on what to do next.',
          style: TextStyle(fontSize: 17, height: 1.6, color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: loggedIn ? onStart : onRegister,
              icon: Icon(
                loggedIn ? Icons.document_scanner_outlined : Icons.arrow_forward_rounded,
                size: 20,
              ),
              label: Text(loggedIn ? 'Start screening' : 'Get started'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onLearn,
              icon: const Icon(Icons.expand_more_rounded, size: 22),
              label: const Text('Learn about conditions'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            _Tick('Photo & symptom based'),
            _Tick('Quick results'),
            _Tick('Next-step guidance'),
          ],
        ),
      ],
    );
  }
}

class _Tick extends StatelessWidget {
  final String text;
  const _Tick(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ],
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual();

  @override
  Widget build(BuildContext context) {
    return FadeInUp(
      delay: const Duration(milliseconds: 150),
      child: Container(
        height: 400,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: fade(AppColors.primary, .22),
              blurRadius: 50,
              offset: const Offset(0, 26),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SmartImage(
                asset: 'assets/images/hero.jpg',
                fallback: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primaryDark,
                        AppColors.primary,
                        AppColors.accent,
                      ],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.health_and_safety_rounded,
                      size: 150,
                      color: fade(Colors.white, .9),
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 20,
                bottom: 24,
                child: _FloatChip(
                  icon: Icons.document_scanner_outlined,
                  title: 'AI image analysis',
                  sub: 'Skin photo screening',
                ),
              ),
              const Positioned(
                right: 20,
                top: 24,
                child: _FloatChip(
                  icon: Icons.medical_services_outlined,
                  title: 'Guided next steps',
                  sub: 'Know when to see a doctor',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;

  const _FloatChip({required this.icon, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
      decoration: BoxDecoration(
        color: fade(Colors.white, .94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: fade(Colors.black, .12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: fade(AppColors.primary, .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              Text(
                sub,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── SHARED TITLE ─────────────────────────

class _SectionTitle extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;

  const _SectionTitle({required this.eyebrow, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final small = MediaQuery.of(context).size.width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: small ? 26 : 36,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -.6,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 16.5,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── HOW IT WORKS ─────────────────────────

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = [
    (
      Icons.photo_camera_outlined,
      'Upload a photo',
      'Take or upload a clear photo of the affected skin area.',
    ),
    (
      Icons.checklist_rtl_rounded,
      'Report your symptoms',
      'Tell us about itching, pain, how long it has been there and more.',
    ),
    (
      Icons.fact_check_outlined,
      'Get screening results',
      'See a likely condition screening with guidance on what to do next.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(eyebrow: 'How it works', title: 'Three simple steps'),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 800;
            final cards = [
              for (var i = 0; i < _steps.length; i++)
                FadeInUp(
                  delay: Duration(milliseconds: 100 * i),
                  child: _StepCard(
                    number: '0${i + 1}',
                    icon: _steps[i].$1,
                    title: _steps[i].$2,
                    text: _steps[i].$3,
                  ),
                ),
            ];
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 20),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  cards[i],
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String text;

  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: fade(AppColors.primary, .06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.accent],
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 26),
              ),
              const Spacer(),
              Text(
                number,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: fade(AppColors.primary, .15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 15, height: 1.55, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── CONDITIONS ─────────────────────────

class _Conditions extends StatelessWidget {
  const _Conditions();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          eyebrow: 'Know the signs',
          title: 'Common skin conditions in the Philippines',
          subtitle:
              'The warm, humid weather, strong sun and crowded living spaces '
              'make several skin conditions especially common. Here are a few '
              'you may come across.',
        ),
        const SizedBox(height: 30),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 640 ? 2 : 1);
            const gap = 22.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (var i = 0; i < kSkinConditions.length; i++)
                  SizedBox(
                    width: w,
                    child: FadeInUp(
                      delay: Duration(milliseconds: 80 * i),
                      child: _ConditionCard(condition: kSkinConditions[i]),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ConditionCard extends StatefulWidget {
  final SkinCondition condition;
  const _ConditionCard({required this.condition});

  @override
  State<_ConditionCard> createState() => _ConditionCardState();
}

class _ConditionCardState extends State<_ConditionCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.condition;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -6 : 0, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: fade(AppColors.primary, _hover ? .18 : .07),
              blurRadius: _hover ? 36 : 20,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 176,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SmartImage(
                    asset: c.imageAsset,
                    fallback: _ImageFallback(icon: c.icon, tint: c.tint),
                  ),
                  Positioned(
                    left: 14,
                    top: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: fade(Colors.white, .92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        c.category,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color.lerp(c.tint, Colors.black, .25),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    c.summary,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.55,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'COMMON SIGNS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in c.signs)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: fade(c.tint, .12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            s,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
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

class _ImageFallback extends StatelessWidget {
  final IconData icon;
  final Color tint;
  const _ImageFallback({required this.icon, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint, Color.lerp(tint, Colors.black, .22)!],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 64, color: fade(Colors.white, .92)),
      ),
    );
  }
}

// ───────────────────────── DISCLAIMER + FOOTER ─────────────────────────

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: fade(AppColors.primary, .07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: fade(AppColors.primary, .20)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 28),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'DermaScreen is a screening tool, not a medical diagnosis. Its '
              'results should never replace the advice of a licensed '
              'dermatologist or physician. If a skin problem is spreading, '
              'painful, bleeding or not healing, please see a doctor.',
              style: TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: Text(
        '© 2026 DermaScreen · ML-based skin condition screening',
        textAlign: TextAlign.center,
        style: TextStyle(color: fade(AppColors.muted, .9), fontSize: 13.5),
      ),
    );
  }
}

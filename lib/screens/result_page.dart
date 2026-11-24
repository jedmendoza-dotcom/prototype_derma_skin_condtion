import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../data/scan_options.dart';
import '../services/result_service.dart';

/// Shows the screening result: the most likely conditions, a short description of each,
/// when to see a doctor, and a "More details" link to a trusted page.
class ResultPage extends StatefulWidget {
  final int scanId;
  final String baseUrl;
  final Future<String?> Function() getToken;
  const ResultPage({super.key, required this.scanId, required this.baseUrl, required this.getToken});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  late final _service = ResultService(baseUrl: widget.baseUrl, getToken: widget.getToken);
  ScreeningResult? _r;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final f = await _service.fetch(widget.scanId);
    if (!mounted) return;
    setState(() {
      _r = f.result;
      _error = f.error;
      _loading = false;
    });
  }

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    }
  }

  Widget _card(Widget child, {Color? border, Color? fill}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: fill ?? Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border ?? AppColors.line),
        ),
        child: child,
      );

  String _level(double c) => c >= 0.6 ? 'Strong match' : (c >= 0.4 ? 'Possible match' : 'Weak match');

  Widget _condition(ConditionResult c, {required bool top}) {
    final g = c.guidance;
    return _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(c.name,
                  style: TextStyle(fontSize: top ? 20 : 17, fontWeight: FontWeight.w800, color: AppColors.ink))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Text('${(c.confidence * 100).round()}%  ${_level(c.confidence)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(c.category, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 10),
        Text(c.description, style: const TextStyle(height: 1.5)),
        if (c.commonSigns.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(c.matchedSigns.isEmpty ? 'Typical signs' : 'Typical signs (green = matches what you wrote)',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          Wrap(
              spacing: 6,
              runSpacing: 6,
              children: c.commonSigns
                  .map((s) {
                final hit = c.matchedSigns.contains(s);
                return Chip(
                  avatar: hit ? const Icon(Icons.check_circle, size: 16, color: AppColors.success) : null,
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: hit ? AppColors.success.withOpacity(0.12) : null,
                );
              })
                  .toList()),
        ],
        if (top && g != null) ...[
          const Divider(height: 24),
          if ((g.advice ?? '').isNotEmpty) ...[
            const Text('What you can do', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(g.advice!, style: const TextStyle(height: 1.5)),
          ],
          if ((g.seeDoctorWhen ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('See a doctor if', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(g.seeDoctorWhen!, style: const TextStyle(height: 1.5)),
          ],
        ],
        if (c.moreDetailsUrl != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _open(c.moreDetailsUrl!),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text('More details${c.moreDetailsSource != null ? ' (${c.moreDetailsSource})' : ''}'),
          ),
        ],
      ]),
      border: top ? AppColors.primary : null,
    );
  }

  /// Turns a stored code (like '1_2w') into the words the user picked ('1 to 2 weeks').
  String _label(List<ChoiceOption> options, String code) {
    for (final o in options) {
      if (o.code == code) return o.label;
    }
    return code;
  }

  Widget _answersCard(YourAnswers a) {
    Widget row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(color: AppColors.muted))),
          Expanded(child: Text(v)),
        ]));
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('What you told us', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      row('Age', _label(kAgeGroups, a.ageGroup)),
      row('How long', _label(kDurations, a.durationRange)),
      row('Itch', a.itchScore == 0 ? 'None' : '${a.itchScore} out of 10'),
      row('Swelling', a.hasSwelling ? 'Yes' : 'No'),
      row('Allergies', a.hasAllergy ? (a.allergyDetails ?? 'Yes') : 'No'),
      row('Description', a.description),
    ]));
  }

  Widget _body(ScreeningResult r) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _card(
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(r.disclaimer, style: const TextStyle(height: 1.5))),
        ]),
        fill: const Color(0xFFFFF8E6),
        border: AppColors.warning,
      ),
      if (r.answers != null) _answersCard(r.answers!),
      for (final n in r.notes)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(n, style: const TextStyle(color: AppColors.muted, height: 1.4))),
      if (r.inconclusive)
        _card(
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No clear match', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text('We could not match your answers and photo to one condition with enough certainty. '
                'The conditions below are only possibilities. Please see a doctor or health worker.',
                style: TextStyle(height: 1.5)),
          ]),
          border: AppColors.danger,
        )
      else
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Most likely', style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w700)),
        ),
      for (var i = 0; i < r.conditions.length; i++) ...[
        if (i == 1)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Other possibilities',
                style: TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w700)),
          ),
        _condition(r.conditions[i], top: i == 0 && !r.inconclusive),
      ],
      _card(
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('See a doctor right away if', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final f in r.redFlags)
            Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  '),
                  Expanded(child: Text(f, style: const TextStyle(height: 1.4))),
                ])),
        ]),
        border: AppColors.danger,
      ),
      Text('Reference no. ${r.scanId}', textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Your screening result')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _load, child: const Text('Try again')),
                    ]),
                  ),
                )
              : _body(_r!),
    );
  }
}
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme.dart';
import '../data/scan_options.dart';
import '../services/scan_service.dart';
import 'history_page.dart';
import 'result_page.dart';

enum _Step { form, photo, done }

final RegExp _phoneRule = RegExp(r'^(09\d{9}|\+639\d{9})$');

String? _contactError(String? v) {
  final t = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
  if (t.isEmpty) return 'Contact number is required';
  if (!_phoneRule.hasMatch(t)) return 'Use 09XXXXXXXXX or +639XXXXXXXXX';
  return null;
}

String? _descriptionError(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Please describe what you feel';
  if (t.length < 10) return 'Please write a little more (at least 10 characters)';
  return null;
}

/// The screening flow:
///   step 1  symptom form (every answer is required)
///   step 2  photo (checked for quality; retake once, then description only)
///   step 3  confirmation
///
/// Open it from your signed-in home screen:
///   Navigator.of(context).push(MaterialPageRoute(
///     builder: (_) => ScanPage(
///         baseUrl: AuthService.baseUrl, getToken: AuthService.getAccessToken)));
class ScanPage extends StatefulWidget {
  final String baseUrl;
  final Future<String?> Function() getToken;

  const ScanPage({super.key, required this.baseUrl, required this.getToken});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  late final ScanService _service =
      ScanService(baseUrl: widget.baseUrl, getToken: widget.getToken);
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _allergyCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _contactCtl = TextEditingController();

  _Step _step = _Step.form;

  // step 1 answers
  String? _age;
  String? _duration;
  int? _itch;
  bool? _swelling;
  bool? _allergy;
  List<String> _problems = [];

  // step 2 photo
  Uint8List? _photo;
  String _photoName = 'photo.jpg';
  PhotoCheck? _check;
  bool _checking = false;
  bool _submitting = false;
  int _retakes = 0;

  // step 3
  ScanSubmitResult? _result;

  @override
  void dispose() {
    _scroll.dispose();
    _allergyCtl.dispose();
    _descCtl.dispose();
    _contactCtl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- helpers

  void _scrollTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Names of every answer that is still missing or wrong.
  List<String> _missingAnswers() {
    final m = <String>[];
    if (_age == null) m.add('Age');
    if (_duration == null) m.add('How long you have had it');
    if (_itch == null) m.add('Itch rating');
    if (_swelling == null) m.add('Swelling');
    if (_allergy == null) {
      m.add('Allergies');
    } else if (_allergy == true && _allergyCtl.text.trim().isEmpty) {
      m.add('What you are allergic to');
    }
    if (_descriptionError(_descCtl.text) != null) m.add('Description');
    if (_contactError(_contactCtl.text) != null) m.add('Contact number');
    return m;
  }

  void _goToPhoto() {
    final fieldsOk = _formKey.currentState?.validate() ?? true; // paints the red errors
    final missing = _missingAnswers();
    if (!fieldsOk || missing.isNotEmpty) {
      setState(() => _problems = missing);
      _scrollTop();
      return;
    }
    setState(() {
      _problems = [];
      _step = _Step.photo;
    });
    _scrollTop();
  }

  // ------------------------------------------------------------------ photo

  Future<void> _pick(ImageSource source) async {
    try {
      final XFile? f =
          await _picker.pickImage(source: source, maxWidth: 2048, imageQuality: 90);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() {
        if (_photo != null) _retakes = _retakes < 5 ? _retakes + 1 : 5;
        _photo = bytes;
        _photoName = f.name.isEmpty ? 'photo.jpg' : f.name;
        _check = null;
      });
      await _runCheck();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _check = const PhotoCheck.failed(
            'Could not open the camera or gallery. Please allow access and try again.');
      });
    }
  }

  Future<void> _runCheck() async {
    final bytes = _photo;
    if (bytes == null) return;
    setState(() => _checking = true);
    final r = await _service.checkPhoto(bytes, _photoName);
    if (!mounted) return;
    setState(() {
      _check = r;
      _checking = false;
    });
  }

  Future<void> _submit() async {
    final bytes = _photo;
    if (bytes == null) return;
    setState(() => _submitting = true);

    final form = ScanForm(
      ageGroup: _age!,
      durationRange: _duration!,
      itchScore: _itch!,
      hasSwelling: _swelling!,
      hasAllergy: _allergy!,
      allergyDetails: _allergyCtl.text,
      description: _descCtl.text,
      contactNumber: _contactCtl.text,
    );
    final r = await _service.submit(form, bytes, _photoName, retakeCount: _retakes);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (r.ok) {
      setState(() {
        _result = r;
        _step = _Step.done;
      });
      _scrollTop();
      return;
    }
    if (r.retakeRequired) {
      setState(() => _check = PhotoCheck(ok: false, message: r.message));
      return;
    }
    if (r.fieldErrors.isNotEmpty) {
      setState(() {
        _problems = r.fieldErrors.entries
            .map((e) => '${kFieldLabels[e.key] ?? e.key}: ${e.value}')
            .toList();
        _step = _Step.form;
      });
      _scrollTop();
      return;
    }
    _toast(r.message ?? 'Something went wrong. Please try again.');
  }

  // ---------------------------------------------------------------- widgets

  Widget _card({required Widget child, bool error = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: error ? AppColors.danger : AppColors.line,
          width: error ? 1.6 : 1,
        ),
      ),
      child: child,
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: text,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner({
    required Color color,
    required IconData icon,
    required String title,
    String? body,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fade(color, .10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fade(color, .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (body != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(body, style: const TextStyle(height: 1.4)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A required question shown as a card. The card turns red and shows
  /// [requiredMsg] when the user tries to continue without answering.
  Widget _fieldCard<T>({
    required String label,
    required T? value,
    required String requiredMsg,
    required Widget Function(FormFieldState<T> state) body,
    Widget? extra,
  }) {
    return FormField<T>(
      initialValue: value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (_) => value == null ? requiredMsg : null,
      builder: (state) {
        return _card(
          error: state.hasError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(label),
              body(state),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.errorText ?? requiredMsg,
                    style: const TextStyle(color: AppColors.danger, fontSize: 12.5),
                  ),
                ),
              if (extra != null) extra,
            ],
          ),
        );
      },
    );
  }

  Widget _dropdown(String? value, List<ChoiceOption> options, ValueChanged<String> onChanged) {
    return InputDecorator(
      decoration: const InputDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          hint: const Text('Select one'),
          items: [
            for (final o in options) DropdownMenuItem<String>(value: o.code, child: Text(o.label)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _yesNo(bool? value, ValueChanged<bool> onChanged) {
    return Wrap(
      spacing: 10,
      children: [
        ChoiceChip(label: const Text('Yes'), selected: value == true, onSelected: (_) => onChanged(true)),
        ChoiceChip(label: const Text('No'), selected: value == false, onSelected: (_) => onChanged(false)),
      ],
    );
  }

  // ------------------------------------------------------------ step 1: form

  List<Widget> _formStep() {
    return [
      if (_problems.isNotEmpty)
        _banner(
          color: AppColors.danger,
          icon: Icons.error_outline,
          title: 'Please answer everything marked with *',
          body: 'Still needed: ${_problems.join(', ')}',
        ),
      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fieldCard<String>(
              label: 'Age of the person with the skin problem',
              value: _age,
              requiredMsg: 'Please select an age group',
              body: (s) => _dropdown(_age, kAgeGroups, (v) {
                setState(() => _age = v);
                s.didChange(v);
              }),
            ),
            _fieldCard<String>(
              label: 'How long have you had this skin problem?',
              value: _duration,
              requiredMsg: 'Please select how long',
              body: (s) => _dropdown(_duration, kDurations, (v) {
                setState(() => _duration = v);
                s.didChange(v);
              }),
            ),
            _fieldCard<int>(
              label: 'How itchy is it? (1 = very mild, 10 = unbearable)',
              value: _itch,
              requiredMsg: 'Please rate the itching',
              body: (s) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (var i = 0; i <= 10; i++)
                        ChoiceChip(
                          label: Text(i == 0 ? 'None' : '$i'),
                          selected: _itch == i,
                          onSelected: (_) {
                            setState(() => _itch = i);
                            s.didChange(i);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _itch == null
                        ? 'Tap a number. Choose "None" if it does not itch.'
                        : '$_itch: ${itchWord(_itch!)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            _fieldCard<bool>(
              label: 'Is the skin swollen?',
              value: _swelling,
              requiredMsg: 'Please choose Yes or No',
              body: (s) => _yesNo(_swelling, (v) {
                setState(() => _swelling = v);
                s.didChange(v);
              }),
            ),
            _fieldCard<bool>(
              label: 'Do you have any allergies? (food, medicine, soap, insect bites...)',
              value: _allergy,
              requiredMsg: 'Please choose Yes or No',
              body: (s) => _yesNo(_allergy, (v) {
                setState(() => _allergy = v);
                s.didChange(v);
              }),
              extra: _allergy == true
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: _allergyCtl,
                        maxLength: 200,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: const InputDecoration(labelText: 'What are you allergic to? *'),
                        validator: (v) => (_allergy == true && (v ?? '').trim().isEmpty)
                            ? 'Please say what you are allergic to'
                            : null,
                      ),
                    )
                  : null,
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Describe what you feel in your own words'),
                  TextFormField(
                    controller: _descCtl,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 1000,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      hintText: 'Example: red, itchy patches on my arm. It gets worse at night.',
                    ),
                    validator: _descriptionError,
                  ),
                ],
              ),
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Your contact number'),
                  TextFormField(
                    controller: _contactCtl,
                    keyboardType: TextInputType.phone,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.phone_outlined),
                      hintText: '09XXXXXXXXX',
                    ),
                    validator: _contactError,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text('* required', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ),
      FilledButton.icon(
        onPressed: _goToPhoto,
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Next: take a photo'),
      ),
    ];
  }

  // ------------------------------------------------------------ step 2: photo

  List<Widget> _photoStep() {
    final check = _check;
    final limit = check?.retakesBeforeFallback ?? 1;
    final checkFailed = check != null && check.error != null;
    final poor = check != null && !check.ok && !checkFailed;
    final mustRetake = poor && _retakes < limit;
    final canFallback = poor && _retakes >= limit;
    final good = check != null && check.ok;
    final canSubmit = (good || canFallback) && !_checking && !_submitting;

    return [
      if (_photo == null)
        _card(
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Take a clear photo of the skin problem',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              SizedBox(height: 10),
              Text('- Use daylight or a bright room, no flash.\n'
                  '- Hold the phone steady and tap the skin to focus.\n'
                  '- Fill the picture with the affected area, about 10-15 cm away.\n'
                  '- Do not include your face unless the problem is on your face.',
                  style: TextStyle(height: 1.6)),
            ],
          ),
        ),
      if (_photo != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 260,
              child: Image.memory(_photo!, fit: BoxFit.cover),
            ),
          ),
        ),
      if (_checking)
        _card(
          child: const Column(
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 10),
              Text('Checking the photo quality...'),
            ],
          ),
        ),
      if (checkFailed)
        _banner(
          color: AppColors.warning,
          icon: Icons.wifi_off,
          title: 'Could not check the photo',
          body: check!.error,
        ),
      if (good)
        _banner(
          color: AppColors.success,
          icon: Icons.check_circle_outline,
          title: 'The photo looks good',
          body: 'It will be used together with your answers.',
        ),
      if (mustRetake)
        _banner(
          color: AppColors.warning,
          icon: Icons.camera_alt_outlined,
          title: 'Please retake the photo',
          body: check!.message,
        ),
      if (canFallback)
        _banner(
          color: AppColors.primary,
          icon: Icons.info_outline,
          title: 'We still cannot see this photo clearly',
          body: 'You can try one more photo, or continue with your description only. '
              'Your result will be less certain, so please see a doctor if you are worried.',
        ),
      if (_photo == null || mustRetake)
        FilledButton.icon(
          onPressed: () => _pick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera),
          label: Text(_photo == null ? 'Take photo' : 'Retake photo'),
        )
      else
        OutlinedButton.icon(
          onPressed: () => _pick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Retake photo'),
        ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => _pick(ImageSource.gallery),
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Choose from gallery'),
      ),
      if (checkFailed && _photo != null) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _runCheck,
          icon: const Icon(Icons.refresh),
          label: const Text('Check the photo again'),
        ),
      ],
      const SizedBox(height: 18),
      FilledButton(
        onPressed: canSubmit ? _submit : null,
        child: _submitting
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Text(canFallback ? 'Continue with description only' : 'Submit screening'),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: _submitting ? null : () => setState(() => _step = _Step.form),
        child: const Text('Back to my answers'),
      ),
    ];
  }

  // ----------------------------------------------------------- step 3: done

  List<Widget> _doneStep() {
    final r = _result;
    return [
      _card(
        child: Column(
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.check_circle, size: 64, color: AppColors.success),
            const SizedBox(height: 12),
            const Text('Screening received',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(r?.message ?? '', textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
            if (r?.scanId != null) ...[
              const SizedBox(height: 8),
              Text('Reference no. ${r!.scanId}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ],
            const SizedBox(height: 14),
            const Text(
              'This is a screening, not a diagnosis. If the problem gets worse or you '
              'are worried, please see a doctor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            if (r?.scanId != null) ...[
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ResultPage(
                      scanId: r!.scanId!, baseUrl: widget.baseUrl, getToken: widget.getToken),
                )),
                icon: const Icon(Icons.assignment_turned_in_outlined),
                label: const Text('View result'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => HistoryPage(baseUrl: widget.baseUrl, getToken: widget.getToken),
              )),
              child: const Text('My results and history'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    ];
  }

  // ------------------------------------------------------------------- build

  Widget _progress() {
    final index = _step == _Step.form ? 0 : 1;
    const titles = ['Your symptoms', 'Photo'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 2; i++)
              Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: i == 0 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: i <= index ? AppColors.primary : AppColors.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Step ${index + 1} of 2: ${titles[index]}',
            style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> content;
    switch (_step) {
      case _Step.form:
        content = _formStep();
        break;
      case _Step.photo:
        content = _photoStep();
        break;
      case _Step.done:
        content = _doneStep();
        break;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Skin screening'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step != _Step.done) _progress(),
                  ...content,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
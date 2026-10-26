class Validators {
  static final RegExp _name = RegExp(r"^[A-Za-zÀ-ÿñÑ][A-Za-zÀ-ÿñÑ .'\-]*$");
  static final RegExp _phone = RegExp(r'^(09\d{9}|\+639\d{9})$');
  static final RegExp _username = RegExp(r'^[A-Za-z0-9_]{4,20}$');

  static String? name(String? v, {required String label, bool required = true}) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return required ? '$label is required' : null;
    if (required && t.length < 2) return '$label is too short';
    if (t.length > 40) return '$label is too long';
    if (!_name.hasMatch(t)) return 'Letters only, please';
    return null;
  }

  static String? contact(String? v) {
    final t = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (t.isEmpty) return 'Contact number is required';
    if (!_phone.hasMatch(t)) return 'Use 09XXXXXXXXX or +639XXXXXXXXX';
    return null;
  }

  static String? age(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Age is required';
    final n = int.tryParse(t);
    if (n == null) return 'Numbers only';
    if (n < 1 || n > 120) return 'Enter a valid age (1-120)';
    return null;
  }

  static String? username(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Username is required';
    if (!_username.hasMatch(t)) {
      return '4-20 characters: letters, numbers, underscore';
    }
    return null;
  }

  /// 0-4: length, upper+lower, number, symbol.
  static int passwordScore(String p) {
    var s = 0;
    if (p.length >= 8) s++;
    if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p)) s++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s;
  }

  static String? password(String? v) {
    final p = v ?? '';
    if (p.isEmpty) return 'Password is required';
    if (p.length < 8) return 'At least 8 characters';
    if (p.length > 64) return 'Maximum 64 characters';
    if (passwordScore(p) < 4) {
      return 'Mix upper & lower case, a number and a symbol';
    }
    return null;
  }

  static String? confirm(String? v, String original) {
    if ((v ?? '').isEmpty) return 'Please confirm your password';
    if (v != original) return 'Passwords do not match';
    return null;
  }
}

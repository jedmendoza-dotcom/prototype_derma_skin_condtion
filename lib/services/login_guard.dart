import 'package:shared_preferences/shared_preferences.dart';

class FailureResult {
  final int attemptsLeft;
  final DateTime? lockedUntil;
  const FailureResult(this.attemptsLeft, this.lockedUntil);
}

/// Counts failed sign-ins and enforces a cooldown after too many.
///
/// NOTE: this runs on the device, so it protects the UI only. The real
/// protection has to be repeated in the FastAPI backend (see SETUP.md).
class LoginGuard {
  static const int maxAttempts = 5;
  static const Duration cooldown = Duration(minutes: 3);

  static const _kFails = 'login_fail_count';
  static const _kLockUntil = 'login_lock_until';

  /// Returns the time the lock ends, or null when not locked.
  /// Also clears an expired lock and resets the counter.
  Future<DateTime?> activeLock() async {
    final p = await SharedPreferences.getInstance();
    final until = p.getInt(_kLockUntil) ?? 0;
    if (until == 0) return null;
    final t = DateTime.fromMillisecondsSinceEpoch(until);
    if (t.isAfter(DateTime.now())) return t;
    await p.remove(_kLockUntil);
    await p.setInt(_kFails, 0);
    return null;
  }

  Future<FailureResult> registerFailure() async {
    final p = await SharedPreferences.getInstance();
    final fails = (p.getInt(_kFails) ?? 0) + 1;
    await p.setInt(_kFails, fails);
    if (fails >= maxAttempts) {
      final until = DateTime.now().add(cooldown);
      await p.setInt(_kLockUntil, until.millisecondsSinceEpoch);
      return FailureResult(0, until);
    }
    return FailureResult(maxAttempts - fails, null);
  }

  Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kFails);
    await p.remove(_kLockUntil);
  }
}

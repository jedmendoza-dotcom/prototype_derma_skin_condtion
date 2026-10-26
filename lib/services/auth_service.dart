import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class RegisterData {
  final String firstName;
  final String lastName;
  final String middleName;
  final String contact;
  final int age;
  final String username;
  final String password;

  const RegisterData({
    required this.firstName,
    required this.lastName,
    required this.middleName,
    required this.contact,
    required this.age,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'middle_name': middleName,
        'contact_number': contact,
        'age': age,
        'username': username,
        'password': password,
      };
}

class AuthResult {
  final bool ok;
  final String? message;
  final String? username;

  /// True when the failure was not a wrong password (server down, rate
  /// limited...). These must not count toward the 5-attempt lockout.
  final bool networkError;

  const AuthResult.success(this.username)
      : ok = true,
        message = null,
        networkError = false;

  const AuthResult.failure(this.message, {this.networkError = false})
      : ok = false,
        username = null;
}

class AuthService {
  /// true  = fake in-memory accounts so you can test the UI now
  ///         (demo account: demo / Demo@1234)
  /// false = call your FastAPI backend at [baseUrl]
  static const bool useMock = true;

  static String get baseUrl =>
      kIsWeb ? 'http://localhost:8000' : 'http://10.0.2.2:8000'; // 10.0.2.2 = Android emulator

  static const _storage = FlutterSecureStorage();
  static const _kUser = 'session_user';
  static const _kToken = 'session_token';
  static const _kExpiry = 'session_expiry';

  static final Map<String, String> _mockUsers = {'demo': 'Demo@1234'};

  Future<AuthResult> login(String username, String password,
      {required bool remember}) async {
    String token;

    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 700));
      final stored = _mockUsers[username.toLowerCase()];
      if (stored == null || stored != password) {
        return const AuthResult.failure('Incorrect username or password.');
      }
      token = 'mock-token';
    } else {
      try {
        final res = await http
            .post(
              Uri.parse('$baseUrl/auth/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'username': username, 'password': password}),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          token = (jsonDecode(res.body)['access_token'] ?? '').toString();
        } else if (res.statusCode == 400 ||
            res.statusCode == 401 ||
            res.statusCode == 403) {
          return const AuthResult.failure('Incorrect username or password.');
        } else if (res.statusCode == 429) {
          return const AuthResult.failure(
              'Too many attempts. Please wait and try again.',
              networkError: true);
        } else {
          return AuthResult.failure('Server error (${res.statusCode}).',
              networkError: true);
        }
      } catch (_) {
        return const AuthResult.failure(
            'Cannot reach the server. Check your connection.',
            networkError: true);
      }
    }

    if (remember) {
      final expiry = DateTime.now().add(const Duration(days: 7));
      await _storage.write(key: _kUser, value: username);
      await _storage.write(key: _kToken, value: token);
      await _storage.write(
          key: _kExpiry, value: expiry.millisecondsSinceEpoch.toString());
    } else {
      await _clearStored();
    }
    return AuthResult.success(username);
  }

  Future<AuthResult> register(RegisterData d) async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 800));
      final key = d.username.toLowerCase();
      if (_mockUsers.containsKey(key)) {
        return const AuthResult.failure('That username is already taken.');
      }
      _mockUsers[key] = d.password;
      return AuthResult.success(d.username);
    }

    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(d.toJson()),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 || res.statusCode == 201) {
        return AuthResult.success(d.username);
      }
      if (res.statusCode == 409) {
        return const AuthResult.failure('That username is already taken.');
      }
      if (res.statusCode == 422) {
        return const AuthResult.failure('Please check your details and try again.');
      }
      return AuthResult.failure('Server error (${res.statusCode}).');
    } catch (_) {
      return const AuthResult.failure(
          'Cannot reach the server. Check your connection.');
    }
  }

  /// Returns the username if a "remember me" session is still valid.
  Future<String?> restoreSession() async {
    try {
      final user = await _storage.read(key: _kUser);
      final exp = int.tryParse(await _storage.read(key: _kExpiry) ?? '');
      if (user == null || exp == null) return null;
      if (DateTime.now().millisecondsSinceEpoch > exp) {
        await _clearStored();
        return null;
      }
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() => _clearStored();

  Future<void> _clearStored() async {
    try {
      await _storage.delete(key: _kUser);
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kExpiry);
    } catch (_) {}
  }
}

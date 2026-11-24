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
  final bool consent;

  const RegisterData({
    required this.firstName,
    required this.lastName,
    required this.middleName,
    required this.contact,
    required this.age,
    required this.username,
    required this.password,
    this.consent = true,
  });

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'middle_name': middleName,
        'contact_number': contact,
        'age': age,
        'username': username,
        'password': password,
        'consent': consent,
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
  /// false = call your FastAPI backend at [baseUrl]
  /// true  = fake in-memory accounts for offline demo testing
  static const bool useMock = false;

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    return (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)
        ? 'http://localhost:8000'
        : 'http://10.0.2.2:8000'; // 10.0.2.2 = Android emulator loopback
  }

  static const _storage = FlutterSecureStorage();
  static const _kUser = 'session_user';
  static const _kRefresh = 'session_refresh'; // the long-lived token (remember me)
  static const _kExpiry = 'session_expiry';
  static const _kOldToken = 'session_token'; // older versions of this app stored it here

  // The short-lived access token (15 minutes) lives only in memory.
  // Static, so every AuthService() in the app shares the same sign-in.
  static String? _access;
  static DateTime? _accessExpiry;
  static String? _refresh;

  static final Map<String, String> _mockUsers = {'demo': 'Demo@1234'};

  /// A valid access token for calling the API, or null if the user must sign in
  /// again. Refreshes it automatically when it is about to expire.
  /// Pass this (not a fixed string) to screens that call the API.
  static Future<String?> getAccessToken() async {
    if (useMock) return 'mock-token';

    final access = _access;
    final expiry = _accessExpiry;
    if (access != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry.subtract(const Duration(seconds: 30)))) {
      return access;
    }

    final refresh = _refresh;
    if (refresh == null) return null;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _setAccess(data['access_token'], data['expires_in']);
        return _access;
      }
      if (res.statusCode == 401) {
        await _clearStored(); // session ended or was signed out elsewhere
      }
    } catch (_) {}
    return null;
  }

  static void _setAccess(dynamic token, dynamic expiresIn) {
    _access = (token ?? '').toString();
    final secs = expiresIn is int ? expiresIn : 900;
    _accessExpiry = DateTime.now().add(Duration(seconds: secs));
  }

  Future<AuthResult> login(String username, String password,
      {required bool remember}) async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 700));
      final stored = _mockUsers[username.toLowerCase()];
      if (stored == null || stored != password) {
        return const AuthResult.failure('Incorrect username or password.');
      }
      return AuthResult.success(username);
    }

    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
              'remember_me': remember,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _setAccess(data['access_token'], data['expires_in']);
        _refresh = (data['refresh_token'] ?? '').toString();

        if (remember) {
          final expiry = DateTime.now().add(const Duration(days: 7));
          await _storage.write(key: _kUser, value: username);
          await _storage.write(key: _kRefresh, value: _refresh);
          await _storage.write(
              key: _kExpiry, value: expiry.millisecondsSinceEpoch.toString());
        } else {
          await _clearStoredOnly();
        }
        return AuthResult.success(username);
      }
      if (res.statusCode == 400 ||
          res.statusCode == 401 ||
          res.statusCode == 403) {
        return const AuthResult.failure('Incorrect username or password.');
      }
      if (res.statusCode == 423) {
        try {
          final body = jsonDecode(res.body);
          final detail = body['detail'];
          final msg = (detail is Map && detail['message'] != null)
              ? detail['message']
              : 'Too many failed attempts. Account is locked.';
          return AuthResult.failure(msg.toString());
        } catch (_) {
          return const AuthResult.failure('Account is temporarily locked.');
        }
      }
      if (res.statusCode == 429) {
        return const AuthResult.failure(
            'Too many attempts. Please wait and try again.',
            networkError: true);
      }
      if (res.statusCode == 503) {
        return const AuthResult.failure(
            'Database unavailable. Please check if PostgreSQL is running.',
            networkError: true);
      }
      return AuthResult.failure('Server error (${res.statusCode}).',
          networkError: true);
    } catch (_) {
      return const AuthResult.failure(
          'Cannot reach the server. Check your connection.',
          networkError: true);
    }
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
        try {
          final errData = jsonDecode(res.body);
          if (errData['detail'] is List &&
              (errData['detail'] as List).isNotEmpty) {
            final firstMsg = errData['detail'][0]['msg'];
            return AuthResult.failure('Validation: $firstMsg');
          }
        } catch (_) {}
        return const AuthResult.failure(
            'Please check your details and try again.');
      }
      if (res.statusCode == 503) {
        return const AuthResult.failure(
            'Database unavailable. Please check if PostgreSQL is running.');
      }
      return AuthResult.failure('Server error (${res.statusCode}).');
    } catch (_) {
      return const AuthResult.failure(
          'Cannot reach the server. Check your connection.');
    }
  }

  /// Returns the username if a "remember me" session is still valid.
  /// The access token is fetched later by [getAccessToken] when it is needed.
  Future<String?> restoreSession() async {
    try {
      final user = await _storage.read(key: _kUser);
      final refresh = await _storage.read(key: _kRefresh);
      final exp = int.tryParse(await _storage.read(key: _kExpiry) ?? '');
      if (user == null || exp == null) return null;
      if (DateTime.now().millisecondsSinceEpoch > exp) {
        await _clearStored();
        return null;
      }
      if (refresh == null || refresh.isEmpty) {
        // saved by an older version of the app: no usable token, sign in again
        await _clearStored();
        return null;
      }
      _refresh = refresh;
      return user;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    if (!useMock) {
      try {
        final token = await getAccessToken();
        if (token != null && token.isNotEmpty) {
          await http.post(
            Uri.parse('$baseUrl/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          ).timeout(const Duration(seconds: 5));
        }
      } catch (_) {}
    }
    await _clearStored();
  }

  /// Forget everything: memory and saved session.
  static Future<void> _clearStored() async {
    _access = null;
    _accessExpiry = null;
    _refresh = null;
    await _clearStoredOnly();
  }

  /// Forget only the saved ("remember me") session, keep the current sign-in.
  static Future<void> _clearStoredOnly() async {
    try {
      await _storage.delete(key: _kUser);
      await _storage.delete(key: _kRefresh);
      await _storage.delete(key: _kExpiry);
      await _storage.delete(key: _kOldToken);
    } catch (_) {}
  }
}
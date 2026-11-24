import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Everything the user fills in on the symptom form.
class ScanForm {
  final String ageGroup;
  final String durationRange;
  final int itchScore; // 0 = no itching, 1-10 = the rating
  final bool hasSwelling;
  final bool hasAllergy;
  final String allergyDetails;
  final String description;
  final String contactNumber;

  const ScanForm({
    required this.ageGroup,
    required this.durationRange,
    required this.itchScore,
    required this.hasSwelling,
    required this.hasAllergy,
    required this.allergyDetails,
    required this.description,
    required this.contactNumber,
  });
}

/// Result of checking one photo (POST /scans/check-photo).
class PhotoCheck {
  final bool ok;
  final String? message; // what to fix, in plain words
  final int retakesBeforeFallback;
  final String? error; // set when the check itself could not run (no network...)

  const PhotoCheck({
    required this.ok,
    this.message,
    this.retakesBeforeFallback = 1,
    this.error,
  });

  const PhotoCheck.failed(String reason)
      : ok = false,
        message = null,
        retakesBeforeFallback = 1,
        error = reason;
}

/// Result of saving the screening (POST /scans).
class ScanSubmitResult {
  final bool ok;
  final int? scanId;
  final bool descriptionOnly;
  final String? message;

  /// Server-side validation problems: field name -> message.
  final Map<String, String> fieldErrors;

  /// The server looked at the photo and wants a new one.
  final bool retakeRequired;

  const ScanSubmitResult({
    required this.ok,
    this.scanId,
    this.descriptionOnly = false,
    this.message,
    this.fieldErrors = const {},
    this.retakeRequired = false,
  });
}

class ScanService {
  final String baseUrl;

  /// Gives a valid access token (refreshing it when needed), or null when the
  /// user has to sign in again. Pass AuthService.getAccessToken.
  final Future<String?> Function() getToken;

  const ScanService({required this.baseUrl, required this.getToken});

  dynamic _json(http.Response res) {
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  String _plainDetail(http.Response res, String fallback) {
    final body = _json(res);
    if (body is Map && body['detail'] is String) return body['detail'] as String;
    return fallback;
  }

  /// Asks the server whether the photo is sharp, bright and big enough.
  Future<PhotoCheck> checkPhoto(Uint8List bytes, String filename) async {
    try {
      final token = await getToken();
      if (token == null) {
        return const PhotoCheck.failed('Your session expired. Please sign in again.');
      }
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/scans/check-photo'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes('photo', bytes, filename: filename));
      final res = await http.Response.fromStream(
          await req.send().timeout(const Duration(seconds: 30)));

      if (res.statusCode == 200) {
        final body = _json(res);
        if (body is Map) {
          return PhotoCheck(
            ok: body['ok'] == true,
            message: body['message'] as String?,
            retakesBeforeFallback: (body['retakes_before_fallback'] as int?) ?? 1,
          );
        }
      }
      if (res.statusCode == 401) {
        return const PhotoCheck.failed('Your session expired. Please sign in again.');
      }
      if (res.statusCode == 400) {
        return PhotoCheck.failed(_plainDetail(res, 'That file is not a valid photo.'));
      }
      return PhotoCheck.failed('Server error (${res.statusCode}). Please try again.');
    } catch (_) {
      return const PhotoCheck.failed('Cannot reach the server. Check your connection.');
    }
  }

  /// Saves the form and the photo together.
  /// [retakeCount] = how many times the user replaced a photo.
  Future<ScanSubmitResult> submit(
    ScanForm f,
    Uint8List photo,
    String filename, {
    required int retakeCount,
  }) async {
    try {
      final token = await getToken();
      if (token == null) {
        return const ScanSubmitResult(
            ok: false, message: 'Your session expired. Please sign in again.');
      }
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/scans'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields.addAll({
          'age_group': f.ageGroup,
          'duration_range': f.durationRange,
          'itch_score': f.itchScore.toString(),
          'has_swelling': f.hasSwelling.toString(),
          'has_allergy': f.hasAllergy.toString(),
          'description': f.description.trim(),
          'contact_number': f.contactNumber.trim(),
          'retake_count': retakeCount.toString(),
        })
        ..files.add(http.MultipartFile.fromBytes('photo', photo, filename: filename));
      if (f.hasAllergy) req.fields['allergy_details'] = f.allergyDetails.trim();

      final res = await http.Response.fromStream(
          await req.send().timeout(const Duration(seconds: 60)));
      final body = _json(res);

      if (res.statusCode == 201 && body is Map) {
        return ScanSubmitResult(
          ok: true,
          scanId: body['scan_id'] as int?,
          descriptionOnly: body['result_basis'] == 'description_only',
          message: body['message'] as String?,
        );
      }

      final detail = body is Map ? body['detail'] : null;

      if (res.statusCode == 422 && detail is Map && detail['code'] == 'retake_required') {
        return ScanSubmitResult(
          ok: false,
          retakeRequired: true,
          message: detail['message'] as String?,
        );
      }
      if (res.statusCode == 422 && detail is List) {
        final errors = <String, String>{};
        for (final e in detail) {
          if (e is Map) {
            final loc = e['loc'];
            final field = (loc is List && loc.isNotEmpty) ? loc.last.toString() : 'form';
            errors[field] = (e['msg'] ?? 'Please check this field').toString();
          }
        }
        return ScanSubmitResult(
          ok: false,
          fieldErrors: errors,
          message: 'Please check the highlighted answers.',
        );
      }
      if (res.statusCode == 401) {
        return const ScanSubmitResult(
            ok: false, message: 'Your session expired. Please sign in again.');
      }
      if (res.statusCode == 403) {
        return ScanSubmitResult(
            ok: false, message: _plainDetail(res, 'This account cannot submit a screening.'));
      }
      if (res.statusCode == 400) {
        return ScanSubmitResult(
            ok: false, message: _plainDetail(res, 'That file is not a valid photo.'));
      }
      return ScanSubmitResult(
          ok: false, message: 'Server error (${res.statusCode}). Please try again.');
    } catch (_) {
      return const ScanSubmitResult(
          ok: false, message: 'Cannot reach the server. Check your connection.');
    }
  }
}
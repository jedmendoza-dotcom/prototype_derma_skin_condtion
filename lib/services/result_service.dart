import 'dart:convert';

import 'package:http/http.dart' as http;

class Guidance {
  final String? severity, urgency, title, advice, seeDoctorWhen;
  const Guidance({this.severity, this.urgency, this.title, this.advice, this.seeDoctorWhen});
}

class ConditionResult {
  final int rank;
  final String name, category, description;
  final double confidence;
  final List<String> commonSigns;
  final String? moreDetailsUrl, moreDetailsSource;
  final Guidance? guidance;
  final List<String> matchedSigns;
  const ConditionResult({
    required this.rank,
    required this.name,
    required this.category,
    required this.description,
    required this.confidence,
    required this.commonSigns,
    this.moreDetailsUrl,
    this.moreDetailsSource,
    this.guidance,
    this.matchedSigns = const [],
  });
}

class YourAnswers {
  final String ageGroup, durationRange, description;
  final int itchScore;
  final bool hasSwelling, hasAllergy;
  final String? allergyDetails;
  const YourAnswers({
    required this.ageGroup,
    required this.durationRange,
    required this.description,
    required this.itchScore,
    required this.hasSwelling,
    required this.hasAllergy,
    this.allergyDetails,
  });
}

class RecordItem {
  final int scanId;
  final String scannedAt, description;
  final String? topCondition;
  final double? topConfidence;
  final String? note;
  const RecordItem({
    required this.scanId,
    required this.scannedAt,
    required this.description,
    this.topCondition,
    this.topConfidence,
    this.note,
  });
}

class ScreeningResult {
  final YourAnswers? answers;
  final int scanId;
  final bool inconclusive;
  final String method; // rules_only | model_and_rules
  final String basis; // image_and_description | description_only
  final List<ConditionResult> conditions;
  final List<String> redFlags, notes;
  final String disclaimer;
  const ScreeningResult({
    this.answers,
    required this.scanId,
    required this.inconclusive,
    required this.method,
    required this.basis,
    required this.conditions,
    required this.redFlags,
    required this.notes,
    required this.disclaimer,
  });
}

class ResultFetch {
  final ScreeningResult? result;
  final String? error;
  const ResultFetch({this.result, this.error});
}

class ResultService {
  final String baseUrl;
  final Future<String?> Function() getToken;
  const ResultService({required this.baseUrl, required this.getToken});

  Future<ResultFetch> fetch(int scanId) async {
    try {
      final token = await getToken();
      if (token == null) return const ResultFetch(error: 'Your session expired. Please sign in again.');
      final res = await http
          .get(Uri.parse('$baseUrl/scans/$scanId/result'),
              headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) return const ResultFetch(error: 'No result found for this screening.');
      if (res.statusCode != 200) return ResultFetch(error: 'Server error (${res.statusCode}).');
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      List<String> strs(dynamic v) => (v as List? ?? []).map((e) => e.toString()).toList();
      final conds = (j['conditions'] as List).map((c) {
        final g = c['guidance'];
        return ConditionResult(
          rank: c['rank'] as int,
          name: c['name'] as String,
          category: (c['category'] ?? '').toString(),
          description: (c['description'] ?? '').toString(),
          confidence: (c['confidence'] as num).toDouble(),
          commonSigns: strs(c['common_signs']),
          matchedSigns: strs(c['matched_signs']),
          moreDetailsUrl: c['more_details_url'] as String?,
          moreDetailsSource: c['more_details_source'] as String?,
          guidance: g == null
              ? null
              : Guidance(
                  severity: g['severity'] as String?,
                  urgency: g['urgency'] as String?,
                  title: g['title'] as String?,
                  advice: g['advice'] as String?,
                  seeDoctorWhen: g['see_doctor_when'] as String?),
        );
      }).toList();
      final a = j['your_answers'];
      return ResultFetch(
          result: ScreeningResult(
        answers: a == null
            ? null
            : YourAnswers(
                ageGroup: (a['age_group'] ?? '').toString(),
                durationRange: (a['duration_range'] ?? '').toString(),
                description: (a['description'] ?? '').toString(),
                itchScore: (a['itch_score'] as num?)?.toInt() ?? 0,
                hasSwelling: a['has_swelling'] == true,
                hasAllergy: a['has_allergy'] == true,
                allergyDetails: a['allergy_details'] as String?),
        scanId: j['scan_id'] as int,
        inconclusive: j['inconclusive'] == true,
        method: (j['method'] ?? '').toString(),
        basis: (j['basis'] ?? '').toString(),
        conditions: conds,
        redFlags: strs(j['red_flags']),
        notes: strs(j['notes']),
        disclaimer: (j['disclaimer'] ?? '').toString(),
      ));
    } catch (_) {
      return const ResultFetch(error: 'Cannot reach the server. Check your connection.');
    }
  }

  /// The signed-in person's own past screenings, newest first.
  Future<({List<RecordItem> items, String? error})> list() async {
    try {
      final token = await getToken();
      if (token == null) return (items: <RecordItem>[], error: 'Your session expired. Please sign in again.');
      final res = await http
          .get(Uri.parse('$baseUrl/scans'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return (items: <RecordItem>[], error: 'Server error (${res.statusCode}).');
      final l = jsonDecode(utf8.decode(res.bodyBytes)) as List;
      return (
        items: l
            .map((e) => RecordItem(
                  scanId: e['scan_id'] as int,
                  scannedAt: (e['scanned_at'] ?? '').toString(),
                  description: (e['description'] ?? '').toString(),
                  topCondition: e['top_condition'] as String?,
                  topConfidence: (e['top_confidence'] as num?)?.toDouble(),
                  note: e['note'] as String?,
                ))
            .toList(),
        error: null
      );
    } catch (_) {
      return (items: <RecordItem>[], error: 'Cannot reach the server. Check your connection.');
    }
  }

  /// Update: save the person's own note on one screening. Returns an error text, or null when it worked.
  Future<String?> updateNote(int scanId, String note) async {
    try {
      final token = await getToken();
      if (token == null) return 'Your session expired. Please sign in again.';
      final res = await http
          .patch(Uri.parse('$baseUrl/scans/$scanId/note'),
              headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
              body: jsonEncode({'note': note}))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return null;
      if (res.statusCode == 404) return 'This screening no longer exists.';
      return 'Server error (${res.statusCode}).';
    } catch (_) {
      return 'Cannot reach the server. Check your connection.';
    }
  }

  /// Delete: remove one of the person's own screenings. Returns an error text, or null when it worked.
  Future<String?> delete(int scanId) async {
    try {
      final token = await getToken();
      if (token == null) return 'Your session expired. Please sign in again.';
      final res = await http
          .delete(Uri.parse('$baseUrl/scans/$scanId'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return null;
      if (res.statusCode == 404) return 'This screening no longer exists.';
      if (res.statusCode == 409) {
        try {
          final d = jsonDecode(utf8.decode(res.bodyBytes))['detail'];
          if (d is String) return d;
        } catch (_) {}
        return 'This screening cannot be deleted.';
      }
      return 'Server error (${res.statusCode}).';
    } catch (_) {
      return 'Cannot reach the server. Check your connection.';
    }
  }
}
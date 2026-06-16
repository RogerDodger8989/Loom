import 'package:flutter/foundation.dart';

/// Validates API responses before they reach model classes.
///
/// Hard errors (missing required fields) always throw [ApiContractException].
/// Soft warnings (wrong type on optional field) throw in debug, log silently
/// in release — the app never crashes on bad API data.
class ApiContract {
  ApiContract._();

  static Map<String, dynamic> validateMediaDetails(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw ApiContractException(
          'mediaDetails: expected object, got ${raw.runtimeType}');
    }
    _require(raw, 'id');
    _require(raw, 'title');
    _require(raw, 'type');
    // episodes is optional but must be a List if present
    if (raw.containsKey('episodes') && raw['episodes'] != null && raw['episodes'] is! List) {
      _warn('mediaDetails.episodes: expected List, got ${raw['episodes'].runtimeType}');
    }
    return raw;
  }

  static Map<String, dynamic> validateEpisode(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw ApiContractException(
          'episode: expected object, got ${raw.runtimeType}');
    }
    _require(raw, 'id');
    return raw;
  }

  /// Validates a list-endpoint response (e.g. /api/media/movies).
  /// Each entry must be a Map with at least `id` and `title`.
  /// Invalid entries are dropped with a warning rather than crashing the list.
  static List<Map<String, dynamic>> validateMediaList(dynamic raw) {
    if (raw is! List) {
      throw ApiContractException(
          'mediaList: expected List, got ${raw.runtimeType}');
    }
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map<String, dynamic>) {
        _warn('mediaList[$i]: expected object, got ${entry.runtimeType} — skipped');
        continue;
      }
      if (!entry.containsKey('id') || entry['id'] == null) {
        _warn('mediaList[$i]: missing required field "id" — skipped');
        continue;
      }
      if (!entry.containsKey('title') || entry['title'] == null) {
        _warn('mediaList[$i]: missing required field "title" — skipped');
        continue;
      }
      result.add(entry);
    }
    return result;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static void _require(Map<String, dynamic> m, String key) {
    if (!m.containsKey(key) || m[key] == null) {
      throw ApiContractException('Missing required field: $key');
    }
  }

  static void _warn(String msg) {
    // In debug builds: surface as an exception so the issue is caught early.
    assert(() {
      throw ApiContractException(msg);
    }());
    // In release builds: log silently — never crash the user.
    debugPrint('[ApiContract] WARNING: $msg');
  }
}

class ApiContractException implements Exception {
  final String message;
  const ApiContractException(this.message);

  @override
  String toString() => 'ApiContractException: $message';
}

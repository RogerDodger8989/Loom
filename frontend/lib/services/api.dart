import 'dart:convert';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  // Configured to point to the Fastify local server.
  final String baseUrl = 'http://localhost:8080';

  String? _token;

  String? get token => _token;

  // Remembers the last-used statistics tab across settings sessions (in-memory only).
  int lastStatsTabIndex = 0;

  // ---- Local Storage helpers (shared_preferences) ----

  SharedPreferences? _prefs;

  Future<void> initStorage() async {
    _prefs = await SharedPreferences.getInstance();
    // Load initial token if exists
    _token = _readStorage('loom_token');
  }

  String? _readStorage(String key) {
    return _prefs?.getString(key);
  }

  Future<void> _writeStorage(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  Future<void> _removeStorage(String key) async {
    await _prefs?.remove(key);
  }

  // ---- Device ID management ----

  String getOrCreateDeviceId() {
    String? deviceId = _readStorage('loom_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${1000 + (DateTime.now().microsecond % 9000)}';
      unawaited(_writeStorage('loom_device_id', deviceId));
    }
    return deviceId;
  }

  Future<void> saveDeviceId(String deviceId) async {
    await _writeStorage('loom_device_id', deviceId);
  }

  // ---- Token management ----

  bool loadPersistedToken() {
    _token = _readStorage('loom_token');
    return _token != null;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _writeStorage('loom_token', token);
  }

  Future<void> clearToken() async {
    _token = null;
    await _removeStorage('loom_token');
  }

  Future<void> saveSettingsCache(Map<String, dynamic> settings) async {
    await _writeStorage('loom_settings_cache', jsonEncode(settings));
  }

  Map<String, dynamic>? loadSettingsCache() {
    final raw = _readStorage('loom_settings_cache');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  /// Trigger a folder scan for movies, shows, or music tracks.
  Future<Map<String, dynamic>> triggerLibraryScan(String folderPath, String type, {bool preferLocalNfo = true}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/library/scan'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'path': folderPath,
        'type': type,
        'preferLocalNfo': preferLocalNfo,
      }),
    );

    if (response.statusCode == 202) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to trigger scan: ${response.body}');
    }
  }

  /// Open server-side Windows Folder Browser Dialog to select a path
  Future<Map<String, dynamic>> browseNativeDirectory() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/library/browse-native'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to browse native directory: ${response.body}');
    }
  }

  /// Authenticated: Fetch Global Settings
  Future<Map<String, dynamic>> getSettings() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/settings'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get settings: ${response.body}');
    }
  }

  Future<void> updateSettings(Map<String, String> newSettings) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/settings'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode(newSettings),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to update settings: ${response.body}');
    }
  }

  /// Fetch movies library
  Future<List<dynamic>> fetchMovies({bool mergeVersions = true}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/media/movies?mergeVersions=$mergeVersions'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load movies: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchMediaDetails(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/media/items/$id'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load media details: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchTechInfo(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/api/media/items/$id/tech-info'));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to fetch tech info: ${response.body}');
  }

  /// Authenticated: Upsert media metadata (general-purpose)
  Future<void> saveMediaMetadata(String id, String key, dynamic value) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/metadata'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'key': key, 'value': value}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to save media metadata: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> fetchMediaMetadataState(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/media/items/$id/metadata-state'),
      headers: const {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to fetch metadata state: ${response.body}');
  }

  Future<void> setMediaMetadataLock(String id, String key, bool isLocked) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/media/items/$id/metadata-lock'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'key': key, 'isLocked': isLocked}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update metadata lock: ${response.body}');
    }
  }

  Future<void> updateMediaItemFields(String id, Map<String, dynamic> fields) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/media/items/$id'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(fields),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update media item: ${response.body}');
    }
  }

  /// Convenience: Save user's personal rating for a media item
  Future<void> saveRating(String id, double rating) async {
    await saveMediaMetadata(id, 'my_rating', rating.round().toString());
  }

  /// Authenticated: Toggle seen/watched status for a media item
  Future<Map<String, dynamic>> toggleSeenStatus(String id, bool isWatched) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/seen'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'watched': isWatched}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to toggle seen status: ${response.body}');
    }
  }

  /// Authenticated: Toggle favorite/protected status for a media item
  Future<Map<String, dynamic>> toggleFavorite(String id, {bool? isFavorite}) async {
    final body = isFavorite != null ? jsonEncode({'is_favorite': isFavorite}) : '{}';
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/favorite'),
      headers: {'Content-Type': 'application/json', ..._authHeaders()},
      body: body,
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to toggle favorite: ${response.body}');
  }

  /// Authenticated: Toggle favorite for a specific season of a TV show
  Future<Map<String, dynamic>> toggleSeasonFavorite(String showId, int season, {bool? isFavorite}) async {
    final body = isFavorite != null ? jsonEncode({'is_favorite': isFavorite}) : '{}';
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$showId/season/$season/favorite'),
      headers: {'Content-Type': 'application/json', ..._authHeaders()},
      body: body,
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to toggle season favorite: ${response.body}');
  }

  /// Authenticated: Report playback progress (heartbeat/scrobble)
  Future<Map<String, dynamic>> reportPlaybackProgress(String id, int positionSeconds, int durationSeconds) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/progress'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'position': positionSeconds,
        'duration': durationSeconds,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to report playback progress: ${response.body}');
    }
  }


  Future<Map<String, dynamic>> fetchCollectionItems(String collectionId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/media/collections/$collectionId'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load collection items: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchSimilarItems(String mediaId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/media/$mediaId/similar'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load similar items: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchPersonDetails(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/people/$id'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load person details: ${response.statusCode}');
    }
  }

  /// Fetch shows library
  Future<List<dynamic>> fetchShows() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/media/shows'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch shows: ${response.body}');
    }
  }

  /// Get library scanner status
  Future<Map<String, dynamic>> getLibraryStatus() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/library/status'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get library status: ${response.body}');
    }
  }

  /// Fetch all configured library paths
  Future<List<dynamic>> fetchLibraryPaths() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/library/paths'),
      headers: const {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch library paths: ${response.body}');
    }
  }

  /// Add a new configured library directory path
  Future<Map<String, dynamic>> addLibraryPath(String folderPath, String type) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/library/paths'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'path': folderPath,
        'type': type,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to add library path: ${response.body}');
    }
  }

  /// Delete a configured library directory path
  Future<Map<String, dynamic>> deleteLibraryPath(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/library/paths'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': id,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to delete library path: ${response.body}');
    }
  }

  /// Update a configured library directory path and bulk replace items
  Future<Map<String, dynamic>> updateLibraryPath(String id, String newPath) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/library/paths'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': id,
        'newPath': newPath,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update library path: ${response.body}');
    }
  }

  /// POST /api/auth/login — sparar token, kastar vid fel lösenord.
  // ── Saved credentials (remember password) ───────────────────────────────

  Future<void> saveRememberedLogin(String username, String password) async {
    await _prefs?.setString('saved_login_username', username);
    await _prefs?.setString('saved_login_password', password);
  }

  Map<String, String>? loadRememberedLogin() {
    final u = _prefs?.getString('saved_login_username');
    final p = _prefs?.getString('saved_login_password');
    if (u == null || p == null) return null;
    return {'username': u, 'password': p};
  }

  Future<void> clearRememberedLogin() async {
    await _prefs?.remove('saved_login_username');
    await _prefs?.remove('saved_login_password');
  }

  // ── PIN login ────────────────────────────────────────────────────────────

  Future<void> loginWithPin(String userId, String pin) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login-pin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'pin': pin}),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await saveToken(body['token'] as String);
    } else {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Fel PIN');
    }
  }

  Future<void> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await saveToken(body['token'] as String);
    } else {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['error'] ?? 'Inloggning misslyckades');
    }
  }

  /// Initialize user session — returns true if a saved token exists.
  Future<bool> initializeSession() async {
    try {
      await initStorage();
      _token = _readStorage('loom_token');
      return _token != null && _token!.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Authenticated: Search TMDB candidates for a media item
  Future<List<dynamic>> searchTmdbCandidates(String id, String query, {String? year}) async {
    if (_token == null) throw Exception('Unauthorized');
    final uri = Uri.parse('$baseUrl/api/media/items/$id/search-tmdb').replace(
      queryParameters: {
        'query': query,
        if (year != null && year.isNotEmpty) 'year': year,
      },
    );
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to search TMDB candidates: ${response.body}');
    }
  }

  /// Authenticated: Search TMDB movies (generic endpoint, no local media id needed)
  Future<List<dynamic>> searchTmdbMovies(String query, {String? year}) async {
    if (_token == null) throw Exception('Unauthorized');
    final uri = Uri.parse('$baseUrl/api/media/search-tmdb').replace(
      queryParameters: {
        'query': query,
        if (year != null && year.isNotEmpty) 'year': year,
      },
    );
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to search TMDB movies: ${response.body}');
    }
  }

  /// Authenticated: Manually pair a movie to a specific TMDB ID
  Future<Map<String, dynamic>> fixMatch(String id, String tmdbId) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/match'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'tmdbId': tmdbId,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fix match: ${response.body}');
    }
  }

  /// Authenticated: Create a new playlist and add a media item to it.
  Future<Map<String, dynamic>> createPlaylistAndAddItem(String playlistName, String mediaItemId) async {
    if (_token == null) throw Exception('Unauthorized');
    // Create the playlist
    final createResp = await http.post(
      Uri.parse('$baseUrl/api/playlists'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'name': playlistName}),
    );
    if (createResp.statusCode != 200 && createResp.statusCode != 201) {
      throw Exception('Kunde inte skapa spellista: ${createResp.body}');
    }
    final playlist = jsonDecode(createResp.body);
    final playlistId = playlist['id'];

    // Add the item
    final addResp = await http.post(
      Uri.parse('$baseUrl/api/playlists/$playlistId/items'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'mediaItemId': mediaItemId}),
    );
    if (addResp.statusCode != 200 && addResp.statusCode != 201) {
      throw Exception('Kunde inte lägga till i spellista: ${addResp.body}');
    }
    return jsonDecode(addResp.body);
  }

  /// Soft-delete media item (moves file to .trash, sets deleted_at)
  Future<void> deleteMediaItem(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/media/items/$id'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete media item: ${response.body}');
    }
  }

  Future<List<dynamic>> fetchImdbCalendar(String start, {int days = 90}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/calendar/imdb?start=$start&days=$days'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode == 200) return jsonDecode(response.body) as List;
    if (response.statusCode == 404 || response.statusCode == 401) return [];
    throw Exception('IMDb calendar error: ${response.body}');
  }

  /// Report playback progress for a single episode (heartbeat)
  Future<Map<String, dynamic>> reportEpisodeProgress(String episodeId, int positionSeconds, int durationSeconds) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/episodes/$episodeId/progress'),
      headers: {'Content-Type': 'application/json', ..._authHeaders()},
      body: jsonEncode({'positionSeconds': positionSeconds, 'durationSeconds': durationSeconds}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to report episode progress: ${response.body}');
  }

  /// Fetch watched/progress status for a single episode
  Future<Map<String, dynamic>> fetchEpisodeStatus(String episodeId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/media/episodes/$episodeId/status'),
      headers: _authHeaders(),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to fetch episode status: ${response.body}');
  }

  /// Toggle watched status for a single episode
  Future<Map<String, dynamic>> toggleEpisodeSeenStatus(String episodeId, bool isWatched) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/episodes/$episodeId/seen'),
      headers: {'Content-Type': 'application/json', ..._authHeaders()},
      body: jsonEncode({'watched': isWatched}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to toggle episode seen: ${response.body}');
  }

  /// Mark all episodes in a season as watched or unwatched
  Future<Map<String, dynamic>> markSeasonSeen(String showId, int season, bool isWatched) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$showId/season/$season/seen'),
      headers: {'Content-Type': 'application/json', ..._authHeaders()},
      body: jsonEncode({'watched': isWatched}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to mark season seen: ${response.body}');
  }

  /// Soft-delete a single episode
  Future<void> deleteEpisode(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/media/episodes/$id'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete episode: ${response.body}');
    }
  }

  /// Soft-delete all episodes in a season
  Future<void> deleteSeason(String showId, int seasonNumber) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/media/seasons/$showId/$seasonNumber'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete season: ${response.body}');
    }
  }

  /// Authenticated: Refresh media metadata from online services
  Future<void> refreshMediaMetadata(String id) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/refresh'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to refresh media metadata: ${response.body}');
    }
  }

  /// Authenticated: Unmatch media item in database
  Future<void> unmatchMediaItem(String id) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/unmatch'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to unmatch media item: ${response.body}');
    }
  }

  /// Authenticated: Re-analyze media item file tracks
  Future<void> analyzeMediaItem(String id) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/analyze'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to analyze media item: ${response.body}');
    }
  }

  /// Authenticated: Trigger a manual background synchronization of Trakt and Simkl ratings and watched history
  Future<Map<String, dynamic>> triggerSync() async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.post(
      Uri.parse('$baseUrl/api/sync/trigger'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: '{}',
    );
    if (response.statusCode == 202) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to trigger sync: ${response.body}');
    }
  }

  /// Authenticated: Fetch current sync status and progress
  Future<Map<String, dynamic>> getSyncStatus() async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.get(
      Uri.parse('$baseUrl/api/sync/status'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch sync status: ${response.body}');
    }
  }

  /// Authenticated: Fetch log entries, optionally only entries with id > sinceId
  Future<Map<String, dynamic>> fetchLogs({int? sinceId}) async {
    final uri = sinceId != null
        ? Uri.parse('$baseUrl/api/logs?sinceId=$sinceId')
        : Uri.parse('$baseUrl/api/logs');
    final response = await http.get(
      uri,
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('fetchLogs failed: ${response.statusCode}');
  }

  /// URL for downloading the full log file
  String get logsDownloadUrl => '$baseUrl/api/logs/download';

  /// Authenticated: Send a test Discord webhook notification
  Future<Map<String, dynamic>> testDiscordWebhook() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/notifications/test/discord'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    return jsonDecode(response.body);
  }

  /// Authenticated: Send a test email via SMTP
  Future<Map<String, dynamic>> testEmail() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/notifications/test/email'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    return jsonDecode(response.body);
  }

  /// Authenticated: Fetch server info (uptime, DB size, counts)
  Future<Map<String, dynamic>> fetchServerInfo() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/server/info'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('fetchServerInfo failed: ${response.statusCode}');
  }

  /// Authenticated: Optimize the SQLite database
  Future<Map<String, dynamic>> optimizeDatabase() async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/server/db/optimize'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    return jsonDecode(response.body);
  }

  /// URL for downloading the database backup (use downloadBackup() on desktop)
  String get dbBackupUrl => '$baseUrl/api/server/db/backup';

  /// Download backup as bytes — for desktop where html.window.open doesn't work
  Future<List<int>> downloadBackupBytes() async {
    final response = await http.get(Uri.parse(dbBackupUrl));
    if (response.statusCode == 200) return response.bodyBytes;
    throw Exception('Backup misslyckades: ${response.statusCode}');
  }

  /// Download logs as bytes
  Future<List<int>> downloadLogsBytes() async {
    final response = await http.get(Uri.parse(logsDownloadUrl));
    if (response.statusCode == 200) return response.bodyBytes;
    throw Exception('Loggexport misslyckades: ${response.statusCode}');
  }

  /// Authenticated: Upload a database restore file (raw bytes)
  Future<Map<String, dynamic>> restartServer() async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.post(
      Uri.parse('$baseUrl/api/server/restart'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> restoreDatabase(List<int> fileBytes, String filename) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/server/db/restore'),
    );
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    return jsonDecode(body);
  }

  /// Authenticated: Fetch all watchlist items
  Future<List<dynamic>> fetchWatchlist() async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.get(
      Uri.parse('$baseUrl/api/watchlist'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch watchlist: ${response.body}');
    }
  }

  /// Authenticated: Add item to watchlist
  Future<Map<String, dynamic>> addToWatchlist({
    required String tmdbId,
    required String title,
    required String type,
    int? year,
    String? posterPath,
  }) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.post(
      Uri.parse('$baseUrl/api/watchlist'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'tmdbId': tmdbId,
        'title': title,
        'type': type,
        'year': year,
        'posterPath': posterPath,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to add to watchlist: ${response.body}');
    }
  }

  /// Authenticated: Remove item from watchlist
  Future<void> removeFromWatchlist(String tmdbId) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.delete(
      Uri.parse('$baseUrl/api/watchlist/$tmdbId'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to remove from watchlist: ${response.body}');
    }
  }


  /// Fetch playback markers (Skip Intro/Outro)
  Future<Map<String, dynamic>?> getPlaybackMarkers(String mediaId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/playback/markers/$mediaId'),
        headers: {
          'Authorization': 'Bearer $_token',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      print('Error fetching markers: $e');
      return null;
    }
  }

  /// Start stream (Trigger HLS Transcode)
  Future<Map<String, dynamic>> startStream(String mediaId, {bool transcode = false, String bitrate = '4000k', String subtitleIndex = 'none'}) async {
    final url = Uri.parse('$baseUrl/api/playback/stream/$mediaId?transcode=$transcode&bitrate=$bitrate&subtitleIndex=$subtitleIndex');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to start stream: ${response.body}');
  }

  // ── Marker API ────────────────────────────────────────────────────────

  /// Fetch all markers (chapters + intro/outro) for a media item or episode
  Future<List<dynamic>> fetchMarkers(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/markers/$id'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode == 200) {
      return (jsonDecode(response.body)['markers'] as List<dynamic>? ?? []);
    }
    throw Exception('Failed to fetch markers: ${response.body}');
  }

  /// Trigger chapter extraction for a movie/episode (background)
  Future<void> scanChapters(String id) async {
    await http.post(Uri.parse('$baseUrl/api/markers/scan-chapters/$id'),
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : {});
  }

  /// Trigger audio fingerprint computation for a single episode
  Future<void> scanFingerprint(String episodeId) async {
    await http.post(Uri.parse('$baseUrl/api/markers/scan-fingerprint/$episodeId'),
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : {});
  }

  /// Trigger fingerprinting for all episodes in a show + detect intro
  Future<void> scanShowIntro(String showId) async {
    await http.post(Uri.parse('$baseUrl/api/markers/scan-show/$showId'),
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : {});
  }

  /// Re-run intro detection using existing fingerprints
  Future<Map<String, dynamic>> detectIntro(String showId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/markers/detect-intro/$showId'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to detect intro: ${response.body}');
  }

  /// Delete a marker
  Future<void> deleteMarker(String markerId) async {
    await http.delete(
      Uri.parse('$baseUrl/api/markers/$markerId'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
  }

  /// Returns a file:// URI for direct local playback (mpv/media_kit on desktop).
  /// Falls back to null on error so callers can use the HTTP stream URL instead.
  Future<String?> fetchFileUrl(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/playback/file-path/$id'));
      if (response.statusCode == 200) {
        return (jsonDecode(response.body) as Map<String, dynamic>)['fileUrl'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Fire-and-forget warmup: pre-generates the first HLS segments so playback starts instantly
  void warmupStream(String mediaId) {
    http.get(Uri.parse('$baseUrl/api/stream/warmup/$mediaId')).catchError((_) {});
  }

  /// Fetch all soft-deleted (trash) items
  Future<List<dynamic>> fetchTrash() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/trash'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to fetch trash: ${response.body}');
  }

  /// Restore a soft-deleted item from trash
  Future<void> restoreTrashItem(String id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/trash/$id/restore'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to restore item: ${response.body}');
    }
  }

  /// Permanently delete a trashed item (removes from disk + database)
  Future<void> permanentlyDeleteTrashItem(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/trash/$id/permanent'),
      headers: _token != null ? {'Authorization': 'Bearer $_token'} : {},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to permanently delete item: ${response.body}');
    }
  }

  // ── Calendar API ──────────────────────────────────────────────────────

  /// Fetch calendar events from the local library for [start]..[end] (YYYY-MM-DD).
  /// [type] = 'Show' | 'Movie' | 'all'
  Future<List<dynamic>> fetchCalendar(String start, String end, {String type = 'all'}) async {
    final uri = Uri.parse('$baseUrl/api/calendar').replace(
      queryParameters: {'start': start, 'end': end, 'type': type},
    );
    final response = await http.get(uri,
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : {});
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception('Failed to fetch calendar: ${response.body}');
  }

  /// Fetch upcoming episodes from the user's personal Trakt watchlist calendar.
  /// Requires Trakt OAuth to be connected in settings.
  Future<List<dynamic>> fetchTraktCalendar(String start, {int days = 30}) async {
    final uri = Uri.parse('$baseUrl/api/calendar/trakt').replace(
      queryParameters: {'start': start, 'days': days.toString()},
    );
    final response = await http.get(uri,
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : {});
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    final body = jsonDecode(response.body);
    throw Exception(body['error'] ?? 'Failed to fetch Trakt calendar');
  }

  /// Fetch upcoming episodes from the user's personal Simkl watchlist calendar.
  /// Requires Simkl OAuth to be connected in settings.
  Future<List<dynamic>> fetchSimklCalendar(String start, {int days = 30}) async {
    final uri = Uri.parse('$baseUrl/api/calendar/simkl').replace(
      queryParameters: {'start': start, 'days': days.toString()},
    );
    final response = await http.get(uri,
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : {});
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    final body = jsonDecode(response.body);
    throw Exception(body['error'] ?? 'Failed to fetch Simkl calendar');
  }

  /// Returns the URL for downloading a .ics calendar export.
  String calendarIcsUrl({String start = '2000-01-01', String end = '2099-12-31'}) {
    return '$baseUrl/api/calendar/export.ics?start=$start&end=$end';
  }

  // ── Users API (Admin) ─────────────────────────────────────────────────────

  Future<List<dynamic>> fetchUsers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/users'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception('Kunde inte hämta användare: ${response.body}');
  }

  Future<Map<String, dynamic>> createUser(String username, String password, String role) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/users'),
      headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password, 'role': role}),
    );
    if (response.statusCode == 201) return jsonDecode(response.body) as Map<String, dynamic>;
    final body = jsonDecode(response.body);
    throw Exception(body['error'] ?? 'Kunde inte skapa användare');
  }

  Future<Map<String, dynamic>> updateUser(String id, {String? username, String? fullName, String? role, String? password, String? pin}) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (fullName != null) body['full_name'] = fullName;
    if (role != null) body['role'] = role;
    if (password != null) body['password'] = password;
    if (pin != null) body['pin'] = pin; // empty string = remove PIN
    final response = await http.put(
      Uri.parse('$baseUrl/api/users/$id'),
      headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    final resp = jsonDecode(response.body);
    throw Exception(resp['error'] ?? 'Kunde inte uppdatera användare');
  }

  Future<void> deleteUser(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/users/$id'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Kunde inte ta bort användare');
    }
  }

  // ── RSS API ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> fetchRssFeeds() async {
    final r = await http.get(Uri.parse('$baseUrl/api/rss/feeds'));
    if (r.statusCode == 200) return jsonDecode(r.body) as List<dynamic>;
    throw Exception('Kunde inte hämta RSS-flöden');
  }

  Future<Map<String, dynamic>> addRssFeed(String url) async {
    final r = await http.post(Uri.parse('$baseUrl/api/rss/feeds'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'url': url}));
    if (r.statusCode == 201) return jsonDecode(r.body) as Map<String, dynamic>;
    final body = jsonDecode(r.body); throw Exception(body['error'] ?? 'Kunde inte lägga till flöde');
  }

  Future<void> deleteRssFeed(String id) async {
    final r = await http.delete(Uri.parse('$baseUrl/api/rss/feeds/$id'));
    if (r.statusCode != 200) throw Exception('Kunde inte ta bort flöde');
  }

  Future<List<dynamic>> fetchRssItems() async {
    final r = await http.get(Uri.parse('$baseUrl/api/rss/items'));
    if (r.statusCode == 200) return jsonDecode(r.body) as List<dynamic>;
    throw Exception('Kunde inte hämta RSS-poster');
  }

  Future<Map<String, dynamic>> refreshRssFeeds() async {
    final r = await http.post(Uri.parse('$baseUrl/api/rss/refresh'));
    if (r.statusCode == 200) return jsonDecode(r.body) as Map<String, dynamic>;
    throw Exception('Kunde inte uppdatera flöden');
  }

  // ── Stats API ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchStatsRealtime() async {
    final response = await http.get(Uri.parse('$baseUrl/api/stats/realtime'));
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('stats/realtime ${response.statusCode}: ${response.body}');
  }

  Future<Map<String, dynamic>> fetchStatsHistory({
    String? userId,
    int? days,
    String? startDate,
    String? endDate,
    int limit = 50,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (userId != null) params['userId'] = userId;
    if (startDate != null || endDate != null) {
      if (startDate != null) params['startDate'] = startDate;
      if (endDate != null) params['endDate'] = endDate;
    } else if (days != null) {
      params['days'] = '$days';
    }
    final uri = Uri.parse('$baseUrl/api/stats/history').replace(queryParameters: params);
    final response = await http.get(uri);
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('stats/history ${response.statusCode}: ${response.body}');
  }

  Future<List<dynamic>> fetchStatsUsers() async {
    final response = await http.get(Uri.parse('$baseUrl/api/stats/users'));
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception('stats/users ${response.statusCode}: ${response.body}');
  }

  Future<Map<String, dynamic>> fetchStatsTops() async {
    final response = await http.get(Uri.parse('$baseUrl/api/stats/tops'));
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('stats/tops ${response.statusCode}: ${response.body}');
  }

  Future<Map<String, dynamic>> fetchMediaPlays(String mediaId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/stats/media/$mediaId/plays'));
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('stats/media/plays ${response.statusCode}: ${response.body}');
  }

  // ── Konto API ─────────────────────────────────────────────────────────────

  Future<void> updateOwnPassword(String currentPassword, String newPassword) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword}),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Kunde inte byta lösenord');
    }
  }

  Future<void> uploadAvatar(List<int> imageBytes) async {
    if (_token == null) throw Exception('Unauthorized');
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/auth/me/avatar'),
    );
    request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(http.MultipartFile.fromBytes('avatar', imageBytes, filename: 'avatar.jpg'));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      final resp = jsonDecode(body);
      throw Exception(resp['error'] ?? 'Upload failed');
    }
  }

  Future<Map<String, dynamic>> fetchCurrentUserProfile() async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: {'Authorization': 'Bearer $_token'},
    );
    if (response.statusCode != 200) throw Exception('Kunde inte hämta profil');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> updateOwnProfile({String? fullName, String? newUsername, String? pin}) async {
    final payload = <String, dynamic>{};
    if (fullName != null) payload['full_name'] = fullName;
    if (newUsername != null) payload['newUsername'] = newUsername;
    if (pin != null) payload['pin'] = pin;
    final response = await http.put(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Kunde inte uppdatera profil');
    }
    // Store the fresh JWT returned by the backend so UI reflects changes immediately
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['token'] is String) {
      await saveToken(body['token'] as String);
    }
  }

  /// Decode JWT payload locally — returns {id, username, role} or null.
  Map<String, dynamic>? get currentUserPayload {
    final t = _token;
    if (t == null || t.isEmpty) return null;
    try {
      final parts = t.split('.');
      if (parts.length < 2) return null;
      final padded = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  // ── Export / Import ───────────────────────────────────────────────────────

  Future<List<int>> exportBackup({
    bool settings = true,
    bool libraryPaths = true,
    bool users = false,
    bool watchHistory = false,
    bool watchlist = false,
    bool markers = false,
  }) async {
    final params = {
      if (settings) 'settings': 'true',
      if (libraryPaths) 'library_paths': 'true',
      if (users) 'users': 'true',
      if (watchHistory) 'watch_history': 'true',
      if (watchlist) 'watchlist': 'true',
      if (markers) 'markers': 'true',
    };
    final uri = Uri.parse('$baseUrl/api/export').replace(queryParameters: params);
    final response = await http.get(uri,
        headers: _token != null ? {'Authorization': 'Bearer $_token'} : {});
    if (response.statusCode == 200) return response.bodyBytes;
    throw Exception('Export misslyckades: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> importBackup(List<int> fileBytes, String filename) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/import'));
    if (_token != null) request.headers['Authorization'] = 'Bearer $_token';
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (streamed.statusCode != 200) throw Exception(decoded['error'] ?? 'Import misslyckades');
    return decoded;
  }

  // ── Public user profiles (for profile picker) ────────────────────────────

  Future<List<dynamic>> fetchProfiles() async {
    final response = await http.get(Uri.parse('$baseUrl/api/auth/profiles'));
    if (response.statusCode == 200) return jsonDecode(response.body) as List<dynamic>;
    throw Exception('fetchProfiles failed: ${response.statusCode}');
  }

  // ── Scanner events (real-time polling) ───────────────────────────────────

  Future<Map<String, dynamic>> fetchScanEvents({int? sinceId}) async {
    final uri = Uri.parse('$baseUrl/api/library/scan-events')
        .replace(queryParameters: sinceId != null ? {'sinceId': sinceId.toString()} : {});
    final response = await http.get(uri, headers: _authHeaders());
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('fetchScanEvents failed: ${response.statusCode}');
  }

  // ── Library path watch toggle ─────────────────────────────────────────────

  Future<void> toggleWatchPath(String id, bool watch) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/library/paths/watch'),
      headers: {'Content-Type': 'application/json', ..._authHeaders()},
      body: jsonEncode({'id': id, 'watch': watch}),
    );
    if (response.statusCode != 200) throw Exception('toggleWatchPath failed');
  }

  // ── Watched status + ratings export ──────────────────────────────────────

  Future<List<int>> exportWatched({String format = 'json'}) async {
    final uri = Uri.parse('$baseUrl/api/library/export')
        .replace(queryParameters: {'format': format});
    final response = await http.get(uri, headers: _authHeaders());
    if (response.statusCode == 200) return response.bodyBytes;
    throw Exception('exportWatched failed: ${response.statusCode}');
  }

  Map<String, String> _authHeaders() =>
      _token != null ? {'Authorization': 'Bearer $_token'} : {};

  // ── Disk Manager API ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> diskStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/disk/stats'),
      headers: _authHeaders(),
    );
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('diskStats failed: ${response.body}');
  }

  Future<Map<String, dynamic>> diskScan() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/disk/scan'),
      headers: _authHeaders(),
    );
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('diskScan failed: ${response.body}');
  }

  Future<Map<String, dynamic>> diskCleanup({List<String>? ids}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/disk/cleanup'),
      headers: {..._authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'ids': ids}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('diskCleanup failed: ${response.body}');
  }
}

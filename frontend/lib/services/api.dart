import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiService {
  // Configured to point to the Fastify local server.
  final String baseUrl = 'http://localhost:8080';
  
  String? _token;

  String? get token => _token;

  // ---- Local Storage helpers (direct browser localStorage) ----

  String? _readStorage(String key) {
    return html.window.localStorage[key];
  }

  void _writeStorage(String key, String value) {
    html.window.localStorage[key] = value;
  }

  void _removeStorage(String key) {
    html.window.localStorage.remove(key);
  }

  // ---- Device ID management ----

  String getOrCreateDeviceId() {
    String? deviceId = _readStorage('loom_device_id');
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}_${1000 + (DateTime.now().microsecond % 9000)}';
      _writeStorage('loom_device_id', deviceId);
    }
    return deviceId;
  }

  void saveDeviceId(String deviceId) {
    _writeStorage('loom_device_id', deviceId);
  }

  // ---- Token management ----

  bool loadPersistedToken() {
    _token = _readStorage('loom_token');
    return _token != null;
  }

  void saveToken(String token) {
    _token = token;
    _writeStorage('loom_token', token);
  }

  void clearToken() {
    _token = null;
    _removeStorage('loom_token');
  }

  /// Unauthenticated: Request a temporary pairing PIN and unique Device ID
  Future<Map<String, dynamic>> requestPairingCode({String? deviceId}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/pair/request'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (deviceId != null) 'deviceId': deviceId,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to request pairing code: ${response.body}');
    }
  }

  /// Unauthenticated: Poll pairing status for a given Device ID.
  /// If pairing was approved by the admin, returns the user credentials and JWT.
  Future<Map<String, dynamic>> checkPairingStatus(String deviceId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/auth/pair/status?deviceId=$deviceId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['paired'] == true && data['token'] != null) {
        saveToken(data['token']);
      }
      return data;
    } else {
      throw Exception('Failed to check pairing status: ${response.body}');
    }
  }

  /// Authenticated: Trigger a folder scan for movies, shows, or music tracks.
  Future<Map<String, dynamic>> triggerLibraryScan(String folderPath, String type, {bool preferLocalNfo = true}) async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/library/scan'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
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

  /// Authenticated: Open server-side Windows Folder Browser Dialog to select a path
  Future<Map<String, dynamic>> browseNativeDirectory() async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/library/browse-native'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to browse native directory: ${response.body}');
    }
  }

  /// Authenticated: Fetch Global Settings
  Future<Map<String, dynamic>> getSettings() async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }
    
    final response = await http.get(
      Uri.parse('$baseUrl/api/settings'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get settings: ${response.body}');
    }
  }

  Future<void> updateSettings(Map<String, String> newSettings) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }
    
    final response = await http.put(
      Uri.parse('$baseUrl/api/settings'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(newSettings),
    );
    
    if (response.statusCode != 200) {
      throw Exception('Failed to update settings: ${response.body}');
    }
  }

  /// Authenticated: Fetch movies library
  Future<List<dynamic>> fetchMovies({bool mergeVersions = true}) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/media/movies?mergeVersions=$mergeVersions'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load movies: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchMediaDetails(String id) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/media/items/$id'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load media details: ${response.statusCode}');
    }
  }

  /// Authenticated: Upsert media metadata (general-purpose)
  Future<void> saveMediaMetadata(String id, String key, dynamic value) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/metadata'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'key': key, 'value': value}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to save media metadata: ${response.body}');
    }
  }

  /// Convenience: Save user's personal rating for a media item
  Future<void> saveRating(String id, double rating) async {
    await saveMediaMetadata(id, 'my_rating', rating.round().toString());
  }

  /// Authenticated: Toggle seen/watched status for a media item
  Future<Map<String, dynamic>> toggleSeenStatus(String id, bool isWatched) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/seen'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'watched': isWatched}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to toggle seen status: ${response.body}');
    }
  }

  /// Authenticated: Report playback progress (heartbeat/scrobble)
  Future<Map<String, dynamic>> reportPlaybackProgress(String id, int positionSeconds, int durationSeconds) async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/items/$id/progress'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
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
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/media/collections/$collectionId'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load collection items: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchSimilarItems(String mediaId) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/media/$mediaId/similar'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load similar items: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> fetchPersonDetails(String id) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/people/$id'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load person details: ${response.statusCode}');
    }
  }

  /// Authenticated: Fetch shows library
  Future<List<dynamic>> fetchShows() async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/media/shows'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch shows: ${response.body}');
    }
  }

  /// Authenticated: Get library scanner status
  Future<Map<String, dynamic>> getLibraryStatus() async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/library/status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get library status: ${response.body}');
    }
  }

  /// Authenticated: Fetch all configured library paths
  Future<List<dynamic>> fetchLibraryPaths() async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/library/paths'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch library paths: ${response.body}');
    }
  }

  /// Authenticated: Add a new configured library directory path
  Future<Map<String, dynamic>> addLibraryPath(String folderPath, String type) async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/library/paths'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
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

  /// Authenticated: Delete a configured library directory path
  Future<Map<String, dynamic>> deleteLibraryPath(String id) async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.delete(
      Uri.parse('$baseUrl/api/library/paths'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
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

  /// Authenticated: Update a configured library directory path and bulk replace items
  Future<Map<String, dynamic>> updateLibraryPath(String id, String newPath) async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.put(
      Uri.parse('$baseUrl/api/library/paths'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
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

  /// Unauthenticated: Request to unpair a device ID on the server
  Future<Map<String, dynamic>> unpairDevice(String deviceId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/pair/unpair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to unpair device: ${response.body}');
    }
  }

  /// Initialize user session:
  /// 1. Try to load the local persisted token.
  /// 2. If present, verify it by making a lightweight request (fetchLibraryPaths).
  /// 3. If invalid or missing, check if the server already has this device ID paired.
  Future<bool> initializeSession() async {
    try {
      _token = _readStorage('loom_token');
      final savedDeviceId = _readStorage('loom_device_id');

      debugPrint('[LOOM] initializeSession - token: ${_token != null ? "EXISTS" : "NULL"}, deviceId: $savedDeviceId');

      if (_token != null) {
        try {
          await fetchLibraryPaths();
          debugPrint('[LOOM] Token is VALID! Auto-logged in.');
          return true;
        } catch (e) {
          debugPrint('[LOOM] Token invalid: $e. Clearing...');
          clearToken();
        }
      }

      // No valid local token - check if server remembers this device
      final deviceId = getOrCreateDeviceId();
      debugPrint('[LOOM] Checking server pairing for deviceId: $deviceId');
      try {
        final status = await checkPairingStatus(deviceId);
        debugPrint('[LOOM] Server response: paired=${status['paired']}, hasToken=${status['token'] != null}');
        if (status['paired'] == true && status['token'] != null) {
          debugPrint('[LOOM] Device IS paired! Auto-logged in.');
          return true;
        }
      } catch (e) {
        debugPrint('[LOOM] Error querying pairing status: $e');
      }

      debugPrint('[LOOM] initializeSession -> FALSE (showing pairing screen)');
      return false;
    } catch (e) {
      debugPrint('[LOOM] initializeSession EXCEPTION: $e');
      return false;
    }
  }

  /// Authenticated: Fetch all paired/trusted devices
  Future<List<dynamic>> fetchDevices() async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.get(
      Uri.parse('$baseUrl/api/auth/devices'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch devices: ${response.body}');
    }
  }

  /// Authenticated: Rename a paired device
  Future<Map<String, dynamic>> renameDevice(String deviceId, String newName) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.put(
      Uri.parse('$baseUrl/api/auth/devices/rename'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({
        'deviceId': deviceId,
        'deviceName': newName,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to rename device: ${response.body}');
    }
  }

  /// Authenticated: Remove a paired device
  Future<Map<String, dynamic>> removeDevice(String deviceId) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.delete(
      Uri.parse('$baseUrl/api/auth/devices/$deviceId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to remove device: ${response.body}');
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

  /// Authenticated: Delete media item from DB
  Future<void> deleteMediaItem(String id) async {
    if (_token == null) throw Exception('Unauthorized');
    final response = await http.delete(
      Uri.parse('$baseUrl/api/media/items/$id'),
      headers: {
        'Authorization': 'Bearer $_token',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete media item: ${response.body}');
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
}


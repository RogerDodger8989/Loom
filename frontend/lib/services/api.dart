import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class ApiService {
  // Configured to point to the Fastify local server.
  // In a real application, this can be dynamically entered by the user or auto-discovered via mDNS.
  final String baseUrl = 'http://localhost:8080';
  
  String? _token;

  String? get token => _token;

  /**
   * Unauthenticated: Request a temporary pairing PIN and unique Device ID
   */
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

  /**
   * Unauthenticated: Poll pairing status for a given Device ID.
   * If pairing was approved by the admin, returns the user credentials and JWT.
   */
  Future<Map<String, dynamic>> checkPairingStatus(String deviceId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/auth/pair/status?deviceId=$deviceId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['paired'] == true && data['token'] != null) {
        _token = data['token'];
      }
      return data;
    } else {
      throw Exception('Failed to check pairing status: ${response.body}');
    }
  }

  /**
   * Authenticated: Trigger a folder scan for movies, shows, or music tracks.
   */
  Future<Map<String, dynamic>> triggerLibraryScan(String folderPath, String type) async {
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
      }),
    );

    if (response.statusCode == 202) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to trigger scan: ${response.body}');
    }
  }

  /**
   * Authenticated: Fetch movies library (supports version merging / separated resolution badges)
   */
  Future<List<dynamic>> fetchMovies({bool mergeVersions = true}) async {
    if (_token == null) {
      throw Exception('Unauthorized: Log in or pair first.');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/media/movies?mergeVersions=$mergeVersions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch movies: ${response.body}');
    }
  }

  /**
   * Authenticated: Fetch shows library
   */
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

  /**
   * Authenticated: Get library scanner status
   */
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
}

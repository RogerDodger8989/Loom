import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_frontend/services/api.dart';

void main() {
  group('ApiService — JWT-avkodning (currentUserPayload)', () {
    late ApiService api;

    setUp(() {
      api = ApiService();
    });

    String _makeJwt(Map<String, dynamic> payload) {
      final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
      final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
      return '$header.$body.fakesignature';
    }

    test('returnerar null när token saknas', () {
      expect(api.currentUserPayload, isNull);
    });

    test('dekoderar token och returnerar rätt payload', () async {
      final payload = {'id': 'abc123', 'username': 'admin', 'role': 'Admin'};
      await api.saveToken(_makeJwt(payload));

      final result = api.currentUserPayload;
      expect(result, isNotNull);
      expect(result!['username'], 'admin');
      expect(result['role'], 'Admin');
      expect(result['id'], 'abc123');
    });

    test('returnerar null för en ogiltig token-sträng', () async {
      await api.saveToken('inte.en.riktig.jwt.token.alls');

      expect(api.currentUserPayload, isNull);
    });
  });

  group('ApiService — Inställningscache (loadSettingsCache / saveSettingsCache)', () {
    late ApiService api;

    setUp(() {
      api = ApiService();
    });

    test('returnerar null när inget är sparat', () {
      // Utan initStorage anropas, prefs är null → returnerar null
      expect(api.loadSettingsCache(), isNull);
    });
  });

  group('ApiService — URL-konstruktion', () {
    test('baseUrl pekar på localhost:8080', () {
      final api = ApiService();
      expect(api.baseUrl, 'http://localhost:8080');
    });

    test('logsDownloadUrl är korrekt formaterad', () {
      final api = ApiService();
      expect(api.logsDownloadUrl, contains('/api/logs/download'));
    });

    test('dbBackupUrl är korrekt formaterad', () {
      final api = ApiService();
      expect(api.dbBackupUrl, contains('/api/server/db/backup'));
    });

    test('calendarIcsUrl innehåller korrekt start- och slutdatum', () {
      final api = ApiService();
      final url = api.calendarIcsUrl(start: '2024-01-01', end: '2024-12-31');
      expect(url, contains('start=2024-01-01'));
      expect(url, contains('end=2024-12-31'));
    });
  });
}

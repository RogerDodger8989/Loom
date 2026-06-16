import 'package:flutter_test/flutter_test.dart';
import 'package:loom_frontend/models/season.dart';

void main() {
  group('Season.fromJson', () {
    test('fills in defaults when map is empty', () {
      final s = Season.fromJson(const {});
      expect(s.seasonNumber, 0);
      expect(s.name, 'Specials'); // season 0 defaults to "Specials"
      expect(s.episodeCount, 0);
      expect(s.posterPath, isNull);
    });

    test('uses provided name over generated default', () {
      final s = Season.fromJson(const {'season_number': 1, 'name': 'Säsong ett'});
      expect(s.name, 'Säsong ett');
    });

    test('generates name "Säsong N" for seasons without a name', () {
      final s = Season.fromJson(const {'season_number': 3});
      expect(s.name, 'Säsong 3');
    });

    test('generates name "Specials" for season 0 without a name', () {
      final s = Season.fromJson(const {'season_number': 0});
      expect(s.name, 'Specials');
    });

    test('parses episode_count', () {
      final s = Season.fromJson(const {'season_number': 1, 'episode_count': 10});
      expect(s.episodeCount, 10);
    });

    test('posterUrl is null when poster_path is absent', () {
      final s = Season.fromJson(const {'season_number': 1, 'name': 'S1'});
      expect(s.posterUrl, isNull);
    });

    test('posterUrl prepends TMDB base URL for relative path', () {
      final s = Season.fromJson(const {'poster_path': '/poster.jpg'});
      expect(s.posterUrl, 'https://image.tmdb.org/t/p/w300/poster.jpg');
    });

    test('posterUrl passes through absolute URL unchanged', () {
      const url = 'https://cdn.example.com/poster.jpg';
      final s = Season.fromJson(const {'poster_path': url});
      expect(s.posterUrl, url);
    });

    test('yearLabel extracts year from air_date', () {
      final s = Season.fromJson(const {'air_date': '2023-09-15'});
      expect(s.yearLabel, '2023');
    });

    test('yearLabel is empty string when air_date is absent', () {
      final s = Season.fromJson(const {});
      expect(s.yearLabel, '');
    });

    test('yearLabel is empty when air_date is shorter than 4 chars', () {
      final s = Season.fromJson(const {'air_date': '202'});
      expect(s.yearLabel, '');
    });
  });
}

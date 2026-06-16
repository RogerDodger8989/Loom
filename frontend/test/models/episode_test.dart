import 'package:flutter_test/flutter_test.dart';
import 'package:loom_frontend/models/episode.dart';

void main() {
  group('Episode.fromJson', () {
    test('fills in defaults when map is empty', () {
      final ep = Episode.fromJson(const {});
      expect(ep.id, '');
      expect(ep.seasonNumber, 0);
      expect(ep.episodeNumber, 0);
      expect(ep.title, '');
      expect(ep.isWatched, false);
      expect(ep.playbackProgress, 0);
      expect(ep.duration, 0);
      expect(ep.isUpcoming, false);
    });

    test('parses is_watched as int 1', () {
      final ep = Episode.fromJson(const {'id': 'e1', 'is_watched': 1});
      expect(ep.isWatched, true);
    });

    test('parses is_watched as bool true', () {
      final ep = Episode.fromJson(const {'id': 'e1', 'is_watched': true});
      expect(ep.isWatched, true);
    });

    test('is_watched false when 0', () {
      final ep = Episode.fromJson(const {'id': 'e1', 'is_watched': 0});
      expect(ep.isWatched, false);
    });

    test('parses season_number and episode_number as strings', () {
      final ep = Episode.fromJson(const {
        'season_number': '2',
        'episode_number': '5',
      });
      expect(ep.seasonNumber, 2);
      expect(ep.episodeNumber, 5);
    });

    test('handles non-numeric season_number gracefully', () {
      final ep = Episode.fromJson(const {'season_number': 'N/A'});
      expect(ep.seasonNumber, 0);
    });

    test('isInProgress true when progress > 60 and not watched', () {
      final ep = Episode.fromJson(const {
        'is_watched': 0,
        'playback_progress': '120',
        'duration': '3600',
      });
      expect(ep.isInProgress, true);
    });

    test('isInProgress false when watched', () {
      final ep = Episode.fromJson(const {
        'is_watched': 1,
        'playback_progress': '120',
      });
      expect(ep.isInProgress, false);
    });

    test('isInProgress false when progress <= 60', () {
      final ep = Episode.fromJson(const {
        'is_watched': 0,
        'playback_progress': '30',
      });
      expect(ep.isInProgress, false);
    });

    test('label formats S01E03 correctly', () {
      final ep = Episode.fromJson(const {'season_number': 1, 'episode_number': 3});
      expect(ep.label, 'S01E03');
    });

    test('stillUrl prepends TMDB base URL for relative paths', () {
      final ep = Episode.fromJson(const {'still_path': '/abc.jpg'});
      expect(ep.stillUrl, 'https://image.tmdb.org/t/p/w300/abc.jpg');
    });

    test('stillUrl passes through full URLs unchanged', () {
      const url = 'https://example.com/still.jpg';
      final ep = Episode.fromJson(const {'still_path': url});
      expect(ep.stillUrl, url);
    });

    test('stillUrl is null when still_path is missing', () {
      final ep = Episode.fromJson(const {});
      expect(ep.stillUrl, isNull);
    });

    test('hasFile is false when file_path is null', () {
      expect(Episode.fromJson(const {}).hasFile, false);
    });

    test('hasFile is true when file_path is set', () {
      final ep = Episode.fromJson(const {'file_path': '/media/ep.mkv'});
      expect(ep.hasFile, true);
    });

    test('copyWithWatched returns updated copy', () {
      final ep = Episode.fromJson(const {'id': 'e1', 'is_watched': 0});
      final watched = ep.copyWithWatched(true);
      expect(watched.isWatched, true);
      expect(watched.id, 'e1');
    });

    test('toJson round-trips core fields', () {
      final original = Episode.fromJson(const {
        'id': 'abc',
        'season_number': 2,
        'episode_number': 4,
        'title': 'Test',
        'is_watched': 1,
        'playback_progress': '300',
        'duration': '1800',
      });
      final json = original.toJson();
      expect(json['id'], 'abc');
      expect(json['season_number'], 2);
      expect(json['episode_number'], 4);
      expect(json['is_watched'], 1);
    });
  });
}

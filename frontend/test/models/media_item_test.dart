import 'package:flutter_test/flutter_test.dart';
import 'package:loom_frontend/models/episode.dart';
import 'package:loom_frontend/models/media_item.dart';

void main() {
  group('MediaItem.fromJson', () {
    test('fills in defaults when map is empty', () {
      final item = MediaItem.fromJson(const {});
      expect(item.id, '');
      expect(item.title, '');
      expect(item.type, '');
      expect(item.episodes, isEmpty);
      expect(item.tmdbSeasons, isEmpty);
      expect(item.isFavorite, false);
      expect(item.isInWatchlist, false);
      expect(item.myRating, 0.0);
    });

    test('parses episodes list', () {
      final item = MediaItem.fromJson(const {
        'type': 'Show',
        'episodes': [
          {'id': 'e1', 'season_number': 1, 'episode_number': 1, 'title': 'Pilot'},
          {'id': 'e2', 'season_number': 1, 'episode_number': 2, 'title': 'Ep2'},
          {'id': 'e3', 'season_number': 2, 'episode_number': 1, 'title': 'S2E1'},
        ],
      });
      expect(item.episodes.length, 3);
      expect(item.episodes[0].id, 'e1');
    });

    test('episodes is empty when key is missing', () {
      final item = MediaItem.fromJson(const {'type': 'Show'});
      expect(item.episodes, isEmpty);
    });

    test('episodes is empty when key is null', () {
      final item = MediaItem.fromJson(const {'type': 'Show', 'episodes': null});
      expect(item.episodes, isEmpty);
    });

    test('episodesBySeason groups correctly', () {
      final item = MediaItem.fromJson(const {
        'type': 'Show',
        'episodes': [
          {'id': 'e1', 'season_number': 1, 'episode_number': 1},
          {'id': 'e2', 'season_number': 1, 'episode_number': 2},
          {'id': 'e3', 'season_number': 2, 'episode_number': 1},
        ],
      });
      expect(item.episodesBySeason[1]!.length, 2);
      expect(item.episodesBySeason[2]!.length, 1);
    });

    test('isShow is true for type Show', () {
      final item = MediaItem.fromJson(const {'type': 'Show'});
      expect(item.isShow, true);
      expect(item.isMovie, false);
    });

    test('isMovie is true for type Movie', () {
      final item = MediaItem.fromJson(const {'type': 'Movie'});
      expect(item.isMovie, true);
      expect(item.isShow, false);
    });

    test('isExternal is true for external_ prefix', () {
      final item = MediaItem.fromJson(const {'id': 'external_tmdb_123', 'type': 'Movie'});
      expect(item.isExternal, true);
    });

    test('parses is_favorite as int 1', () {
      final item = MediaItem.fromJson(const {'is_favorite': 1});
      expect(item.isFavorite, true);
    });

    test('parses is_favorite as bool true', () {
      final item = MediaItem.fromJson(const {'is_favorite': true});
      expect(item.isFavorite, true);
    });

    test('myRating parsed from metadata', () {
      final item = MediaItem.fromJson(const {
        'metadata': {'my_rating': '7.5'},
      });
      expect(item.myRating, 7.5);
    });

    test('myRating defaults to 0.0 when missing', () {
      final item = MediaItem.fromJson(const {});
      expect(item.myRating, 0.0);
    });

    test('isWatched from metadata watch_status', () {
      final item = MediaItem.fromJson(const {
        'metadata': {'watch_status': 'watched'},
      });
      expect(item.isWatched, true);
    });

    test('isWatched false when watch_status is not watched', () {
      final item = MediaItem.fromJson(const {
        'metadata': {'watch_status': 'unwatched'},
      });
      expect(item.isWatched, false);
    });

    test('withEpisodeWatched marks episode and returns new instance', () {
      final item = MediaItem.fromJson(const {
        'type': 'Show',
        'episodes': [
          {'id': 'e1', 'season_number': 1, 'episode_number': 1, 'is_watched': 0},
          {'id': 'e2', 'season_number': 1, 'episode_number': 2, 'is_watched': 0},
        ],
      });
      final updated = item.withEpisodeWatched('e1', true);
      expect(updated.episodes.first.isWatched, true);
      expect(updated.episodes.last.isWatched, false);
      // original untouched
      expect(item.episodes.first.isWatched, false);
    });

    test('withSeasonWatched marks all episodes in season', () {
      final item = MediaItem.fromJson(const {
        'type': 'Show',
        'episodes': [
          {'id': 'e1', 'season_number': 1, 'episode_number': 1, 'is_watched': 0},
          {'id': 'e2', 'season_number': 1, 'episode_number': 2, 'is_watched': 0},
          {'id': 'e3', 'season_number': 2, 'episode_number': 1, 'is_watched': 0},
        ],
      });
      final updated = item.withSeasonWatched(1, true);
      final s1 = updated.episodesBySeason[1]!;
      final s2 = updated.episodesBySeason[2]!;
      expect(s1.every((e) => e.isWatched), true);
      expect(s2.every((e) => e.isWatched), false);
    });

    test('skips non-map entries in episodes list', () {
      final item = MediaItem.fromJson(const {
        'type': 'Show',
        'episodes': [
          {'id': 'e1', 'season_number': 1, 'episode_number': 1},
          'not_a_map',
          42,
          null,
        ],
      });
      expect(item.episodes.length, 1);
      expect(item.episodes.first.id, 'e1');
    });
  });

  group('Episode immutability', () {
    test('two Episodes from same json are equal in fields', () {
      const json = {'id': 'x', 'season_number': 1, 'episode_number': 2};
      final a = Episode.fromJson(json);
      final b = Episode.fromJson(json);
      expect(a.id, b.id);
      expect(a.seasonNumber, b.seasonNumber);
    });
  });
}

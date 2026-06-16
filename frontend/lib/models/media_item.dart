import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'episode.dart';
import 'season.dart';

@immutable
class MediaItem {
  final String id;
  final String title;
  final String type;
  final int? year;
  final String? plot;
  final String? posterPath;
  final String? fanartPath;
  final String? tmdbId;
  final String? imdbId;
  final String? collectionId;
  final String? originalTitle;
  final String? filePath;
  final double myRating;
  final bool isWatched;
  final bool isFavorite;
  final bool isInWatchlist;
  final int savedProgressSeconds;
  final List<Episode> episodes;
  final List<Season> tmdbSeasons;
  // Kept for fields not yet covered by typed properties (crew, ratings, etc.)
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> versions;

  const MediaItem({
    required this.id,
    required this.title,
    required this.type,
    this.year,
    this.plot,
    this.posterPath,
    this.fanartPath,
    this.tmdbId,
    this.imdbId,
    this.collectionId,
    this.originalTitle,
    this.filePath,
    required this.myRating,
    required this.isWatched,
    required this.isFavorite,
    required this.isInWatchlist,
    required this.savedProgressSeconds,
    required this.episodes,
    required this.tmdbSeasons,
    required this.metadata,
    required this.versions,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : <String, dynamic>{};

    final rawEpisodes = json['episodes'];
    final episodes = rawEpisodes is List
        ? rawEpisodes
            .whereType<Map<String, dynamic>>()
            .map(Episode.fromJson)
            .toList()
        : const <Episode>[];

    return MediaItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      year: json['year'] == null ? null : int.tryParse(json['year'].toString()),
      plot: json['plot']?.toString(),
      posterPath: json['poster_path']?.toString(),
      fanartPath: json['fanart_path']?.toString(),
      tmdbId: json['tmdb_id']?.toString(),
      imdbId: json['imdb_id']?.toString(),
      collectionId: json['collection_id']?.toString(),
      originalTitle: json['original_title']?.toString(),
      filePath: json['file_path']?.toString(),
      myRating:
          double.tryParse(meta['my_rating']?.toString() ?? '0') ?? 0.0,
      isWatched: meta['watch_status'] == 'watched',
      isFavorite:
          json['is_favorite'] == true || json['is_favorite'] == 1,
      isInWatchlist: json['is_in_watchlist'] as bool? ?? false,
      savedProgressSeconds:
          int.tryParse(meta['playback_progress']?.toString() ?? '0') ?? 0,
      episodes: episodes,
      tmdbSeasons: _parseSeasons(meta['seasons_json']),
      metadata: meta,
      versions: _parseVersions(json['versions']),
    );
  }

  static List<Season> _parseSeasons(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Season.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          return parsed
              .whereType<Map>()
              .map((e) => Season.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }
    return const [];
  }

  static List<Map<String, dynamic>> _parseVersions(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }

  bool get isShow => type == 'Show';
  bool get isMovie => type == 'Movie';
  bool get isExternal => id.startsWith('external_');
  bool get hasFile => filePath != null && filePath!.isNotEmpty;

  Map<int, List<Episode>> get episodesBySeason {
    final map = <int, List<Episode>>{};
    for (final ep in episodes) {
      map.putIfAbsent(ep.seasonNumber, () => []).add(ep);
    }
    return map;
  }

  MediaItem withEpisodeWatched(String episodeId, bool watched) {
    final updated =
        episodes.map((ep) => ep.id == episodeId ? ep.copyWithWatched(watched) : ep).toList();
    return _copyWith(episodes: updated);
  }

  MediaItem withSeasonWatched(int seasonNumber, bool watched) {
    final updated = episodes
        .map((ep) => ep.seasonNumber == seasonNumber ? ep.copyWithWatched(watched) : ep)
        .toList();
    return _copyWith(episodes: updated);
  }

  MediaItem _copyWith({List<Episode>? episodes}) => MediaItem(
        id: id,
        title: title,
        type: type,
        year: year,
        plot: plot,
        posterPath: posterPath,
        fanartPath: fanartPath,
        tmdbId: tmdbId,
        imdbId: imdbId,
        collectionId: collectionId,
        originalTitle: originalTitle,
        filePath: filePath,
        myRating: myRating,
        isWatched: isWatched,
        isFavorite: isFavorite,
        isInWatchlist: isInWatchlist,
        savedProgressSeconds: savedProgressSeconds,
        episodes: episodes ?? this.episodes,
        tmdbSeasons: tmdbSeasons,
        metadata: metadata,
        versions: versions,
      );
}

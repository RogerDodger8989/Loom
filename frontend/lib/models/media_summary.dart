import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Lightweight summary of a media item — used by list views and poster grids.
///
/// Covers the fields [UnifiedPosterCard] and poster-grid screens need.
/// Heavy fields (episodes, cast, TMDB seasons) live on [MediaItem] instead.
/// The [toJson] bridge lets unmigrated callbacks receive a raw map until
/// they are individually migrated to accept [MediaSummary] directly.
@immutable
class MediaSummary {
  final String id;
  final String title;
  final String? originalTitle;
  final String type; // 'Movie' | 'Show'
  final int? year;
  final String? posterPath;
  final String? tmdbId;
  final bool isFavorite;
  final bool isInWatchlist;
  // Kept as raw lists/maps — typed in a later step
  final List<Map<String, dynamic>> versions;
  final Map<String, dynamic> metadata;
  // Top-level resolution field (some endpoints return it outside metadata)
  final String? resolution;

  const MediaSummary({
    required this.id,
    required this.title,
    this.originalTitle,
    required this.type,
    this.year,
    this.posterPath,
    this.tmdbId,
    required this.isFavorite,
    required this.isInWatchlist,
    required this.versions,
    required this.metadata,
    this.resolution,
  });

  factory MediaSummary.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : <String, dynamic>{};

    final rawVersions = json['versions'];
    final versions = rawVersions is List
        ? rawVersions.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
        : const <Map<String, dynamic>>[];

    return MediaSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      originalTitle: json['original_title']?.toString(),
      type: json['type']?.toString() ?? 'Movie',
      year: _asInt(json['year']),
      posterPath: json['poster_path']?.toString(),
      tmdbId: json['tmdb_id']?.toString(),
      isFavorite: json['is_favorite'] == true || json['is_favorite'] == 1,
      isInWatchlist: json['is_in_watchlist'] as bool? ?? false,
      versions: versions,
      metadata: meta,
      resolution: json['resolution']?.toString(),
    );
  }

  bool get isShow => type == 'Show';
  bool get isMovie => type == 'Movie';
  bool get isExternal => id.startsWith('external_');
  bool get isWatched => metadata['watch_status'] == 'watched';
  int get playbackProgress =>
      int.tryParse(metadata['playback_progress']?.toString() ?? '') ?? 0;

  /// Bridge method — returns a raw map so that callbacks whose receivers
  /// have not yet been migrated can accept this value unchanged.
  /// Remove call sites as those receivers are individually migrated.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (originalTitle != null) 'original_title': originalTitle,
        'type': type,
        if (year != null) 'year': year,
        if (posterPath != null) 'poster_path': posterPath,
        if (tmdbId != null) 'tmdb_id': tmdbId,
        'is_favorite': isFavorite,
        'is_in_watchlist': isInWatchlist,
        'versions': versions,
        'metadata': metadata,
        if (resolution != null) 'resolution': resolution,
      };

  MediaSummary copyWithFavorite(bool favorite) => MediaSummary(
        id: id,
        title: title,
        originalTitle: originalTitle,
        type: type,
        year: year,
        posterPath: posterPath,
        tmdbId: tmdbId,
        isFavorite: favorite,
        isInWatchlist: isInWatchlist,
        versions: versions,
        metadata: metadata,
        resolution: resolution,
      );

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }

  /// Parses a list API response — e.g. /api/media/movies or /api/media/shows.
  static List<MediaSummary> fromJsonList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MediaSummary.fromJson)
        .toList();
  }
}

/// Parses a [next_episode_to_air] value from metadata, handling both
/// inline Map and JSON-encoded String forms.
Map<String, dynamic>? parseNextEpisodeToAir(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
  }
  return null;
}

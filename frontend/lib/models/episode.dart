import 'package:flutter/foundation.dart';

@immutable
class Episode {
  final String id;
  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final String? filePath;
  final bool isWatched;
  final int playbackProgress;
  final int duration;
  final String? stillPath;
  final String? airDate;
  final String? overview;
  final bool isUpcoming;

  const Episode({
    required this.id,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    this.filePath,
    required this.isWatched,
    required this.playbackProgress,
    required this.duration,
    this.stillPath,
    this.airDate,
    this.overview,
    this.isUpcoming = false,
  });

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id']?.toString() ?? '',
        seasonNumber: _asInt(json['season_number'], 0),
        episodeNumber: _asInt(json['episode_number'], 0),
        title: json['title']?.toString() ?? '',
        filePath: json['file_path']?.toString(),
        isWatched: json['is_watched'] == 1 || json['is_watched'] == true,
        playbackProgress: _asInt(json['playback_progress'], 0),
        duration: _asInt(json['duration'], 0),
        stillPath: json['still_path']?.toString(),
        airDate: json['air_date']?.toString(),
        overview: json['overview']?.toString(),
        isUpcoming: false,
      );

  static int _asInt(dynamic v, int fallback) =>
      int.tryParse(v?.toString() ?? '') ?? fallback;

  bool get hasId => id.isNotEmpty;
  bool get hasFile => filePath != null && filePath!.isNotEmpty;
  bool get isInProgress => playbackProgress > 60 && !isWatched;

  String get label =>
      'S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';

  String? get stillUrl {
    if (stillPath == null || stillPath!.isEmpty) return null;
    return stillPath!.startsWith('http')
        ? stillPath
        : 'https://image.tmdb.org/t/p/w300$stillPath';
  }

  Episode copyWithWatched(bool watched) => Episode(
        id: id,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
        title: title,
        filePath: filePath,
        isWatched: watched,
        playbackProgress: playbackProgress,
        duration: duration,
        stillPath: stillPath,
        airDate: airDate,
        overview: overview,
        isUpcoming: isUpcoming,
      );

  // Bridge for screens not yet migrated to Episode (e.g. EpisodeDetailsScreen)
  Map<String, dynamic> toJson() => {
        'id': id,
        'season_number': seasonNumber,
        'episode_number': episodeNumber,
        'title': title,
        'file_path': filePath,
        'is_watched': isWatched ? 1 : 0,
        'playback_progress': playbackProgress,
        'duration': duration,
        'still_path': stillPath,
        'air_date': airDate,
        'overview': overview,
      };
}

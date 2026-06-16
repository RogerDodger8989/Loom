import 'package:flutter/foundation.dart';

@immutable
class Season {
  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String? posterPath;
  final String? airDate;
  final String? overview;

  const Season({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    this.posterPath,
    this.airDate,
    this.overview,
  });

  factory Season.fromJson(Map<String, dynamic> json) {
    final sNum = (json['season_number'] as num?)?.toInt() ?? 0;
    return Season(
      seasonNumber: sNum,
      name: json['name']?.toString() ??
          (sNum == 0 ? 'Specials' : 'Säsong $sNum'),
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      posterPath: json['poster_path']?.toString(),
      airDate: json['air_date']?.toString(),
      overview: json['overview']?.toString(),
    );
  }

  String? get posterUrl {
    if (posterPath == null || posterPath!.isEmpty) return null;
    return posterPath!.startsWith('http')
        ? posterPath
        : 'https://image.tmdb.org/t/p/w300$posterPath';
  }

  String get yearLabel {
    final date = airDate ?? '';
    return date.length >= 4 ? date.substring(0, 4) : '';
  }
}

part of '../media_details_screen.dart';

extension MediaLayoutTabExtension on _MediaDetailsScreenState {
Widget _buildContent(BuildContext context, Map<String, dynamic> media) {
    final title = media['title'] ?? 'Unknown Title';
    final year = media['year']?.toString() ?? '';
    final plot = media['plot'] ?? 'Ingen beskrivning tillgänglig.';
    final posterPath = media['poster_path'];
    final fanartPath = media['fanart_path'];
    final collectionName = media['collection_name'];
    final collectionId = media['collection_id'];
    final trailerUrl = media['metadata']?['trailer_url'];
    final metadata = (media['metadata'] is Map)
        ? media['metadata'] as Map<String, dynamic>
        : {};
    final tagline = metadata['tagline'] as String?;
    final genresList = (media['genre'] as String? ?? '')
        .split(', ')
        .where((g) => g.isNotEmpty)
        .toList();
    final ratings = (metadata['ratings'] is Map)
        ? metadata['ratings'] as Map<String, dynamic>
        : {};
    final cast =
        (metadata['cast'] is List) ? metadata['cast'] as List<dynamic> : [];
    final keywords = (metadata['keywords'] is List)
        ? metadata['keywords'] as List<dynamic>
        : [];
    final productionCompanies = (metadata['production_companies'] is List)
        ? metadata['production_companies'] as List<dynamic>
        : [];
    final productionCountries = (metadata['production_countries'] is List)
        ? metadata['production_countries'] as List<dynamic>
        : [];
    // Director is now stored as an object with id and name
    final directorData = metadata['director'] is Map
        ? metadata['director'] as Map<String, dynamic>
        : metadata['director'] is String
            ? {'name': metadata['director']}
            : null;
    final directorName = directorData?['name'] as String?;
    final directorId = directorData?['id']?.toString();

    List<Map<String, dynamic>> parseCrewList(dynamic raw) {
      if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (raw is String) {
        try { return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(); } catch (_) {}
      }
      return [];
    }
    final producers = parseCrewList(metadata['producers']);
    final writers = parseCrewList(metadata['writers']);
    final composers = parseCrewList(metadata['composers']);

    // TV-serie specifik data
    final isShow = (media['type']?.toString() ?? '') == 'Show';
    final showStatus = metadata['status']?.toString();
    final nextEpisodeRaw = metadata['next_episode_to_air'];
    final nextEpisodeToAir = nextEpisodeRaw is Map<String, dynamic>
        ? nextEpisodeRaw
        : (nextEpisodeRaw is String && nextEpisodeRaw.isNotEmpty)
            ? (() { try { return Map<String, dynamic>.from(jsonDecode(nextEpisodeRaw) as Map); } catch (_) { return null; } })()
            : null;
    final createdBy = parseCrewList(metadata['created_by']);
    final networks = (metadata['networks'] is List)
        ? (metadata['networks'] as List<dynamic>).map((n) => n.toString()).toList()
        : metadata['networks'] is String
            ? [metadata['networks'].toString()]
            : <String>[];

    final logoPath = metadata['logo_path'] as String?;
    final providers = (metadata['watch_providers'] is Map &&
            metadata['watch_providers']['SE'] is Map)
        ? (metadata['watch_providers']['SE']['flatrate'] as List<dynamic>? ??
            [])
        : [];
    final awardsValue = metadata['awards'] ??
        metadata['awards_text'] ??
        metadata['award'] ??
        metadata['prizes'] ??
        metadata['omdb_awards'] ??
        metadata['imdb_awards'];
    final awardsString =
        awardsValue is String ? awardsValue : awardsValue?.toString();

    debugPrint(
        '[Flutter Details] Metadata rating keys present: ${metadata.keys.where((k) => k.contains("rating") || k.contains("vote")).toList()}');
    debugPrint(
        '[Flutter Details] imdb_rating: ${metadata["imdb_rating"]} (${metadata["imdb_rating"].runtimeType}), simkl_rating: ${metadata["simkl_rating"]} (${metadata["simkl_rating"].runtimeType}), trakt_rating: ${metadata["trakt_rating"]} (${metadata["trakt_rating"].runtimeType})');

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fanart & Hero Column
            Stack(
              children: [
                // Background fanart with mask
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  width: double.infinity,
                  child: fanartPath != null
                      ? ShaderMask(
                          shaderCallback: (rect) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black,
                                Colors.black,
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.45, 1.0],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: Image.network(fanartPath, fit: BoxFit.cover),
                        )
                      : Container(color: const Color(0xFF15102A)),
                ),

                // Hero Content overlay
                Positioned(
                  bottom: 0,
                  left: 40,
                  right: 40,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Poster column with logo above
                      if (posterPath != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ClearLOGO above poster (constrained to poster width)
                            if (logoPath != null) ...[
                              SizedBox(
                                width: 220,
                                height: 80,
                                child: Image.network(
                                  logoPath,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            // Poster with hover effect
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) =>
                                  setState(() => _isCoverHovered = true),
                              onExit: (_) =>
                                  setState(() => _isCoverHovered = false),
                              child: Listener(
                                onPointerDown: widget.mediaId.startsWith('external_') ? null : (event) {
                                  if (event.buttons == kSecondaryMouseButton) {
                                    widget.onContextMenu?.call(widget.mediaId, event.position);
                                  }
                                },
                                child: GestureDetector(
                                onTap: widget.mediaId.startsWith('external_')
                                    ? _toggleWatchlist
                                    : _playMedia,
                                child: Container(
                                  width: 220,
                                  height: 330,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.6),
                                          blurRadius: 24,
                                          offset: const Offset(0, 12)),
                                    ],
                                    image: DecorationImage(
                                        image: NetworkImage(posterPath),
                                        fit: BoxFit.cover),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      children: [
                                        AnimatedOpacity(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          opacity: _isCoverHovered ? 1.0 : 0.0,
                                          child: Container(
                                            color: Colors.black
                                                .withValues(alpha: 0.55),
                                            child: Center(
                                              child: CircleAvatar(
                                                radius: 36,
                                                backgroundColor:
                                                    const Color(0xFF8A5BFF),
                                                child: Icon(
                                                  widget.mediaId.startsWith(
                                                          'external_')
                                                      ? (_isInWatchlist
                                                          ? Icons
                                                              .playlist_add_check
                                                          : Icons.playlist_add)
                                                      : Icons.play_arrow,
                                                  size: 40,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                ),
                              ),
                            ),
                            // Runtime (speltid) under poster
                            Builder(builder: (context) {
                              final meta = _mediaData?['metadata'] ?? {};
                              int durationSec = int.tryParse(meta['duration']?.toString() ?? '') ?? 0;
                              if (durationSec == 0) {
                                final runtimeMinutes = int.tryParse(meta['runtime']?.toString() ?? '') ?? 0;
                                durationSec = runtimeMinutes * 60;
                              }
                              if (durationSec == 0) return const SizedBox.shrink();
                              final totalMin = (durationSec / 60).round();
                              final h = totalMin ~/ 60;
                              final m = totalMin % 60;
                              final label = h > 0 ? '${h}h ${m}min' : '${m}min';
                              return Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Container(
                                  width: 220,
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.schedule, color: Colors.white38, size: 13),
                                      const SizedBox(width: 5),
                                      Text(
                                        label,
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),

                            // Progress bar and minutes-left when in-progress
                            if (_savedProgressSeconds > 0) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 220,
                                child: Builder(builder: (context) {
                                  final meta = _mediaData?['metadata'] ?? {};
                                  int durationSec = int.tryParse(
                                          meta['duration']?.toString() ?? '') ??
                                      0;
                                  if (durationSec == 0) {
                                    final runtimeMinutes = int.tryParse(
                                            meta['runtime']?.toString() ??
                                                '') ??
                                        0;
                                    durationSec = runtimeMinutes * 60;
                                  }
                                  if (durationSec == 0) {
                                    durationSec =
                                        7200; // 120 min fallback to prevent indeterminate/rolling line
                                  }
                                  final progress = _savedProgressSeconds;
                                  final ratio =
                                      (progress / durationSec).clamp(0.0, 1.0);
                                  final playedMin = (progress / 60).ceil();
                                  final leftMin =
                                      ((durationSec - progress) / 60).ceil();

                                  return Column(
                                    children: [
                                      LinearProgressIndicator(
                                        value: ratio,
                                        color: const Color(0xFF8A5BFF),
                                        backgroundColor: Colors.white12,
                                        minHeight: 4,
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8, horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.55),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.08)),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$playedMin min spelat, ${leftMin > 0 ? leftMin : 0} min kvar',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ] else if (_isWatched) ...[
                              const SizedBox(height: 12),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: _toggleWatchStatus,
                                  child: Container(
                                    width: 220,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: const Color(0xFF00E676)
                                              .withValues(alpha: 0.4),
                                          width:
                                              1.2), // neon green glowing border
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF00E676)
                                              .withValues(alpha: 0.1),
                                          blurRadius: 4,
                                        )
                                      ],
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            color: Color(0xFF00E676), size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Sedd',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      const SizedBox(width: 40),

                      // Title & Metadata info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Favorite star + Title row
                            if (!widget.mediaId.startsWith('external_'))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: _isFavorite ? 'Ta bort favorit' : 'Markera som favorit',
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: _toggleFavorite,
                                          child: AnimatedSwitcher(
                                            duration: const Duration(milliseconds: 200),
                                            child: Text(
                                              String.fromCharCode((_isFavorite ? Icons.star : Icons.star_border).codePoint),
                                              key: ValueKey(_isFavorite),
                                              style: TextStyle(
                                                fontFamily: Icons.star.fontFamily,
                                                package: Icons.star.fontPackage,
                                                fontSize: 28,
                                                color: _isFavorite ? const Color(0xFFFFD65C) : Colors.white,
                                                shadows: const [
                                                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1.5, 1.5)),
                                                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1.5, 1.5)),
                                                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1.5, -1.5)),
                                                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(-1.5, -1.5)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Title (Year) with translated/original logic
                            Builder(
                              builder: (context) {
                                final originalTitle =
                                    media['original_title'] as String?;
                                final hasOriginal = originalTitle != null &&
                                    originalTitle.isNotEmpty;
                                final isOriginalStyle =
                                    _titleDisplayStyle == 'Original';

                                String mainDisplayTitle = title;
                                String? subtitleDisplayTitle;

                                if (isOriginalStyle && hasOriginal) {
                                  mainDisplayTitle = originalTitle;
                                  if (originalTitle.toLowerCase() !=
                                      title.toLowerCase()) {
                                    subtitleDisplayTitle =
                                        'Översatt titel: $title';
                                  }
                                } else if (!isOriginalStyle && hasOriginal) {
                                  mainDisplayTitle = title;
                                  if (originalTitle.toLowerCase() !=
                                      title.toLowerCase()) {
                                    subtitleDisplayTitle =
                                        'Originaltitel: $originalTitle';
                                  }
                                }

                                final releaseVersion =
                                    metadata['release_version']?.toString() ??
                                        '';
                                final versionSuffix = _showReleaseVersion && releaseVersion.isNotEmpty
                                    ? ' [$releaseVersion]'
                                    : '';

                                // For ended shows show year range (xxxx–xxxx), for ongoing show (xxxx–)
                                String yearDisplay = year;
                                if (isShow && year.isNotEmpty) {
                                  final statusLower = (showStatus ?? '').toLowerCase();
                                  if (statusLower == 'ended' || statusLower == 'canceled' || statusLower == 'cancelled') {
                                    final lastAirRaw = metadata['last_air_date']?.toString() ?? '';
                                    if (lastAirRaw.length >= 4) {
                                      final endYear = lastAirRaw.substring(0, 4);
                                      if (endYear != year) yearDisplay = '$year–$endYear';
                                    }
                                  } else if (statusLower.isNotEmpty) {
                                    yearDisplay = '$year–';
                                  }
                                }

                                final displayTitle = yearDisplay.isNotEmpty
                                    ? '$mainDisplayTitle ($yearDisplay)$versionSuffix'
                                    : '$mainDisplayTitle$versionSuffix';

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Stack(
                                      children: [
                                        Text(
                                          displayTitle,
                                          style: TextStyle(
                                            fontSize: 44,
                                            fontWeight: FontWeight.bold,
                                            height: 1.1,
                                            letterSpacing: -0.5,
                                            foreground: Paint()
                                              ..style = PaintingStyle.stroke
                                              ..strokeWidth = 2.2
                                              ..color = Colors.black,
                                          ),
                                        ),
                                        Text(
                                          displayTitle,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 44,
                                            fontWeight: FontWeight.bold,
                                            height: 1.1,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (subtitleDisplayTitle != null) ...[
                                      const SizedBox(height: 6),
                                      Stack(
                                        children: [
                                          Text(
                                            subtitleDisplayTitle,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontStyle: FontStyle.italic,
                                              fontWeight: FontWeight.w500,
                                              foreground: Paint()
                                                ..style = PaintingStyle.stroke
                                                ..strokeWidth = 1.8
                                                ..color = Colors.black,
                                            ),
                                          ),
                                          Text(
                                            subtitleDisplayTitle,
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withValues(alpha: 0.85),
                                              fontSize: 16,
                                              fontStyle: FontStyle.italic,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),

                            // Show status badge
                            if (isShow && showStatus != null && showStatus.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _buildShowStatusBadge(showStatus, nextEpisodeToAir: nextEpisodeToAir),
                            ],

                            // Skapare (Creator/Showrunner) for shows
                            if (isShow && createdBy.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildCrewRow('Skapare', createdBy),
                            ],

                            // Director for movies
                            if (!isShow && directorName != null) ...[
                              const SizedBox(height: 8),
                              _buildCrewRow('Regi', [{'name': directorName, 'id': directorId}]),
                            ],

                            // Producers (Producent)
                            if (producers.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildCrewRow('Producent', producers),
                            ],

                            // Writers (Manus)
                            if (writers.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildCrewRow('Manus', writers),
                            ],

                            // Composers (Musik)
                            if (composers.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildCrewRow('Musik', composers),
                            ],

                            const SizedBox(height: 12),

                            // Subtitle Metadata details with highly legible high-contrast outlines
                            Row(
                              children: [
                                // PG Box with drop shadow and outline
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    border: Border.all(
                                        color: Colors.black, width: 2),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2)),
                                    ],
                                  ),
                                  child: const Text('PG-13',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      )),
                                ),
                                const SizedBox(width: 16),

                                // Collection Banner with clear black outline
                                if (collectionName != null &&
                                    collectionName.toString().isNotEmpty) ...[
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () {
                                        _showCollectionDialog(
                                            collectionName.toString(),
                                            collectionId?.toString());
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFB593FF)
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.black, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 4,
                                                offset: const Offset(0, 2)),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.layers,
                                                color: Color(0xFFB593FF),
                                                size: 14),
                                            const SizedBox(width: 6),
                                            Text(
                                              collectionName.toString(),
                                              style: const TextStyle(
                                                color: Color(0xFFB593FF),
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (productionCompanies.isNotEmpty ||
                                productionCountries.isNotEmpty) ...[
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  ...productionCompanies.take(3).map((company) {
                                    final companyName = company is Map
                                        ? (company['name']?.toString() ?? '')
                                        : company.toString();
                                    final logoPath = company is Map
                                        ? company['logo_path']?.toString()
                                        : null;

                                    if (companyName.isEmpty)
                                      return const SizedBox.shrink();

                                    if (logoPath != null && logoPath.isNotEmpty) {
                                      return Tooltip(
                                        message: companyName,
                                        child: Container(
                                          height: 32,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                          ),
                                          child: Image.network(
                                            logoPath,
                                            height: 24,
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.business, size: 16),
                                          ),
                                        ),
                                      );
                                    }

                                    return Chip(
                                      avatar: const Icon(Icons.business,
                                          size: 16, color: Color(0xFF8A5BFF)),
                                      label: Text(companyName,
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.06),
                                      side: BorderSide(
                                          color: Colors.white
                                              .withValues(alpha: 0.08)),
                                    );
                                  }),
                                  ...productionCountries.map((country) {
                                    final countryName = country is Map
                                        ? (country['name']?.toString() ?? '')
                                        : country.toString();
                                    final isoRaw = country is Map
                                        ? (country['iso_3166_1']?.toString() ??
                                            '')
                                        : '';
                                    final iso = isoRaw.toUpperCase();
                                    if (countryName.isEmpty)
                                      return const SizedBox.shrink();

                                    return Tooltip(
                                      message: countryName,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.06),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: 0.08)),
                                        ),
                                        child: (iso.length == 2)
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                                child: Image.network(
                                                  'https://flagcdn.com/w20/${iso.toLowerCase()}.png',
                                                  width: 20,
                                                  height: 14,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      Text(iso,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors
                                                                      .white54)),
                                                ),
                                              )
                                            : Text(
                                                countryName,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white70),
                                              ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],

                            // Clickable Genre Badges
                            Wrap(
                              spacing: 8,
                              children: genresList.map((g) {
                                return ActionChip(
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.06),
                                  side: BorderSide(
                                      color:
                                          Colors.white.withValues(alpha: 0.08)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  label: Text(g,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                  onPressed: () {
                                    final isShow = _mediaData?['type']?.toString() == 'Show';
                                    if (isShow && widget.onShowGenreSelected != null) {
                                      widget.onShowGenreSelected!(g);
                                    } else if (widget.onGenreSelected != null) {
                                      widget.onGenreSelected!(g);
                                    } else {
                                      Navigator.pop(context, g);
                                    }
                                  },
                                );
                              }).toList(),
                            ),

                            // Awards / Priser placed directly under Genre
                            _buildAwardsRow(awardsString),
                            const SizedBox(height: 24),

                            // Control Actions Row
                            Row(
                              children: [
                                if (widget.mediaId.startsWith('external_')) ...[
                                  // Watchlist Add/Remove Action for external item
                                  ElevatedButton.icon(
                                    onPressed: _isWatchlistLoading
                                        ? null
                                        : _toggleWatchlist,
                                    icon: _isWatchlistLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2),
                                          )
                                        : Icon(
                                            _isInWatchlist
                                                ? Icons.playlist_add_check
                                                : Icons.playlist_add,
                                            size: 28),
                                    label: Text(
                                      _isInWatchlist
                                          ? 'I bevakningslistan'
                                          : 'Lägg till i bevakningslista',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isInWatchlist
                                          ? const Color(0xFF281E46)
                                          : const Color(0xFF8A5BFF),
                                      foregroundColor: Colors.white,
                                      side: _isInWatchlist
                                          ? const BorderSide(
                                              color: Color(0xFF8A5BFF),
                                              width: 1.5)
                                          : null,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 36, vertical: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(30)),
                                      elevation: 8,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  if (trailerUrl != null &&
                                      trailerUrl.toString().isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.only(right: 16),
                                      child: OutlinedButton.icon(
                                        onPressed: () => _launchTrailer(
                                            trailerUrl.toString(),
                                            title.toString(),
                                            year.toString()),
                                        icon: const Icon(Icons.slideshow,
                                            size: 22, color: Colors.white),
                                        label: const Text('Trailer',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold)),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                              color: Colors.white54,
                                              width: 1.5),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 16),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(30)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ] else ...[
                                  ElevatedButton.icon(
                                    onPressed: _playMedia,
                                    icon:
                                        const Icon(Icons.play_arrow, size: 28),
                                    label: Text(
                                      _savedProgressSeconds > 0
                                          ? 'Återuppta'
                                          : 'Spela',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF8A5BFF),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 36, vertical: 16),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(30)),
                                      elevation: 8,
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  Padding(
                                    padding: const EdgeInsets.only(right: 16),
                                    child: OutlinedButton.icon(
                                      onPressed: () => _launchTrailer(
                                          trailerUrl?.toString(),
                                          title.toString(),
                                          year.toString()),
                                      icon: const Icon(Icons.slideshow,
                                          size: 22, color: Colors.white),
                                      label: const Text('Trailer',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Colors.white54, width: 1.5),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 16),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(30)),
                                      ),
                                    ),
                                  ),

                                  // Dynamic kebab Menu button frambringande av actions
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color:
                                          Colors.black.withValues(alpha: 0.55),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Theme(
                                      data: Theme.of(context).copyWith(
                                        cardColor: const Color(0xFF15102A),
                                      ),
                                      child: PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_horiz,
                                            size: 26, color: Colors.white70),
                                        tooltip: 'Fler åtgärder',
                                        onSelected: (value) async {
                                          if (value == 'playlist') {
                                            _showPlaylistDialog();
                                          } else if (value == 'watch') {
                                            _toggleWatchStatus();
                                          } else if (value == 'refresh') {
                                            try {
                                              setState(() => _isLoading = true);
                                              await widget.apiService
                                                  .refreshMediaMetadata(
                                                      widget.mediaId);
                                              _fetchDetails();
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Metadata har uppdaterats online!'),
                                                    backgroundColor:
                                                        Color(0xFF8A5BFF)),
                                              );
                                            } catch (e) {
                                              setState(
                                                  () => _isLoading = false);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'Misslyckades uppdatera: $e'),
                                                    backgroundColor:
                                                        Colors.redAccent),
                                              );
                                            }
                                          } else if (value == 'analyze') {
                                            try {
                                              setState(() => _isLoading = true);
                                              await widget.apiService
                                                  .analyzeMediaItem(
                                                      widget.mediaId);
                                              _fetchDetails();
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Mediefilen har analyserats om!'),
                                                    backgroundColor:
                                                        Color(0xFF8A5BFF)),
                                              );
                                            } catch (e) {
                                              setState(
                                                  () => _isLoading = false);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'Misslyckades analysera: $e'),
                                                    backgroundColor:
                                                        Colors.redAccent),
                                              );
                                            }
                                          } else if (value == 'match') {
                                            _showFixMatchDialog();
                                          } else if (value == 'unmatch') {
                                            try {
                                              setState(() => _isLoading = true);
                                              await widget.apiService
                                                  .unmatchMediaItem(
                                                      widget.mediaId);
                                              _fetchDetails();
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Matchning borttagen!'),
                                                    backgroundColor:
                                                        Color(0xFF8A5BFF)),
                                              );
                                            } catch (e) {
                                              setState(
                                                  () => _isLoading = false);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(
                                                        'Misslyckades ta bort matchning: $e'),
                                                    backgroundColor:
                                                        Colors.redAccent),
                                              );
                                            }
                                          } else if (value == 'delete') {
                                            // Confirm dialog
                                            final confirm =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor:
                                                    const Color(0xFF15102A),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(16),
                                                  side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                                                ),
                                                title: const Row(
                                                  children: [
                                                    Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
                                                    SizedBox(width: 10),
                                                    Text('Flytta till papperskorg?',
                                                        style: TextStyle(color: Colors.white, fontSize: 18)),
                                                  ],
                                                ),
                                                content: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Filmen tas bort från biblioteket och filen på hårddisken flyttas till en .trash-mapp.',
                                                      style: const TextStyle(color: Colors.white70, height: 1.4),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Container(
                                                      padding: const EdgeInsets.all(10),
                                                      decoration: BoxDecoration(
                                                        color: Colors.redAccent.withValues(alpha: 0.08),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                                                      ),
                                                      child: const Row(
                                                        children: [
                                                          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                                                          SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              'Filen raderas från hårddisken om du tömmer papperskorgen i Inställningar.',
                                                              style: TextStyle(color: Colors.orange, fontSize: 12, height: 1.4),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                actions: [
                                                  OutlinedButton(
                                                    onPressed: () => Navigator.pop(ctx, false),
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.white70,
                                                      side: const BorderSide(color: Colors.white24),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                    ),
                                                    child: const Text('Avbryt'),
                                                  ),
                                                  ElevatedButton.icon(
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    icon: const Icon(Icons.delete_outline, size: 18),
                                                    label: const Text('Flytta till papperskorg'),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: Colors.redAccent,
                                                      foregroundColor: Colors.white,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              try {
                                                await widget.apiService
                                                    .deleteMediaItem(
                                                        widget.mediaId);
                                                if (widget.onBack != null) {
                                                  widget.onBack!();
                                                } else {
                                                  Navigator.pop(context);
                                                }
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'Media raderad från biblioteket.'),
                                                      backgroundColor:
                                                          Color(0xFF8A5BFF)),
                                                );
                                              } catch (e) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                      content: Text(
                                                          'Misslyckades ta bort: $e'),
                                                      backgroundColor:
                                                          Colors.redAccent),
                                                );
                                              }
                                            }
                                          } else if (value == 'scan_chapters') {
                                            try {
                                              await widget.apiService.scanChapters(widget.mediaId);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Kapitelskanning startad i bakgrunden. Intro/outro-knappar visas när det är klart!'),
                                                  backgroundColor: Color(0xFF8A5BFF),
                                                  duration: Duration(seconds: 4),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Skanning misslyckades: $e'), backgroundColor: Colors.redAccent),
                                              );
                                            }
                                          } else if (value == 'edit') {
                                            widget.onEdit?.call();
                                          } else if (value == 'info') {
                                            showDialog(
                                              context: context,
                                              barrierDismissible: true,
                                              builder: (_) => MediaInfoDialog(
                                                mediaId: widget.mediaId,
                                                title: _mediaData?['title']?.toString() ?? 'Media',
                                                apiService: widget.apiService,
                                              ),
                                            );
                                          } else if (value == 'statistics') {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Statistik kommer snart!'),
                                                backgroundColor:
                                                    Color(0xFF8A5BFF),
                                              ),
                                            );
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'playlist',
                                            child: Text(
                                                'Lägg till på spellista',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          PopupMenuItem(
                                            value: 'watch',
                                            child: Text(
                                                _isWatched
                                                    ? 'Markera som osedd'
                                                    : 'Markera som visad',
                                                style: const TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'refresh',
                                            child: Text('Uppdatera metadata',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'analyze',
                                            child: Text('Analysera',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          if (!widget.mediaId.startsWith('external_'))
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Redigera', style: TextStyle(color: Colors.white)),
                                            ),
                                          const PopupMenuItem(
                                            value: 'match',
                                            child: Text('Fixa matchning',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'unmatch',
                                            child: Text('Ta bort matchning',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'scan_chapters',
                                            child: Text('Skanna kapitel/intro',
                                                style: TextStyle(
                                                    color: Colors.white70)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Ta bort',
                                                style: TextStyle(
                                                    color: Colors.redAccent)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'info',
                                            child: Text('Info',
                                                style: TextStyle(
                                                    color: Colors.white)),
                                          ),
                                          const PopupMenuItem(
                                            value: 'statistics',
                                            child: Text('Visa statistik',
                                                style: TextStyle(
                                                    color: Colors.white30)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Content & Ratings
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overview & Streams info (2/3 width)
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Raw Tagline italicized right above Plot (Handling) without 'Tagline:' prefix text
                        if (tagline != null && tagline.trim().isNotEmpty) ...[
                          Text(
                            tagline,
                            style: const TextStyle(
                              color: Color(0xFFB593FF),
                              fontSize: 19,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          plot,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 17, height: 1.6),
                        ),
                        const SizedBox(height: 20),

                        // Streaming Watch Providers
                        if (providers.isNotEmpty) ...[
                          const Text('Finns att strömma på',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: providers.map((prov) {
                              final logoPath = prov['logo_path'];
                              final name = prov['provider_name'];
                              if (logoPath == null) return const SizedBox();
                              return Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white12),
                                  image: DecorationImage(
                                    image: NetworkImage(
                                        'https://image.tmdb.org/t/p/w500$logoPath'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Tooltip(message: name ?? ''),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Playback settings dropdowns ──────────────
                        if (!isShow) _buildPlaybackSelectors(Map<String, dynamic>.from(metadata)),
                        const SizedBox(height: 16),

                        // Keywords section placed within left column
                        if (keywords.isNotEmpty) ...[
                          _KeywordsExpandableContainer(
                            keywords: keywords,
                            onKeywordSelected: (label) {
                              if (widget.onKeywordSelected != null) {
                                widget.onKeywordSelected!(label);
                              } else if (widget.onGenreSelected != null) {
                                widget.onGenreSelected!(label);
                              } else {
                                Navigator.pop(context, label);
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                        ],

                      ],
                    ),
                  ),
                  const SizedBox(width: 60),

                  // Ratings Panel (1/3 width) - Shifted upwards and gap minimized
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Betyg',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 20),
                          _buildMyRatingControl(),
                          const SizedBox(height: 8),

                          // Order: IMDb, Simkl, Trakt, TMDB
                          _buildRatingRow(
                            'IMDb',
                            '${_formatRating(metadata['imdb_rating'])} / 10',
                            const Color(0xFFF5C518),
                            url: media['imdb_id'] != null
                                ? 'https://www.imdb.com/title/${media['imdb_id']}'
                                : 'https://www.imdb.com/find/?q=${Uri.encodeComponent(media['title']?.toString() ?? '')}',
                            votes: _formatVotes(metadata['imdb_votes']),
                          ),
                          _buildRatingRow(
                            'TMDB',
                            '${_formatRating(ratings['tmdb'])} / 10',
                            const Color(0xFF03B6E1),
                            url: media['tmdb_id'] != null
                                ? (media['type']?.toString().toLowerCase() == 'show' ||
                                        media['type']?.toString().toLowerCase() == 'tv'
                                    ? 'https://www.themoviedb.org/tv/${media['tmdb_id']}'
                                    : 'https://www.themoviedb.org/movie/${media['tmdb_id']}')
                                : 'https://www.themoviedb.org/search?query=${Uri.encodeComponent(media['title']?.toString() ?? '')}',
                            votes: _formatVotes(ratings['tmdb_votes']),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Seasons & Episodes for TV shows — shown ABOVE cast
            if (media['type'] == 'Show' && media['episodes'] is List && (media['episodes'] as List).isNotEmpty)
              _buildSeasonsSection(media['episodes'] as List<dynamic>),

            // Cast Carousel
            if (cast.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text('Skådespelare',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 230,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  scrollDirection: Axis.horizontal,
                  itemCount: cast.length,
                  itemBuilder: (context, index) {
                    final actor = cast[index];
                    final actorId = actor['id']?.toString();

                    return HoverableBuilder(
                      builder: (context, isHovered) {
                        return GestureDetector(
                          onTap: () {
                              if (actorId != null) {
                                if (widget.onPersonSelected != null) {
                                  widget.onPersonSelected!(actorId);
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PersonDetailsScreen(
                                        personId: actorId,
                                        apiService: widget.apiService,
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Container(
                              width: 140,
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 160,
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color:
                                              Colors.white.withValues(alpha: isHovered ? 0.3 : 0.04)),
                                      image: actor['profile_path'] != null
                                          ? DecorationImage(
                                              image: NetworkImage(
                                                  actor['profile_path']),
                                              fit: BoxFit.cover)
                                          : null,
                                    ),
                                    foregroundDecoration: isHovered
                                        ? BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          )
                                        : null,
                                child: actor['profile_path'] == null
                                    ? const Center(
                                        child: Icon(Icons.person,
                                            size: 50, color: Colors.white24))
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              Text(actor['name'] ?? 'Unknown',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(actor['character'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      );
                    }
                  );
                  },
                ),
              ),
              const SizedBox(height: 30),
            ],

            // --- SOUNDTRACK SEKTION ---
            Builder(
              builder: (context) {
                final soundtrack = metadata['soundtrack'] as Map<String, dynamic>?;
                if (soundtrack == null) {
                  return const SizedBox.shrink();
                }

                final albumTitle = soundtrack['album']?.toString() ?? 'Okänt Album';
                final artist = soundtrack['artist']?.toString() ?? 'Okänd Artist';
                final coverPath = soundtrack['cover_path']?.toString();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          const Text(
                            'Soundtrack',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SoundtrackScreen(
                                  soundtrackData: soundtrack,
                                  movieTitle: title,
                                  movieId: widget.mediaId,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 180,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.black.withValues(alpha: 0.3),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      child: AspectRatio(
                                        aspectRatio: 1,
                                        child: coverPath != null
                                            ? Image.network(
                                                coverPath,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: const Color(0xFF2A2438),
                                                child: const Icon(Icons.album, size: 50, color: Colors.white24),
                                              ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                          hoverColor: Colors.black.withValues(alpha: 0.4),
                                          onTap: () {
                                            debugPrint('Öppnar soundtrack vy för $albumTitle');
                                          },
                                          child: Align(
                                            alignment: Alignment.center,
                                            child: IconButton(
                                              icon: const CircleAvatar(
                                                radius: 24,
                                                backgroundColor: Color(0xFF8A5BFF),
                                                child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
                                              ),
                                              onPressed: () {
                                                debugPrint('Spelar soundtrack: $albumTitle');
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        albumTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'FLAC • Lossless',
                                        style: TextStyle(
                                          color: Color(0xFF00E676),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                );
              },
            ),

            // Collection Chronology horizontal scroll under Cast
            if (collectionId != null && collectionId.toString().isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text('$collectionName',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, dynamic>>(
                future: _collectionItemsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                      child: Text('Laddar samling...',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 14)),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return const SizedBox.shrink();
                  }
                  final collectionData = snapshot.data!;
                  final parts = collectionData['items'] as List<dynamic>? ?? [];
                  if (parts.isEmpty) return const SizedBox.shrink();

                  return SizedBox(
                    height: 260,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      scrollDirection: Axis.horizontal,
                      itemCount: parts.length,
                      itemBuilder: (context, index) {
                        final item = parts[index] as Map<String, dynamic>;
                        final localId = item['id']?.toString() ?? '';
                        final tmdbId = item['tmdb_id']?.toString();
                        final inLibrary = localId.isNotEmpty;
                        
                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: SizedBox(
                            width: 140,
                            child: UnifiedPosterCard(
                              item: item,
                              isHomeCard: false,
                              index: index,
                              inLibrary: inLibrary,
                              posterPrefix: 'col_chronology',
                              titleDisplayStyle: _titleDisplayStyle,
                              posterScale: 1.0,

                              selectedItems: const {},
                              selectionMode: false,
                              onPlayTap: inLibrary ? (i) => widget.onMediaSelected?.call(localId) : null,
                              onContextMenu: (i, isHome, pos) => _mediaActionsHelper.openPosterActionsMenu(i, isHomeCard: isHome, globalPos: pos),
                                onEdit: inLibrary ? _mediaActionsHelper.openMediaEditor : null,
                              onPosterTap: (i, isHome) {
                                if (inLibrary) {
                                  widget.onMediaSelected?.call(localId);
                                } else if (tmdbId != null) {
                                  widget.onMediaSelected?.call('external_movie_$tmdbId');
                                }
                              },
                            ),
                          ),
                        );
                      }
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],

            // Similar media should appear below cast and remain library-only via backend filter
            _buildSimilarCarousel(),
          ],
        ),
      ),
    );
  }

}

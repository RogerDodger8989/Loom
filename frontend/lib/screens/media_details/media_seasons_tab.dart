part of '../media_details_screen.dart';

extension MediaSeasonsTabExtension on _MediaDetailsScreenState {
Widget _buildSeasonsSection(List<dynamic> episodes) {
    // Build local seasons map
    final Map<int, List<Map<String, dynamic>>> localSeasons = {};
    for (final ep in episodes) {
      final episode = Map<String, dynamic>.from(ep as Map);
      final season = int.tryParse(episode['season_number']?.toString() ?? '0') ?? 0;
      localSeasons.putIfAbsent(season, () => []).add(episode);
    }
    if (localSeasons.isEmpty) return const SizedBox.shrink();

    // Parse TMDB seasons metadata
    final metadata = _mediaData?['metadata'];
    List<Map<String, dynamic>> tmdbSeasons = [];
    if (metadata is Map) {
      final seasonsRaw = metadata['seasons_json'];
      if (seasonsRaw is List) {
        for (final e in seasonsRaw) {
          if (e is Map) tmdbSeasons.add(Map<String, dynamic>.from(e));
        }
      } else if (seasonsRaw is String && seasonsRaw.isNotEmpty) {
        for (final e in _parseJsonList(seasonsRaw)) {
          if (e is Map) tmdbSeasons.add(Map<String, dynamic>.from(e));
        }
      }
    }

    // Build merged season list: TMDB seasons (sorted) + any local-only seasons not in TMDB
    final Set<int> tmdbSeasonNums = tmdbSeasons.map((s) => (s['season_number'] as num?)?.toInt() ?? 0).toSet();
    final List<int> localOnly = localSeasons.keys.where((n) => !tmdbSeasonNums.contains(n)).toList()..sort();

    // Compose display list: TMDB seasons first (in order), then local-only ones
    final List<Map<String, dynamic>> displaySeasons = [
      ...tmdbSeasons.where((s) {
        final n = (s['season_number'] as num?)?.toInt() ?? 0;
        return n >= 0; // include specials (0)
      }),
      ...localOnly.map<Map<String, dynamic>>((n) => <String, dynamic>{
        'season_number': n,
        'name': n == 0 ? 'Specials' : 'Säsong $n',
        'episode_count': localSeasons[n]!.length,
        'poster_path': null,
      }),
    ];

    if (displaySeasons.isEmpty) {
      for (final n in localSeasons.keys.toList()..sort()) {
        displaySeasons.add(<String, dynamic>{
          'season_number': n,
          'name': n == 0 ? 'Specials' : 'Säsong $n',
          'episode_count': localSeasons[n]!.length,
          'poster_path': null,
        });
      }
    }

    // Auto-select season for episode view
    if (_selectedSeasonNumber == -1) {
      final lastEpId = metadata is Map ? metadata['last_watched_episode_id']?.toString() : null;
      int autoSeason = (displaySeasons.firstWhere(
        (s) => localSeasons.containsKey((s['season_number'] as num?)?.toInt() ?? -1),
        orElse: () => displaySeasons.first,
      )['season_number'] as num?)?.toInt() ?? 1;
      if (lastEpId != null) {
        for (final ep in episodes) {
          if (ep['id']?.toString() == lastEpId) {
            autoSeason = int.tryParse(ep['season_number']?.toString() ?? '') ?? autoSeason;
            break;
          }
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedSeasonNumber == -1) {
          setState(() => _selectedSeasonNumber = autoSeason);
        }
      });
    }

    if (_seasonOverviewMode) {
      return _buildSeasonOverview(displaySeasons, localSeasons);
    } else {
      return _buildSeasonEpisodeView(localSeasons, displaySeasons);
    }
  }

// ── Season overview ──────────────────────────────────────────────────────

  Widget _buildSeasonOverview(
    List<Map<String, dynamic>> displaySeasons,
    Map<int, List<Map<String, dynamic>>> localSeasons,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Säsonger', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: displaySeasons.length,
            itemBuilder: (context, index) {
              final s = displaySeasons[index];
              final sNum = (s['season_number'] as num?)?.toInt() ?? 0;
              final hasLocal = localSeasons.containsKey(sNum);
              final sEps = localSeasons[sNum] ?? [];
              final watched = sEps.where((e) => e['is_watched'] == 1 || e['is_watched'] == true).length;
              final total = sEps.length;
              final tmdbTotal = (s['episode_count'] as num?)?.toInt() ?? total;
              final allWatched = total > 0 && watched == total;
              final posterRaw = s['poster_path']?.toString();
              final poster = posterRaw != null && posterRaw.isNotEmpty
                  ? (posterRaw.startsWith('http') ? posterRaw : 'https://image.tmdb.org/t/p/w300$posterRaw')
                  : null;
              final sName = s['name']?.toString() ?? (sNum == 0 ? 'Specials' : 'Säsong $sNum');
              final airDate = s['air_date']?.toString() ?? '';
              final year = airDate.length >= 4 ? airDate.substring(0, 4) : '';

              // Find next to watch in this season
              Map<String, dynamic>? nextEp;
              if (hasLocal) {
                for (final ep in sEps) {
                  if (ep['is_watched'] != 1 && ep['is_watched'] != true) {
                    nextEp = ep;
                    break;
                  }
                }
              }

              return MouseRegion(
                cursor: hasLocal ? SystemMouseCursors.click : SystemMouseCursors.basic,
                child: GestureDetector(
                onTap: hasLocal
                    ? () => setState(() {
                          _selectedSeasonNumber = sNum;
                          _seasonOverviewMode = false;
                        })
                    : null,
                onSecondaryTapUp: hasLocal
                    ? (d) => _showSeasonContextMenu(context, d.globalPosition, sNum, sEps)
                    : null,
                child: AnimatedOpacity(
                  opacity: hasLocal ? 1.0 : 0.38,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Poster
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (poster != null && poster.isNotEmpty)
                                  Image.network(poster, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          child: const Icon(Icons.tv, color: Colors.white24, size: 32)))
                                else
                                  Container(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    child: const Icon(Icons.tv, color: Colors.white24, size: 32),
                                  ),
                                // Not-local overlay
                                if (!hasLocal)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: const Center(
                                      child: Icon(Icons.lock_outline, color: Colors.white38, size: 28),
                                    ),
                                  ),
                                // Watched overlay
                                if (allWatched)
                                  Container(color: Colors.black.withValues(alpha: 0.35)),
                                // "Next" banner
                                if (nextEp != null && !allWatched)
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF8A5BFF),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'E${(nextEp['episode_number'] as num?)?.toInt() ?? 1}',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                // Watched check
                                if (allWatched)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                                      child: const Icon(Icons.check, color: Colors.white, size: 10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Info
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(sName,
                                        style: TextStyle(
                                            color: hasLocal ? Colors.white : Colors.white54,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hasLocal ? '$total av $tmdbTotal avsnitt' : '$tmdbTotal avsnitt${year.isNotEmpty ? ' · $year' : ''}',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 10),
                              ),
                              if (hasLocal && total > 0) ...[
                                const SizedBox(height: 5),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: watched / total,
                                    minHeight: 3,
                                    color: allWatched ? const Color(0xFF4CAF50) : const Color(0xFF8A5BFF),
                                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                              ],
                              if (!hasLocal)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Ej tillgänglig',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.30), fontSize: 10)),
                                ),
                              // "..." button row
                              if (hasLocal)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    InkWell(
                                      mouseCursor: SystemMouseCursors.click,
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        final RenderBox box = context.findRenderObject() as RenderBox;
                                        final pos = box.localToGlobal(Offset.zero);
                                        _showSeasonContextMenu(context, Offset(pos.dx + box.size.width / 2, pos.dy + box.size.height / 2), sNum, sEps);
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        child: Icon(Icons.more_horiz, color: Colors.white38, size: 16),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),  // GestureDetector (child of MouseRegion)
              );  // MouseRegion
            },
          ),
        ],
      ),
    );
  }

// ── Episode view (after selecting a season) ──────────────────────────────

  Widget _buildSeasonEpisodeView(
    Map<int, List<Map<String, dynamic>>> localSeasons,
    List<Map<String, dynamic>> displaySeasons,
  ) {
    final sortedLocal = localSeasons.keys.toList()..sort();
    final activeSeason = _selectedSeasonNumber == -1 ? sortedLocal.first : _selectedSeasonNumber;
    final localActiveEps = List<Map<String, dynamic>>.from(localSeasons[activeSeason] ?? localSeasons[sortedLocal.first]!);

    // Build combined list with upcoming placeholder episodes if enabled
    List<Map<String, dynamic>> activeEps = localActiveEps;
    if (_showUpcomingEpisodes) {
      final tmdbSeason = displaySeasons.firstWhere(
        (s) => (s['season_number'] as num?)?.toInt() == activeSeason,
        orElse: () => {},
      );
      final tmdbCount = (tmdbSeason['episode_count'] as num?)?.toInt() ?? 0;
      if (tmdbCount > localActiveEps.length) {
        final localEpNums = localActiveEps.map((e) => int.tryParse(e['episode_number']?.toString() ?? '0') ?? 0).toSet();
        final placeholders = <Map<String, dynamic>>[];
        for (int n = 1; n <= tmdbCount; n++) {
          if (!localEpNums.contains(n)) {
            placeholders.add({
              'episode_number': n,
              'season_number': activeSeason,
              'title': 'Avsnitt $n',
              'file_path': null,
              'id': null,
              '_is_upcoming': true,
            });
          }
        }
        activeEps = [...localActiveEps, ...placeholders]
          ..sort((a, b) => (int.tryParse(a['episode_number']?.toString() ?? '0') ?? 0)
              .compareTo(int.tryParse(b['episode_number']?.toString() ?? '0') ?? 0));
      }
    }

    // Find next unwatched episode (from local only)
    Map<String, dynamic>? nextEp;
    for (final ep in localActiveEps) {
      if (ep['is_watched'] != 1 && ep['is_watched'] != true) { nextEp = ep; break; }
    }

    final watchedCount = localActiveEps.where((e) => e['is_watched'] == 1 || e['is_watched'] == true).length;
    final totalCount = localActiveEps.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ───────────────────────────────────────────────────
          Row(
            children: [
              // Back to season overview
              InkWell(
                onTap: () => setState(() => _seasonOverviewMode = true),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF8A5BFF), size: 14),
                      const SizedBox(width: 4),
                      Text('Säsonger', style: TextStyle(color: const Color(0xFF8A5BFF), fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  activeSeason == 0 ? 'Specials' : 'Säsong $activeSeason',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Grid / List toggle
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildViewToggleBtn(Icons.view_list_rounded, !_episodeViewIsGrid, () { setState(() => _episodeViewIsGrid = false); _saveEpisodeViewPref(false); }, tooltip: 'Lista'),
                    _buildViewToggleBtn(Icons.grid_view_rounded, _episodeViewIsGrid, () { setState(() => _episodeViewIsGrid = true); _saveEpisodeViewPref(true); }, tooltip: 'Rutnät'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Season chips (quick jump) ────────────────────────────────────
          if (sortedLocal.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: sortedLocal.map((sNum) {
                    final isActive = sNum == activeSeason;
                    final sLabel = sNum == 0 ? 'Specials' : 'S$sNum';
                    final sEps = localSeasons[sNum]!;
                    final sWatched = sEps.where((e) => e['is_watched'] == 1 || e['is_watched'] == true).length;
                    final allWatched = sWatched == sEps.length && sEps.isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                        onTap: () => setState(() => _selectedSeasonNumber = sNum),
                        onSecondaryTapUp: (d) => _showSeasonContextMenu(context, d.globalPosition, sNum, sEps),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isActive ? const Color(0xFF8A5BFF).withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isActive ? const Color(0xFF8A5BFF) : Colors.white.withValues(alpha: 0.12),
                              width: isActive ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (allWatched) ...[
                                const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 12),
                                const SizedBox(width: 4),
                              ],
                              Text(sLabel,
                                  style: TextStyle(
                                      color: isActive ? Colors.white : Colors.white60,
                                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12)),
                              const SizedBox(width: 4),
                              Text('$sWatched/${sEps.length}',
                                  style: TextStyle(
                                      color: isActive ? const Color(0xFFB593FF) : Colors.white30,
                                      fontSize: 10)),
                            ],
                          ),
                        ),
                      ),  // GestureDetector
                    ),    // MouseRegion
                  );
                }).toList(),
                ),
              ),
            ),

          // ── Season progress bar ──────────────────────────────────────────
          if (totalCount > 0) ...[
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: watchedCount / totalCount,
                      minHeight: 5,
                      color: const Color(0xFF8A5BFF),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$watchedCount av $totalCount sedda',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // ── Nästa att titta ──────────────────────────────────────────────
          if (nextEp != null) ...[
            _buildNextEpisodeBanner(nextEp, activeSeason),
            const SizedBox(height: 12),
          ],

          // ── Episode list / grid ──────────────────────────────────────────
          _episodeViewIsGrid
              ? _buildEpisodeGrid(activeEps, activeSeason)
              : _buildEpisodeList(activeEps, activeSeason),
        ],
      ),
    );
  }

Widget _buildNextEpisodeBanner(Map<String, dynamic> ep, int seasonNum) {
    final epNum = int.tryParse(ep['episode_number']?.toString() ?? '0') ?? 0;
    final epTitle = ep['title']?.toString() ?? 'Avsnitt $epNum';
    final epId = ep['id']?.toString();
    final label = 'S${seasonNum.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
    final progress = int.tryParse(ep['playback_progress']?.toString() ?? '0') ?? 0;

    return GestureDetector(
      onTap: epId != null
          ? () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(
                mediaId: epId,
                apiService: widget.apiService,
                startFromSeconds: progress > 60 ? progress : 0,
              )))
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF8A5BFF).withValues(alpha: 0.15), const Color(0xFF8A5BFF).withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF8A5BFF).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF8A5BFF), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nästa att titta', style: TextStyle(color: Color(0xFFB593FF), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Text('$label  ·  $epTitle', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (progress > 60) ...[
                    const SizedBox(height: 4),
                    Text('${(progress ~/ 60)} min in', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }

Widget _buildEpisodeList(List<Map<String, dynamic>> eps, int seasonNum) {
    return Column(
      children: eps.map((ep) {
        final epNum = int.tryParse(ep['episode_number']?.toString() ?? '0') ?? 0;
        final epTitle = ep['title']?.toString() ?? 'Avsnitt $epNum';
        final epId = ep['id']?.toString();
        final label = 'S${seasonNum.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
        final isWatched = ep['is_watched'] == 1 || ep['is_watched'] == true;
        final progress = int.tryParse(ep['playback_progress']?.toString() ?? '0') ?? 0;
        final duration = int.tryParse(ep['duration']?.toString() ?? '0') ?? 0;
        final hasProgress = progress > 60 && !isWatched;
        final airDate = ep['air_date']?.toString() ?? '';
        final overview = ep['overview']?.toString() ?? '';
        final isUpcoming = ep['_is_upcoming'] == true;
        final stillPathRaw = ep['still_path']?.toString();
        final stillPath = stillPathRaw != null && stillPathRaw.isNotEmpty
            ? (stillPathRaw.startsWith('http') ? stillPathRaw : 'https://image.tmdb.org/t/p/w300$stillPathRaw')
            : null;

        Widget leadingWidget;
        if (stillPath != null && stillPath.isNotEmpty) {
          leadingWidget = ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 96,
              height: 54,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    stillPath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white.withValues(alpha: 0.06),
                      child: const Icon(Icons.tv, color: Colors.white24, size: 20),
                    ),
                  ),
                  if (isWatched)
                    Container(color: Colors.black.withValues(alpha: 0.45)),
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              color: isWatched ? Colors.white38 : const Color(0xFF8A5BFF),
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          leadingWidget = Container(
            width: 56,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: isWatched ? Colors.white30 : const Color(0xFF8A5BFF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          );
        }

        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onSecondaryTapUp: (epId != null)
                ? (d) => _showEpisodeContextMenu(context, d.globalPosition, epId, label,
                    isWatched: isWatched, progress: progress)
                : null,
            child: InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: () {
                if (widget.onEpisodeSelected != null && _mediaData != null) {
                  widget.onEpisodeSelected!(ep, _mediaData!);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EpisodeDetailsScreen(
                        episode: ep,
                        showData: _mediaData ?? {},
                        apiService: widget.apiService,
                        onStatusChanged: () {
                          if (mounted) _fetchDetails();
                        },
                      ),
                    ),
                  );
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Opacity(
                opacity: isUpcoming ? 0.40 : 1.0,
                child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isWatched ? 0.01 : 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.fromLTRB(
                          12, stillPath != null && stillPath.isNotEmpty ? 8 : 6, 8,
                          stillPath != null && stillPath.isNotEmpty ? 8 : 6),
                      leading: leadingWidget,
                      title: Text(
                        epTitle,
                        style: TextStyle(color: isWatched ? Colors.white38 : Colors.white, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: airDate.isNotEmpty
                          ? Text(airDate,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.28), fontSize: 11))
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Watched toggle
                          Tooltip(
                            message: isWatched ? 'Markera som osedd' : 'Markera som sedd',
                            child: InkWell(
                              mouseCursor: SystemMouseCursors.click,
                              onTap: epId != null
                                  ? () async {
                                      try {
                                        await widget.apiService.toggleEpisodeSeenStatus(epId, !isWatched);
                                        if (mounted && _mediaData != null) {
                                          setState(() {
                                            final eps = _mediaData!['episodes'];
                                            if (eps is List) {
                                              for (final e in eps) {
                                                if (e is Map && e['id']?.toString() == epId) {
                                                  e['is_watched'] = !isWatched ? 1 : 0;
                                                  break;
                                                }
                                              }
                                            }
                                          });
                                        }
                                      } catch (_) {}
                                    }
                                  : null,
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  isWatched ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: isWatched ? const Color(0xFF4CAF50) : Colors.white24,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          // "..." button
                          if (epId != null)
                            GestureDetector(
                              onTapUp: (details) async {
                                await _showEpisodeContextMenu(context, details.globalPosition, epId, label, isWatched: isWatched, progress: progress);
                              },
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Icon(Icons.more_vert, color: Colors.white60, size: 20),
                                ),
                              ),
                            ),
                          // Play button
                          if (epId != null)
                            IconButton(
                              icon: Icon(
                                hasProgress ? Icons.play_circle_outline : Icons.play_arrow_rounded,
                                color: hasProgress ? const Color(0xFFB593FF) : const Color(0xFF8A5BFF),
                                size: 28,
                              ),
                              tooltip: hasProgress ? 'Fortsätt' : 'Spela',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => VideoPlayerScreen(
                                          mediaId: epId,
                                          apiService: widget.apiService,
                                          startFromSeconds: hasProgress ? progress : 0,
                                        )),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Progress bar for in-progress episodes
                    if (hasProgress && duration > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (progress / duration).clamp(0.0, 1.0),
                            minHeight: 3,
                            color: const Color(0xFF8A5BFF),
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ),  // Opacity
            ),
          ),
        );
      }).toList(),
    );
  }

Widget _buildEpisodeGrid(List<Map<String, dynamic>> eps, int seasonNum) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: eps.length,
      itemBuilder: (context, index) {
        final ep = eps[index];
        final epNum = int.tryParse(ep['episode_number']?.toString() ?? '0') ?? 0;
        final epTitle = ep['title']?.toString() ?? 'Avsnitt $epNum';
        final epId = ep['id']?.toString();
        final label = 'S${seasonNum.toString().padLeft(2, '0')}E${epNum.toString().padLeft(2, '0')}';
        final isWatched = ep['is_watched'] == 1 || ep['is_watched'] == true;
        final progress = int.tryParse(ep['playback_progress']?.toString() ?? '0') ?? 0;
        final duration = int.tryParse(ep['duration']?.toString() ?? '0') ?? 0;
        final hasProgress = progress > 60 && !isWatched;
        final stillRaw2 = ep['still_path']?.toString();
        final stillPath = stillRaw2 != null && stillRaw2.isNotEmpty
            ? (stillRaw2.startsWith('http') ? stillRaw2 : 'https://image.tmdb.org/t/p/w300$stillRaw2')
            : null;
        final overview = ep['overview']?.toString() ?? '';
        final airDate = ep['air_date']?.toString() ?? '';
        final isUpcoming = ep['_is_upcoming'] == true;

        return Opacity(
          opacity: isUpcoming ? 0.40 : 1.0,
          child: Stack(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    if (widget.onEpisodeSelected != null && _mediaData != null) {
                      widget.onEpisodeSelected!(ep, _mediaData!);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EpisodeDetailsScreen(
                            episode: ep,
                            showData: _mediaData ?? {},
                            apiService: widget.apiService,
                            onStatusChanged: () {
                              if (mounted) setState(() => _mediaData = null);
                              _fetchDetails();
                            },
                          ),
                        ),
                      );
                    }
                  },
                  onDoubleTap: epId != null
                      ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            mediaId: epId,
                            apiService: widget.apiService,
                            startFromSeconds: hasProgress ? progress : 0,
                          )))
                      : null,
                  onSecondaryTapUp: epId != null
                      ? (d) => _showEpisodeContextMenu(context, d.globalPosition, epId, label, isWatched: isWatched, progress: progress)
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: isWatched ? 0.02 : 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (stillPath != null && stillPath.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              stillPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                        if (isWatched)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 22, 8, 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black.withValues(alpha: 0.88), Colors.transparent],
                              ),
                              borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasProgress && duration > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: (progress / duration).clamp(0.0, 1.0),
                                        minHeight: 3,
                                        color: const Color(0xFF8A5BFF),
                                        backgroundColor: Colors.white12,
                                      ),
                                    ),
                                  ),
                                Text(label,
                                    style: const TextStyle(
                                        color: Color(0xFFB593FF), fontSize: 10, fontWeight: FontWeight.bold)),
                                Text(epTitle,
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                        if (isWatched)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                              child: const Icon(Icons.check, color: Colors.white, size: 10),
                            ),
                          ),
                        Center(
                          child: Icon(
                            isWatched ? Icons.replay_rounded : Icons.play_circle_outline_rounded,
                            color: Colors.white.withValues(alpha: stillPath != null && stillPath.isNotEmpty ? 0.0 : 0.30),
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // "..." button outside the card GestureDetector — no gesture conflict
              if (epId != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTapUp: (details) async {
                        await _showEpisodeContextMenu(context, details.globalPosition, epId, label, isWatched: isWatched, progress: progress);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.more_vert, color: Colors.white70, size: 16),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

Widget _buildViewToggleBtn(IconData icon, bool active, VoidCallback onTap, {String tooltip = ''}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF8A5BFF).withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, color: active ? const Color(0xFF8A5BFF) : Colors.white38, size: 18),
        ),
      ),
    );
  }

}

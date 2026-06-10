part of '../settings_screen.dart';

extension StatistikTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Statistik (steg 9)
  // ─────────────────────────────────────────────
  void _startStatsPolling() {
    _statsPollTimer?.cancel();
    _fetchStats();
    _statsPollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchStats());
  }

  void _stopStatsPolling() {
    _statsPollTimer?.cancel();
    _statsPollTimer = null;
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetchStats() async {
    try {
      final results = await Future.wait<dynamic>([
        widget.apiService.fetchStatsRealtime(),
        widget.apiService.fetchStatsHistory(
          userId: _statsSelectedUserId,
          days: (_statsDateFrom == null && _statsDaysFilter > 0) ? _statsDaysFilter : null,
          startDate: _statsDateFrom != null ? _formatDate(_statsDateFrom!) : null,
          endDate: _statsDateTo != null ? _formatDate(_statsDateTo!) : null,
          limit: 50,
        ),
        widget.apiService.fetchStatsUsers(),
        widget.apiService.fetchStatsTops(),
      ]);
      if (!mounted) return;
      setState(() {
        _statsError    = null;
        _statsRealtime = results[0] as Map<String, dynamic>;
        _statsHistory  = results[1] as Map<String, dynamic>;
        _statsUsers    = results[2] as List<dynamic>;
        _statsTops     = results[3] as Map<String, dynamic>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statsError = e.toString());
    }
  }

  Future<void> _refreshHistory() async {
    setState(() => _statsHistoryLoading = true);
    try {
      final hist = await widget.apiService.fetchStatsHistory(
        userId: _statsSelectedUserId,
        days: (_statsDateFrom == null && _statsDaysFilter > 0) ? _statsDaysFilter : null,
        startDate: _statsDateFrom != null ? _formatDate(_statsDateFrom!) : null,
        endDate: _statsDateTo != null ? _formatDate(_statsDateTo!) : null,
        limit: 50,
      );
      if (mounted) setState(() { _statsHistory = hist; });
    } catch (_) {} finally {
      if (mounted) setState(() => _statsHistoryLoading = false);
    }
  }

  Future<void> _loadTopItemPlays(String mediaId) async {
    if (_topItemPlaysLoading[mediaId] == true) return;
    setState(() => _topItemPlaysLoading[mediaId] = true);
    try {
      final data = await widget.apiService.fetchMediaPlays(mediaId);
      if (mounted) {
        setState(() {
          _topItemPlays[mediaId] = data['plays'] as List<dynamic>? ?? [];
          _topItemPlaysLoading[mediaId] = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _topItemPlaysLoading[mediaId] = false);
    }
  }

  void _toggleTopItem(String mediaId) {
    final nowExpanded = !(_expandedTopItems[mediaId] == true);
    setState(() => _expandedTopItems[mediaId] = nowExpanded);
    if (nowExpanded && _topItemPlays[mediaId] == null) {
      _loadTopItemPlays(mediaId);
    }
  }

  Widget _buildStatistik() {
    if (_statsRealtime == null && _statsPollTimer == null) {
      Future.microtask(_startStatsPolling);
    }
    if (_statsUsers.isNotEmpty && _statsUsers.first is Map && !_statsUsers.first.containsKey('id')) {
      Future.microtask(_fetchStats);
    }

    if (_statsError != null && _statsRealtime == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text('Kunde inte hämta statistik',
                style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_statsError!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white30, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () { setState(() => _statsError = null); _startStatsPolling(); },
              icon: const Icon(Icons.refresh),
              label: const Text('Försök igen'),
            ),
          ],
        ),
      );
    }

    final rt   = _statsRealtime;
    final hist = _statsHistory;
    final tops = _statsTops;
    final allTime = hist?['allTimeTotals'] as Map<String, dynamic>?;

    return Column(
      children: [
        // ── Tab bar ──────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              for (final (i, label) in [
                (0, 'Överblick'), (1, 'Historik'), (2, 'Toppar'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _statsTabIndex = i);
                      widget.apiService.lastStatsTabIndex = i;
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _statsTabIndex == i
                            ? const Color(0xFF8A5BFF).withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _statsTabIndex == i
                              ? const Color(0xFF8A5BFF).withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Text(label,
                          style: TextStyle(
                            color: _statsTabIndex == i ? const Color(0xFFB593FF) : Colors.white38,
                            fontSize: 13,
                            fontWeight: _statsTabIndex == i ? FontWeight.bold : FontWeight.normal,
                          )),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Tab content ──────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _statsTabIndex == 0
                ? _buildStatsOverview(rt, hist, allTime)
                : _statsTabIndex == 1
                    ? _buildStatsHistory(hist)
                    : _buildStatsTops(tops),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsOverview(
    Map<String, dynamic>? rt,
    Map<String, dynamic>? hist,
    Map<String, dynamic>? allTime,
  ) {
    return Column(
      children: [
        // ── 4 stora siffror ─────────────────────
        if (allTime != null) ...[
          Row(children: [
            Expanded(child: _dashStat(Icons.schedule_outlined, 'Total seendetid',
                _formatMinutes(((allTime['totalSeconds'] as num?) ?? 0).toInt() ~/ 60),
                const Color(0xFF8A5BFF))),
            const SizedBox(width: 12),
            Expanded(child: _dashStat(Icons.movie_outlined, 'Unika titlar',
                '${(allTime['uniqueTitles'] as num?) ?? 0}',
                Colors.tealAccent)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _dashStat(Icons.people_outline, 'Aktiva användare',
                '${(allTime['activeUsers'] as num?) ?? 0}',
                Colors.orangeAccent)),
            const SizedBox(width: 12),
            Expanded(child: _dashStat(Icons.history_outlined, 'Sedda (filtrerat)',
                '${hist?['totalWatched'] ?? 0}',
                Colors.greenAccent)),
          ]),
          const SizedBox(height: 20),
        ],
        // ── CPU/RAM ─────────────────────────────
        _buildSection('Serverresurser', Icons.speed_outlined, [
          if (rt == null)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))),
            ))
          else ...[
            _statGaugeRow(
              label: 'CPU',
              value: rt['cpuPercent'] as int,
              subtitle: '${rt['cpuCores']} kärnor  •  ${rt['cpuModel'] ?? ''}',
              color: _gaugeColor(rt['cpuPercent'] as int),
            ),
            const SizedBox(height: 14),
            _statGaugeRow(
              label: 'RAM',
              value: rt['memPercent'] as int,
              subtitle: '${_formatBytes(rt['usedMemBytes'] as int)} / ${_formatBytes(rt['totalMemBytes'] as int)}',
              color: _gaugeColor(rt['memPercent'] as int),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _miniStat(Icons.timer_outlined, 'Upptime', _formatUptime(rt['uptimeSeconds'] as int))),
              const SizedBox(width: 12),
              Expanded(child: _miniStat(Icons.storage_outlined, 'Databas', _formatBytes(rt['dbSizeBytes'] as int))),
            ]),
          ],
        ]),
        const SizedBox(height: 16),
        // ── Per-användare ─────────────────────
        _buildSection('Per användare', Icons.people_outline, [
          if (_statsUsers.isEmpty)
            const Center(child: Text('Ingen data', style: TextStyle(color: Colors.white24)))
          else
            ..._statsUsers.map((u) => _userStatRow(u as Map<String, dynamic>)),
        ]),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStatsHistory(Map<String, dynamic>? hist) {
    final recent = (hist?['recent'] as List<dynamic>?) ?? [];
    final hasDateFilter = _statsDateFrom != null || _statsDateTo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Filter rad 1: användare + snabbval ─
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _statsSelectedUserId,
                    dropdownColor: const Color(0xFF15102A),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    hint: const Text('Alla användare', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Alla användare')),
                      ..._statsUsers.map((u) {
                        final um = u as Map<String, dynamic>;
                        return DropdownMenuItem<String?>(
                          value: um['id'].toString(),
                          child: Text(um['username'] as String? ?? '?'),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      setState(() => _statsSelectedUserId = v);
                      _refreshHistory();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: hasDateFilter
                    ? Colors.black.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasDateFilter
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: hasDateFilter ? 0 : _statsDaysFilter,
                  dropdownColor: const Color(0xFF15102A),
                  style: TextStyle(
                    color: hasDateFilter ? Colors.white24 : Colors.white,
                    fontSize: 13,
                  ),
                  items: const [
                    DropdownMenuItem(value: 0,  child: Text('Alla tider')),
                    DropdownMenuItem(value: 7,  child: Text('7 dagar')),
                    DropdownMenuItem(value: 30, child: Text('30 dagar')),
                    DropdownMenuItem(value: 90, child: Text('90 dagar')),
                  ],
                  onChanged: hasDateFilter ? null : (v) {
                    setState(() => _statsDaysFilter = v ?? 0);
                    _refreshHistory();
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_statsHistoryLoading)
              const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))),
          ],
        ),
        const SizedBox(height: 8),
        // ── Filter rad 2: datumintervall ────────
        Row(
          children: [
            _datePicker(
              label: 'Från',
              value: _statsDateFrom,
              lastDate: _statsDateTo ?? DateTime.now(),
              onPicked: (d) {
                setState(() {
                  _statsDateFrom = d;
                  _statsDaysFilter = 0;
                });
                _refreshHistory();
              },
              onClear: () {
                setState(() => _statsDateFrom = null);
                _refreshHistory();
              },
            ),
            const SizedBox(width: 8),
            _datePicker(
              label: 'Till',
              value: _statsDateTo,
              firstDate: _statsDateFrom ?? DateTime(2020),
              onPicked: (d) {
                setState(() {
                  _statsDateTo = d;
                  _statsDaysFilter = 0;
                });
                _refreshHistory();
              },
              onClear: () {
                setState(() => _statsDateTo = null);
                _refreshHistory();
              },
            ),
            if (hasDateFilter) ...[
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    setState(() { _statsDateFrom = null; _statsDateTo = null; });
                    _refreshHistory();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
                    ),
                    child: const Text('Rensa datum',
                        style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (recent.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('Ingen spelningshistorik',
                  style: TextStyle(color: Colors.white24, fontSize: 14)),
            ),
          )
        else
          ...recent.map((e) => _historyItem(e as Map<String, dynamic>)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _datePicker({
    required String label,
    required DateTime? value,
    DateTime? firstDate,
    DateTime? lastDate,
    required void Function(DateTime) onPicked,
    required VoidCallback onClear,
  }) {
    final active = value != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: firstDate ?? DateTime(2020),
            lastDate: lastDate ?? DateTime.now(),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFF8A5BFF),
                  onPrimary: Colors.white,
                  surface: Color(0xFF1A1230),
                  onSurface: Colors.white,
                ),
                dialogBackgroundColor: const Color(0xFF1A1230),
              ),
              child: child!,
            ),
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF8A5BFF).withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? const Color(0xFF8A5BFF).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today_outlined, size: 13,
                color: active ? const Color(0xFFB593FF) : Colors.white38),
            const SizedBox(width: 5),
            Text(
              active ? _formatDate(value!) : label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 12,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 5),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 12, color: Colors.white38),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildStatsTops(Map<String, dynamic>? tops) {
    if (tops == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))),
        ),
      );
    }
    final topMovies = (tops['topMovies'] as List<dynamic>?) ?? [];
    final topShows  = (tops['topShows']  as List<dynamic>?) ?? [];
    final topUsers  = (tops['topUsers']  as List<dynamic>?) ?? [];

    return Column(
      children: [
        _buildSection('Mest sedda filmer', Icons.movie_outlined, [
          if (topMovies.isEmpty)
            const Text('Ingen data', style: TextStyle(color: Colors.white24))
          else
            ...topMovies.asMap().entries.map((e) => _topMediaRow(e.key + 1, e.value as Map<String, dynamic>, 'Movie')),
        ]),
        const SizedBox(height: 16),
        _buildSection('Mest sedda TV-serier', Icons.tv_outlined, [
          if (topShows.isEmpty)
            const Text('Ingen data', style: TextStyle(color: Colors.white24))
          else
            ...topShows.asMap().entries.map((e) => _topMediaRow(e.key + 1, e.value as Map<String, dynamic>, 'Show')),
        ]),
        const SizedBox(height: 16),
        _buildSection('Mest aktiva användare (30 dagar)', Icons.emoji_events_outlined, [
          if (topUsers.isEmpty)
            const Text('Ingen data', style: TextStyle(color: Colors.white24))
          else
            ...topUsers.asMap().entries.map((e) => _topUserRow(e.key + 1, e.value as Map<String, dynamic>)),
        ]),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _dashStat(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ])),
      ]),
    );
  }

  Widget _historyItem(Map<String, dynamic> e) {
    final year       = (e['year'] as num?)?.toInt();
    final rawTitle   = (e['title'] as String?) ?? 'Okänd';
    final title      = year != null ? '$rawTitle ($year)' : rawTitle;
    final type       = (e['type']  as String?) ?? '';
    final user       = (e['username'] as String?) ?? '—';
    final posterPath = (e['poster_path'] as String?) ?? '';
    final mediaId    = e['media_item_id']?.toString();
    final sn  = e['season_number'];
    final ep  = e['episode_number'];
    final sub = sn != null ? 'S${sn.toString().padLeft(2,'0')}E${ep.toString().padLeft(2,'0')}' : type;
    final durSec = (e['total_duration_seconds'] as num?)?.toInt() ?? 0;
    final updAt = (e['updated_at'] as String?) ?? '';
    final dateStr = updAt.length >= 10 ? updAt.substring(0, 10) : updAt;
    final canNav = mediaId != null && widget.onNavigateToMedia != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        // Cover — klickbar
        MouseRegion(
          cursor: canNav ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            onTap: canNav ? () => widget.onNavigateToMedia!(mediaId!, _statsTabIndex) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: posterPath.isNotEmpty
                  ? Image.network(posterPath, width: 36, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _posterPlaceholder())
                  : _posterPlaceholder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
            if (sub.isNotEmpty)
              Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            Row(children: [
              Icon(Icons.person_outline, size: 11, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(width: 4),
              Text(user, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(dateStr, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          if (durSec > 0)
            Text(_formatMinutes(durSec ~/ 60),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      width: 36, height: 52,
      color: Colors.white.withValues(alpha: 0.04),
      child: const Icon(Icons.movie_outlined, color: Colors.white12, size: 18),
    );
  }

  Widget _topMediaRow(int rank, Map<String, dynamic> m, String mediaType) {
    final year       = (m['year'] as num?)?.toInt();
    final rawTitle   = (m['title']       as String?) ?? 'Okänd';
    final title      = year != null ? '$rawTitle ($year)' : rawTitle;
    final posterPath = (m['poster_path'] as String?) ?? '';
    final mediaId    = m['id']?.toString() ?? '';
    final count      = (m['playCount']   as num?)?.toInt() ?? 0;
    final secs       = (m['totalSeconds'] as num?)?.toInt() ?? 0;
    final rankColor  = rank == 1 ? Colors.amber : rank == 2 ? Colors.white54 : rank == 3 ? const Color(0xFFCD7F32) : Colors.white24;
    final canNav     = mediaId.isNotEmpty && widget.onNavigateToMedia != null;
    final isExpanded = _expandedTopItems[mediaId] == true;
    final plays      = _topItemPlays[mediaId];
    final playsLoading = _topItemPlaysLoading[mediaId] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: isExpanded ? 0 : 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(8))
                : BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: Row(children: [
            SizedBox(width: 24,
                child: Text('#$rank', style: TextStyle(color: rankColor, fontSize: 13, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            // poster + tittel — klickbar för navigering
            MouseRegion(
              cursor: canNav ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                onTap: canNav ? () => widget.onNavigateToMedia!(mediaId, _statsTabIndex) : null,
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: posterPath.isNotEmpty
                        ? Image.network(posterPath, width: 30, height: 44, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _posterPlaceholder())
                        : Container(width: 30, height: 44, color: Colors.white.withValues(alpha: 0.04),
                              child: const Icon(Icons.movie_outlined, color: Colors.white12, size: 14)),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MouseRegion(
                cursor: canNav ? SystemMouseCursors.click : MouseCursor.defer,
                child: GestureDetector(
                  onTap: canNav ? () => widget.onNavigateToMedia!(mediaId, _statsTabIndex) : null,
                  child: Text(title,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            // spelningsräknare — klickbar för att expandera
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _toggleTopItem(mediaId),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$count spelningar',
                          style: TextStyle(
                            color: isExpanded ? const Color(0xFFB593FF) : Colors.white70,
                            fontSize: 12, fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: isExpanded
                                ? const Color(0xFFB593FF)
                                : Colors.white54,
                          )),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(Icons.keyboard_arrow_down,
                            size: 15,
                            color: isExpanded ? const Color(0xFFB593FF) : Colors.white38),
                      ),
                    ]),
                    if (secs > 0)
                      Text(_formatMinutes(secs ~/ 60),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
        // ── expanderat spelpanel ──────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: isExpanded
              ? _buildPlaysExpandedSection(mediaId, mediaType, plays, playsLoading)
              : const SizedBox.shrink(),
        ),
        if (!isExpanded) const SizedBox.shrink()
        else const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildPlaysExpandedSection(
    String mediaId,
    String mediaType,
    List<dynamic>? plays,
    bool loading,
  ) {
    Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))),
        ),
      );
    } else if (plays == null || plays.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text('Ingen spelningshistorik', style: TextStyle(color: Colors.white24, fontSize: 12)),
      );
    } else {
      final isMovie = mediaType == 'Movie';
      body = Column(
        children: plays.map((raw) {
          final p = raw as Map<String, dynamic>;
          final username    = (p['username']  as String?) ?? '—';
          final initials    = username.isNotEmpty ? username[0].toUpperCase() : '?';

          if (isMovie) {
            final isWatched  = (p['is_watched'] as num?)?.toInt() == 1;
            final durSec     = (p['total_duration_seconds'] as num?)?.toInt() ?? 0;
            final posSec     = (p['last_position_seconds']  as num?)?.toInt() ?? 0;
            final pct        = durSec > 0 ? (posSec / durSec * 100).round() : 0;
            final updAt      = (p['updated_at']         as String?) ?? '';
            final startAt    = (p['started_at_approx']  as String?) ?? '';
            final endLabel   = updAt.length  >= 16 ? updAt.substring(0, 16)   : updAt;
            final startLabel = startAt.length >= 16 ? startAt.substring(0, 16) : startAt;

            return _playEntryRow(
              initials: initials,
              username: username,
              line1: startLabel.isNotEmpty ? 'Start: $startLabel' : null,
              line2: 'Slut: $endLabel',
              trailing: isWatched
                  ? Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.check_circle, size: 13, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text('Slutförd', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                    ])
                  : Text('$pct% sedd',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
            );
          } else {
            final epCount   = (p['episode_count']      as num?)?.toInt() ?? 0;
            final compCount = (p['completed_count']    as num?)?.toInt() ?? 0;
            final totSec    = (p['totalSeconds']       as num?)?.toInt() ?? 0;
            final lastAt    = (p['updated_at']         as String?) ?? '';
            final firstAt   = (p['first_watched_approx'] as String?) ?? '';
            final lastLabel  = lastAt.length  >= 10 ? lastAt.substring(0, 10)  : lastAt;
            final firstLabel = firstAt.length >= 10 ? firstAt.substring(0, 10) : firstAt;

            return _playEntryRow(
              initials: initials,
              username: username,
              line1: firstLabel.isNotEmpty ? 'Första: $firstLabel' : null,
              line2: 'Senast: $lastLabel  •  $epCount avsnitt ($compCount klara)',
              trailing: Text(_formatMinutes(totSec ~/ 60),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            );
          }
        }).toList(),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF8A5BFF).withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.12)),
      ),
      child: body,
    );
  }

  Widget _playEntryRow({
    required String initials,
    required String username,
    String? line1,
    required String line2,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
          child: Text(initials,
              style: const TextStyle(color: Color(0xFFB593FF), fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(username, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
            if (line1 != null)
              Text(line1, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
            Text(line2, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
          ]),
        ),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }

  Widget _topUserRow(int rank, Map<String, dynamic> u) {
    final username  = (u['username'] as String?) ?? '—';
    final userId    = u['id']?.toString() ?? '';
    final role      = (u['role']     as String?) ?? 'User';
    final secs      = (u['totalSeconds'] as num?)?.toInt() ?? 0;
    final watched   = (u['watched']  as num?)?.toInt() ?? 0;
    final rankColor = rank == 1 ? Colors.amber : rank == 2 ? Colors.white54 : rank == 3 ? const Color(0xFFCD7F32) : Colors.white24;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _statsTabIndex = 1;
            _statsSelectedUserId = userId.isNotEmpty ? userId : null;
          });
          widget.apiService.lastStatsTabIndex = 1;
          _refreshHistory();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: Row(children: [
            SizedBox(width: 24,
                child: Text('#$rank', style: TextStyle(color: rankColor, fontSize: 13, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: role == 'Admin'
                  ? Colors.amber.withValues(alpha: 0.12)
                  : const Color(0xFF8A5BFF).withValues(alpha: 0.12),
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                  color: role == 'Admin' ? Colors.amber : const Color(0xFFB593FF),
                  fontSize: 12, fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(username,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                const Text('Tryck för att visa historik',
                    style: TextStyle(color: Colors.white24, fontSize: 10)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$watched sedda',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              Text(_formatMinutes(secs ~/ 60),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            ]),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios, size: 11, color: Colors.white24),
          ]),
        ),
      ),
    );
  }

  Color _gaugeColor(int percent) {
    if (percent >= 85) return Colors.redAccent;
    if (percent >= 65) return Colors.orangeAccent;
    return const Color(0xFF8A5BFF);
  }

  Widget _statGaugeRow({required String label, required int value, required String subtitle, required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$value%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
      ],
    );
  }

  Widget _miniStat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF8A5BFF), size: 18),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  Widget _recentItem(Map<String, dynamic> e) {
    final title = (e['title'] as String?) ?? 'Okänd';
    final type  = (e['type']  as String?) ?? '';
    final user  = (e['username'] as String?) ?? '—';
    final sn    = e['season_number'];
    final ep    = e['episode_number'];
    final subtitle = sn != null ? 'S${sn.toString().padLeft(2,'0')}E${ep.toString().padLeft(2,'0')}' : type;
    final watched = e['is_watched'] == 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(
          watched ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: watched ? Colors.greenAccent.withValues(alpha: 0.7) : Colors.white24,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          ]),
        ),
        Text(user, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
      ]),
    );
  }

  Widget _userStatRow(Map<String, dynamic> u) {
    final username = (u['username'] as String?) ?? '—';
    final role     = (u['role']     as String?) ?? 'User';
    final watched  = (u['watched']  as int?)    ?? 0;
    final secs     = (u['totalSeconds'] as int?) ?? 0;
    final lastSeen = (u['lastSeen'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: role == 'Admin'
              ? Colors.amber.withValues(alpha: 0.12)
              : const Color(0xFF8A5BFF).withValues(alpha: 0.10),
          child: Text(
            username.isNotEmpty ? username[0].toUpperCase() : '?',
            style: TextStyle(
              color: role == 'Admin' ? Colors.amber : const Color(0xFFB593FF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(username, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(
            lastSeen != null ? 'Senast: ${lastSeen.substring(0,10)}' : 'Aldrig',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
          ),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$watched sedda', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(_formatMinutes(secs ~/ 60), style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
        ]),
      ]),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h >= 24) return '${h ~/ 24}d ${h % 24}h';
    return '${h}h ${m}m';
  }

}

import 'package:flutter/material.dart';
import '../services/api.dart';

class TrashScreen extends StatefulWidget {
  final ApiService apiService;
  /// Called after a successful restore so the parent can refresh its library.
  final VoidCallback? onRestored;

  const TrashScreen({super.key, required this.apiService, this.onRestored});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  String? _error;

  // Filters / sort
  final TextEditingController _searchController = TextEditingController();
  String _sortColumn = 'deleted_at';
  bool _sortAsc = false;
  String _filterResolution = '';
  String _filterYear = '';

  // Expand state for shows: showId -> set of expanded season numbers
  final Map<String, Set<int>> _expandedSeasons = {};

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTrash() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await widget.apiService.fetchTrash();
      setState(() {
        _items = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _restore(String id, String title) async {
    try {
      await widget.apiService.restoreTrashItem(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$title" återställd till biblioteket.'), backgroundColor: const Color(0xFF8A5BFF)),
        );
      }
      _loadTrash();
      widget.onRestored?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Misslyckades återställa: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _permanentDelete(String id, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 10),
            Text('Radera permanent?', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          '"$title" raderas permanent från hårddisken. Detta går inte att ångra.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Radera permanent'),
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
        await widget.apiService.permanentlyDeleteTrashItem(id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$title" raderades permanent.'), backgroundColor: Colors.redAccent),
        );
        _loadTrash();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Misslyckades radera: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  List<dynamic> get _filteredItems {
    final query = _searchController.text.toLowerCase().trim();
    List<dynamic> items = List.from(_items);

    if (query.isNotEmpty) {
      items = items.where((item) {
        final title = (item['title'] ?? '').toString().toLowerCase();
        return title.contains(query);
      }).toList();
    }
    if (_filterResolution.isNotEmpty) {
      items = items.where((item) {
        final res = (item['resolution'] ?? '').toString().toLowerCase();
        return res.contains(_filterResolution.toLowerCase());
      }).toList();
    }
    if (_filterYear.isNotEmpty) {
      items = items.where((item) {
        return item['year']?.toString() == _filterYear;
      }).toList();
    }

    items.sort((a, b) {
      dynamic va = a[_sortColumn];
      dynamic vb = b[_sortColumn];
      if (va == null && vb == null) return 0;
      if (va == null) return _sortAsc ? -1 : 1;
      if (vb == null) return _sortAsc ? 1 : -1;
      final cmp = va.toString().compareTo(vb.toString());
      return _sortAsc ? cmp : -cmp;
    });
    return items;
  }

  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAsc = !_sortAsc;
      } else {
        _sortColumn = column;
        _sortAsc = column != 'deleted_at';
      }
    });
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Papperskorg', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white54),
                  tooltip: 'Uppdatera',
                  onPressed: _loadTrash,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Objekt här raderas permanent om du klickar "Radera permanent". Filer ligger i .trash-mappen tills dess.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
        ),
        const SizedBox(height: 20),

        // Filter bar
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Sök titel...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _filterChip('Upplösning', _filterResolution, (v) => setState(() => _filterResolution = v),
                ['', '4K', '1080p', '720p', '480p']),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                onChanged: (v) => setState(() => _filterYear = v),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'År...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_isLoading)
          const Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF)))
        else if (_error != null)
          Center(child: Text('Fel: $_error', style: const TextStyle(color: Colors.redAccent)))
        else if (_filteredItems.isEmpty)
          Center(
            child: Column(
              children: [
                const SizedBox(height: 40),
                Icon(Icons.delete_outline, size: 64, color: Colors.white.withValues(alpha: 0.15)),
                const SizedBox(height: 16),
                Text('Papperskorgen är tom', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 16)),
              ],
            ),
          )
        else
          Expanded(
            child: Column(
              children: [
                // Table header
                _buildTableHeader(),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      if (item['type'] == 'Show') {
                        return _buildShowRow(item);
                      }
                      return _buildMovieRow(item);
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filterChip(String label, String current, ValueChanged<String> onChanged, List<String> options) {
    return PopupMenuButton<String>(
      tooltip: label,
      color: const Color(0xFF15102A),
      onSelected: onChanged,
      itemBuilder: (_) => options.map((o) => PopupMenuItem(
        value: o,
        child: Text(o.isEmpty ? 'Alla' : o, style: const TextStyle(color: Colors.white)),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: current.isNotEmpty
              ? const Color(0xFF8A5BFF).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: current.isNotEmpty
                ? const Color(0xFF8A5BFF).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.isEmpty ? label : '$label: $current',
              style: TextStyle(
                color: current.isNotEmpty ? const Color(0xFFB593FF) : Colors.white54,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(dynamic item) {
    final title      = item['title'] ?? '—';
    final year       = item['year']?.toString() ?? '—';
    final resolution = item['resolution'] ?? '—';
    final genre      = item['genre'] ?? '—';
    final deletedAt  = _formatDate(item['deleted_at']?.toString());
    final addedAt    = _formatDate(item['added_at']?.toString());
    final filePath   = item['file_path'] ?? '—';
    final plot       = item['plot'] ?? '';
    final posterPath = (item['poster_path'] as String?) ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        final screen = MediaQuery.of(ctx).size;
        // 1/4 av skärmen (50 % bredd × 50 % höjd), centrerad av Dialog-widgeten
        final dw = screen.width  * 0.50;
        final dh = screen.height * 0.50;
        final pad = dw * 0.05;
        final posterW = dw * 0.18;
        final posterH = posterW * 1.45;

        return Dialog(
          backgroundColor: const Color(0xFF15102A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: SizedBox(
            width: dw,
            height: dh,
            child: Column(
              children: [
                // ── Innehåll ──────────────────────────────────
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(pad),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Poster
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: posterPath.isNotEmpty
                              ? Image.network(posterPath,
                                    width: posterW, height: posterH,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _noPoster(posterW, posterH))
                              : _noPoster(posterW, posterH),
                        ),
                        SizedBox(width: pad * 0.6),
                        // Info
                        Expanded(
                          child: SelectionArea(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(title,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: (dw * 0.028).clamp(14, 22),
                                        fontWeight: FontWeight.bold)),
                                SizedBox(height: dh * 0.02),
                                if (plot.isNotEmpty) ...[
                                  SelectableText(plot,
                                      style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          fontSize: (dw * 0.020).clamp(11, 14),
                                          height: 1.45)),
                                  SizedBox(height: dh * 0.03),
                                ],
                                _infoLine(Icons.calendar_today_outlined, 'År', year),
                                _infoLine(Icons.movie_outlined, 'Genre', genre),
                                _infoLine(Icons.hd_outlined, 'Upplösning', resolution),
                                _infoLine(Icons.library_add_outlined, 'Lades till', addedAt),
                                _infoLine(Icons.delete_outline, 'Raderades', deletedAt),
                                if ((item['delete_source'] as String?) == 'auto')
                                  _infoLine(Icons.auto_delete_outlined, 'Källa', 'AUTO-RADERAT (${item['delete_rule'] ?? ''})'),
                                const Spacer(),
                                SelectableText(filePath,
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        fontSize: (dw * 0.014).clamp(9, 12))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Knappar ───────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad * 0.5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Stäng'),
                      ),
                      SizedBox(width: pad * 0.4),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8A5BFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () { Navigator.pop(ctx); _restore(item['id'], title); },
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('Återställ'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _noPoster([double w = 60, double h = 88]) => Container(
    width: w, height: h,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Icon(Icons.movie_outlined, color: Colors.white12, size: (w * 0.33).clamp(16, 28)),
  );

  Widget _infoLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 13, color: Colors.white38),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        Expanded(child: SelectableText(value, style: const TextStyle(color: Colors.white70, fontSize: 12))),
      ]),
    );
  }

  void _showContextMenu(BuildContext context, Offset position, dynamic item) {
    final title = item['title'] ?? '—';
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: const Color(0xFF15102A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      items: [
        PopupMenuItem(value: 'info', child: Row(children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          const Text('Visa info', style: TextStyle(color: Colors.white, fontSize: 13)),
        ])),
        PopupMenuItem(value: 'restore', child: Row(children: [
          const Icon(Icons.restore, size: 16, color: Color(0xFF8A5BFF)),
          const SizedBox(width: 8),
          const Text('Återställ', style: TextStyle(color: Colors.white, fontSize: 13)),
        ])),
        PopupMenuItem(value: 'delete', child: Row(children: [
          const Icon(Icons.delete_forever, size: 16, color: Colors.redAccent),
          const SizedBox(width: 8),
          const Text('Radera permanent', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
        ])),
      ],
    ).then((value) {
      if (value == 'info') _showInfoDialog(item);
      else if (value == 'restore') _restore(item['id'], title);
      else if (value == 'delete') _permanentDelete(item['id'], title);
    });
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white.withValues(alpha: 0.03),
      child: Row(
        children: [
          const SizedBox(width: 52), // cover column
          Expanded(flex: 3, child: _headerCell('Titel', 'title')),
          SizedBox(width: 70, child: _headerCell('År', 'year')),
          SizedBox(width: 90, child: _headerCell('Upplösning', 'resolution')),
          SizedBox(width: 120, child: _headerCell('Raderad', 'deleted_at')),
          const SizedBox(width: 100),
        ],
      ),
    );
  }

  Widget _headerCell(String label, String col) {
    final active = _sortColumn == col;
    return GestureDetector(
      onTap: () => _toggleSort(col),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFFB593FF) : Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              Icon(
                _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: const Color(0xFF8A5BFF),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMovieRow(dynamic item) {
    final title      = item['title'] ?? '—';
    final year       = item['year']?.toString() ?? '—';
    final resolution = item['resolution'] ?? '—';
    final deletedAt  = _formatDate(item['deleted_at']?.toString());
    final posterPath = (item['poster_path'] as String?) ?? '';

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition, item),
      child: Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Cover thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: posterPath.isNotEmpty
                ? Image.network(posterPath,
                      width: 36, height: 52, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _smallPosterPlaceholder())
                : _smallPosterPlaceholder(),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                ),
                if ((item['delete_source'] as String?) == 'auto') ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: const Text('AUTO', style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(year, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          SizedBox(
            width: 90,
            child: _resolutionBadge(resolution),
          ),
          SizedBox(
            width: 120,
            child: Text(deletedAt, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          SizedBox(
            width: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _actionBtn('Visa info', Icons.info_outline, Colors.white38, () => _showInfoDialog(item)),
                const SizedBox(width: 6),
                _actionBtn('Återställ', Icons.restore, const Color(0xFF8A5BFF), () => _restore(item['id'], title)),
                const SizedBox(width: 6),
                _actionBtn('Radera permanent', Icons.delete_forever, Colors.redAccent, () => _permanentDelete(item['id'], title)),
              ],
            ),
          ),
        ],
      ),
      ),  // closes GestureDetector
    );
  }

  Widget _smallPosterPlaceholder() => Container(
    width: 36, height: 52,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Icon(Icons.movie_outlined, color: Colors.white12, size: 14),
  );

  Widget _buildShowRow(dynamic item) {
    final id = item['id'] as String;
    final title = item['title'] ?? '—';
    final year = item['year']?.toString() ?? '—';
    final deletedAt = _formatDate(item['deleted_at']?.toString());
    final episodes = (item['episodes'] as List<dynamic>? ?? []);

    // Group episodes by season
    final Map<int, List<dynamic>> seasons = {};
    for (final ep in episodes) {
      final s = (ep['season_number'] as int? ?? 0);
      seasons.putIfAbsent(s, () => []).add(ep);
    }
    final expandedSeasons = _expandedSeasons.putIfAbsent(id, () => {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Show header row
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04))),
            color: Colors.white.withValues(alpha: 0.02),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    const Icon(Icons.tv_outlined, size: 16, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('$title ($year)',
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if ((item['delete_source'] as String?) == 'auto') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: const Text('AUTO', style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text('${episodes.length} avsnitt',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 70),
              const SizedBox(width: 90),
              SizedBox(
                width: 120,
                child: Text(deletedAt, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ),
              SizedBox(
                width: 160,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _actionBtn('Återställ', Icons.restore, const Color(0xFF8A5BFF), () => _restore(id, title)),
                    const SizedBox(width: 8),
                    _actionBtn('Radera permanent', Icons.delete_forever, Colors.redAccent, () => _permanentDelete(id, title)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Seasons
        ...seasons.entries.map((seasonEntry) {
          final seasonNum = seasonEntry.key;
          final seasonEps = seasonEntry.value;
          final isExpanded = expandedSeasons.contains(seasonNum);

          return Column(
            children: [
              InkWell(
                onTap: () => setState(() {
                  if (isExpanded) {
                    expandedSeasons.remove(seasonNum);
                  } else {
                    expandedSeasons.add(seasonNum);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.only(left: 32, right: 16, top: 8, bottom: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03))),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Säsong $seasonNum  •  ${seasonEps.length} avsnitt',
                        style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                ...seasonEps.map((ep) {
                  final epTitle = ep['title'] ?? 'Avsnitt ${ep['episode_number']}';
                  final epLabel = 'S${seasonNum.toString().padLeft(2, '0')}E${(ep['episode_number'] as int? ?? 0).toString().padLeft(2, '0')} – $epTitle';
                  return Container(
                    padding: const EdgeInsets.only(left: 56, right: 16, top: 6, bottom: 6),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.02))),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(epLabel,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          );
        }),
      ],
    );
  }

  Widget _resolutionBadge(String res) {
    if (res == '—' || res.isEmpty) return Text('—', style: const TextStyle(color: Colors.white38, fontSize: 13));
    Color color = Colors.white38;
    if (res.contains('4K') || res.contains('2160')) color = const Color(0xFF00E676);
    else if (res.contains('1080')) color = const Color(0xFF8A5BFF);
    else if (res.contains('720')) color = const Color(0xFFFFD65C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(res, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _actionBtn(String tooltip, IconData icon, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

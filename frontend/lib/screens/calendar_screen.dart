import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/api.dart';

class CalendarScreen extends StatefulWidget {
  final ApiService apiService;
  final void Function(String showId)? onShowTap;
  final DateTime? initialSelectedDay;
  final ValueChanged<DateTime>? onDayChanged;
  final void Function(String localId, Offset globalPos)? onContextMenu;

  const CalendarScreen({
    super.key,
    required this.apiService,
    this.onShowTap,
    this.initialSelectedDay,
    this.onDayChanged,
    this.onContextMenu,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final CalendarFormat _calendarFormat = CalendarFormat.month;
  late DateTime _focusedDay;
  late DateTime? _selectedDay;

  // Kalendern visar kommande releases från watchlists — ej lokalt bibliotek.
  // Grönt chip = finns redan i biblioteket.
  final Set<String> _activeSources = {'trakt', 'simkl', 'imdb'};
  final Set<String> _activeTypes = {'shows', 'movies'};

  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _loading = false;
  String? _error;

  // Källfärger för chips när items INTE finns i biblioteket.
  // Simkl = cyan (INTE grön — grön = finns i biblioteket).
  // IMDb = guld.
  static const _sourceColors = {
    'trakt':  Colors.redAccent,
    'simkl':  Color(0xFF00BCD4),   // cyan
    'imdb':   Color(0xFFF5C518),   // IMDb-guld
  };
  static Color _colorForSource(String? src) =>
      _sourceColors[src] ?? const Color(0xFF8A5BFF);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSelectedDay ?? DateTime.now();
    _focusedDay  = initial;
    _selectedDay = initial;
    _loadEvents(initial);
  }

  DateTime _normalise(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  Future<void> _loadEvents(DateTime month) async {
    if (_activeSources.isEmpty) {
      setState(() { _events = {}; _loading = false; });
      return;
    }
    setState(() { _loading = true; _error = null; });

    final start = DateTime(month.year, month.month - 1, 1);
    final end   = DateTime(month.year, month.month + 2, 0);
    final days  = end.difference(start).inDays + 1;

    try {
      final futures = <Future<List<dynamic>>>[];
      if (_activeSources.contains('trakt')) {
        futures.add(widget.apiService
            .fetchTraktCalendar(_fmt(start), days: days));
      }
      if (_activeSources.contains('simkl')) {
        futures.add(widget.apiService
            .fetchSimklCalendar(_fmt(start), days: days));
      }
      if (_activeSources.contains('imdb')) {
        futures.add(widget.apiService
            .fetchImdbCalendar(_fmt(start), days: days));
      }

      final results = await Future.wait(futures, eagerError: false);
      final raw = results.expand((r) => r).toList();

      // Deduplera på titel + episod + datum
      final seen = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final e in raw) {
        final key =
            '${(e['title'] as String? ?? '').toLowerCase()}'
            '|${(e['subtitle'] as String? ?? '').toLowerCase()}'
            '|${(e['date'] as String? ?? '')}';
        if (seen.contains(key)) continue;
        seen.add(key);
        deduped.add(Map<String, dynamic>.from(e));
      }

      final Map<DateTime, List<Map<String, dynamic>>> grouped = {};
      for (final e in deduped) {
        final dateStr = (e['date'] as String?)?.substring(0, 10);
        if (dateStr == null) continue;
        final parts = dateStr.split('-');
        if (parts.length != 3) continue;
        final key = DateTime.utc(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]),
        );
        grouped.putIfAbsent(key, () => []).add(e);
      }

      if (mounted) setState(() { _events = grouped; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _eventsForDay(DateTime day) =>
      _events[_normalise(day)] ?? [];

  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() { _selectedDay = selected; _focusedDay = focused; });
    widget.onDayChanged?.call(selected);
  }

  void _onPageChanged(DateTime focusedDay) {
    _focusedDay = focusedDay;
    _loadEvents(focusedDay);
  }

  void _toggleSource(String source) {
    setState(() {
      if (_activeSources.contains(source)) {
        if (_activeSources.length > 1) _activeSources.remove(source);
      } else {
        _activeSources.add(source);
      }
    });
    _loadEvents(_focusedDay);
  }

  void _toggleType(String type) {
    setState(() {
      if (_activeTypes.contains(type)) {
        if (_activeTypes.length > 1) _activeTypes.remove(type);
      } else {
        _activeTypes.add(type);
      }
    });
  }

  static bool _eventIsMovie(Map<String, dynamic> e) {
    final type      = (e['type'] as String? ?? '');
    final mediaType = (e['media_type'] as String? ?? '');
    return type == 'movie' || type == 'trakt_movie' || type == 'imdb_movie' ||
        type == 'simkl_movie' || mediaType == 'Movie';
  }

  List<Map<String, dynamic>> _filteredEventsForDay(DateTime day) {
    return _eventsForDay(day).where((e) {
      if (_eventIsMovie(e)) return _activeTypes.contains('movies');
      return _activeTypes.contains('shows');
    }).toList();
  }


  Color _accentColor(BuildContext context) {
    if (_activeSources.length == 1) return _colorForSource(_activeSources.first);
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(context);
    final selectedEvents = _selectedDay != null
        ? _filteredEventsForDay(_selectedDay!)
        : <Map<String, dynamic>>[];

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(context, accent),
          if (_error != null) _buildErrorBanner(context),
          _buildCalendar(context, accent),
          const Divider(height: 1),
          _buildDayLabel(context, selectedEvents, accent),
          SizedBox(height: 220, child: _buildDetailPanel(selectedEvents, context, accent)),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(_error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context, Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Row(children: [
        // Grön prick = förklaring
        Container(
          width: 10, height: 10,
          decoration: const BoxDecoration(
            color: Color(0xFF2ECC71),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text('= finns i biblioteket',
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.45))),
        const SizedBox(width: 20),
        _Chip(
          label: 'Simkl',
          selected: _activeSources.contains('simkl'),
          color: const Color(0xFF00BCD4),
          onTap: () => _toggleSource('simkl'),
        ),
        const SizedBox(width: 6),
        _Chip(
          label: 'Trakt',
          selected: _activeSources.contains('trakt'),
          color: Colors.redAccent,
          onTap: () => _toggleSource('trakt'),
        ),
        const SizedBox(width: 6),
        _Chip(
          label: 'IMDb',
          selected: _activeSources.contains('imdb'),
          color: const Color(0xFFF5C518),
          onTap: () => _toggleSource('imdb'),
        ),
        const Spacer(),
        _Chip(
          label: 'TV-Serier',
          selected: _activeTypes.contains('shows'),
          color: const Color(0xFF7C4DFF),
          onTap: () => _toggleType('shows'),
        ),
        const SizedBox(width: 6),
        _Chip(
          label: 'Filmer',
          selected: _activeTypes.contains('movies'),
          color: const Color(0xFFFF6D00),
          onTap: () => _toggleType('movies'),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Exportera till .ics',
          child: IconButton(
            icon: const Icon(Icons.download_rounded, size: 20),
            onPressed: _exportIcs,
          ),
        ),
      ]),
    );
  }

  // Bygg en kalender-cell med siffra OVAN och chips UNDER — inga överlapp.
  Widget _dayCell(
    DateTime day,
    bool isToday,
    bool isSelected, {
    required Color accent,
    bool isOutside = false,
  }) {
    final events = isOutside ? <Map<String, dynamic>>[] : _filteredEventsForDay(day);
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final numColor = isOutside
        ? Colors.white.withValues(alpha: 0.2)
        : isSelected
            ? Colors.white
            : isWeekend
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.87);

    return ClipRect(
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Siffra (alltid 26px, aldrig täckt av chips) ──
          SizedBox(
            height: 26,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? accent
                      : isToday
                          ? accent.withValues(alpha: 0.2)
                          : Colors.transparent,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 13,
                    color: numColor,
                    fontWeight: (isSelected || isToday)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
          // ── Chips under siffran ──
          if (events.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _DayChips(events: events, accent: accent),
              ),
            ),
        ],
      ),
    ));
  }

  Widget _buildCalendar(BuildContext context, Color accent) {
    return TableCalendar<Map<String, dynamic>>(
      locale: 'sv_SE',
      firstDay: DateTime.utc(2020, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _focusedDay,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      eventLoader: _filteredEventsForDay,
      onDaySelected: _onDaySelected,
      onPageChanged: _onPageChanged,
      rowHeight: 90,
      calendarBuilders: CalendarBuilders(
        // Custom builders ger full kontroll — siffra alltid ovan chips
        defaultBuilder: (ctx, day, _) =>
            _dayCell(day, false, false, accent: accent),
        todayBuilder: (ctx, day, _) =>
            _dayCell(day, true, isSameDay(day, _selectedDay), accent: accent),
        selectedBuilder: (ctx, day, _) =>
            _dayCell(day, isSameDay(day, DateTime.now()), true, accent: accent),
      ),
      calendarStyle: const CalendarStyle(
        outsideDaysVisible: false,
        cellMargin: EdgeInsets.zero,
        markersMaxCount: 0,
      ),
      headerStyle: const HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
      ),
    );
  }

  Widget _buildDayLabel(BuildContext context,
      List<Map<String, dynamic>> events, Color accent) {
    if (_selectedDay == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final isToday = isSameDay(_selectedDay, DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(children: [
        Text(
          isToday ? 'Idag' : _fmtDisplayDate(_selectedDay!),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isToday ? accent : theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        if (events.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${events.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.bold,
                )),
          ),
      ]),
    );
  }

  String _fmtDisplayDate(DateTime d) {
    const months = [
      'jan','feb','mar','apr','maj','jun',
      'jul','aug','sep','okt','nov','dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _buildDetailPanel(List<Map<String, dynamic>> events,
      BuildContext context, Color accent) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (events.isEmpty) {
      return Center(
        key: ValueKey(_selectedDay?.toIso8601String() ?? 'none'),
        child: Text(
          _selectedDay != null ? 'Inga händelser denna dag.' : 'Välj en dag.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.35),
              ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.05),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: ListView.builder(
        key: ValueKey(_selectedDay?.millisecondsSinceEpoch ?? 0),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: events.length,
        itemBuilder: (ctx, i) => _MediaCard(
          event: events[i],
          accent: _colorForSource(events[i]['source'] as String?),
          apiService: widget.apiService,
          onTap: widget.onShowTap,
          onDownload: () => _onDownload(events[i]),
          onContextMenu: widget.onContextMenu,
        ),
      ),
    );
  }

  void _onDownload(Map<String, dynamic> event) {
    final type      = event['type']       as String? ?? '';
    final mediaType = event['media_type'] as String? ?? '';
    final isMovie   = type == 'movie' || type == 'trakt_movie' || mediaType == 'Movie';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text('${isMovie ? 'Radarr' : 'Sonarr'}-integration kommer snart.'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  void _exportIcs() {
    final url = widget.apiService.calendarIcsUrl();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exportera kalender'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Importera direkt i din kalenderapp:'),
            const SizedBox(height: 12),
            SelectableText(url,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Stäng')),
        ],
      ),
    );
  }
}

// ── Chips inuti kalendercellen ─────────────────────────────────────────────

class _DayChips extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final Color accent;

  const _DayChips({required this.events, required this.accent});

  String _label(Map<String, dynamic> e) {
    final title    = (e['title'] as String? ?? '').trim();
    final subtitle = (e['subtitle'] as String? ?? '').trim();
    final type     = (e['type'] as String? ?? '');
    if (type == 'movie') return title;
    final code = subtitle.split(' – ').first.trim();
    if (title.isNotEmpty && code.isNotEmpty) return '$title $code';
    return title.isNotEmpty ? title : code;
  }

  bool _isMovie(Map<String, dynamic> e) {
    final type      = (e['type'] as String? ?? '');
    final mediaType = (e['media_type'] as String? ?? '');
    return type == 'movie' || type == 'trakt_movie' || type == 'imdb_movie' || mediaType == 'Movie';
  }

  Color _chipColor(Map<String, dynamic> e) {
    // GRÖN om finns i biblioteket
    final inLib = e['in_library'] as bool? ?? false;
    if (inLib) return const Color(0xFF2ECC71);
    // Orange för film, källfärg för serier
    if (_isMovie(e)) return const Color(0xFFE67E22);
    return _CalendarScreenState._colorForSource(e['source'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    const maxVisible = 3;
    final visible  = events.take(maxVisible).toList();
    final overflow = events.length - maxVisible;

    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...visible.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: _chipColor(e).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: _ChipRow(label: _label(e), isMovie: _isMovie(e)),
                )),
            if (overflow > 0)
              Text(
                '+$overflow till',
                style: TextStyle(
                  fontSize: 9,
                  color: accent.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Chip-rad: text + typ-ikon till höger ──────────────────────────────────

class _ChipRow extends StatelessWidget {
  final String label;
  final bool isMovie;
  const _ChipRow({required this.label, required this.isMovie});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 3),
        Icon(
          isMovie ? Icons.movie_outlined : Icons.tv_outlined,
          size: 9,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      ],
    );
  }
}

// ── Media-kort med hover-popup ─────────────────────────────────────────────

class _MediaCard extends StatefulWidget {
  final Map<String, dynamic> event;
  final Color accent;
  final ApiService apiService;
  final void Function(String showId)? onTap;
  final VoidCallback onDownload;
  final void Function(String localId, Offset globalPos)? onContextMenu;

  const _MediaCard({
    required this.event,
    required this.accent,
    required this.apiService,
    this.onTap,
    required this.onDownload,
    this.onContextMenu,
  });

  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
  final _key = GlobalKey();
  OverlayEntry? _popup;
  bool _hovered = false;
  Timer? _showTimer;
  Timer? _hideTimer;

  @override
  void dispose() {
    _removePopup();
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  String? get _navId {
    final showId  = widget.event['show_id']  as String?;
    final tmdbId  = widget.event['tmdb_id']  as String?;
    final type    = (widget.event['type']    as String? ?? '');
    final mType   = (widget.event['media_type'] as String? ?? '');
    final isMovie = type == 'movie' || type == 'trakt_movie' || mType == 'Movie';
    return showId ??
        (tmdbId != null
            ? (isMovie ? 'external_movie_$tmdbId' : 'external_show_$tmdbId')
            : null);
  }

  void _onEnter(PointerEnterEvent _) {
    _hovered = true;
    _hideTimer?.cancel();
    // Slight delay so quick mouse passes don't trigger popup
    _showTimer?.cancel();
    _showTimer = Timer(const Duration(milliseconds: 350), () {
      if (_hovered && mounted) _showPopup();
    });
  }

  void _onExit(PointerExitEvent _) {
    _hovered = false;
    _showTimer?.cancel();
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 220), () {
      if (!_hovered) _removePopup();
    });
  }

  void _removePopup() {
    _popup?.remove();
    _popup = null;
  }

  void _showPopup() {
    if (!mounted) return;
    _removePopup();

    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final pos      = box.localToGlobal(Offset.zero);
    final cardSize = box.size;
    final screen   = MediaQuery.of(context).size;

    const popupW = 310.0;
    const popupMaxH = 290.0;

    // Try to the right, fall back to left
    double left = pos.dx + cardSize.width + 12;
    if (left + popupW > screen.width - 12) {
      left = pos.dx - popupW - 12;
    }
    // Align top with card, clamp to screen
    double top = pos.dy;
    if (top + popupMaxH > screen.height - 12) {
      top = screen.height - popupMaxH - 12;
    }
    top = top.clamp(12.0, screen.height.toDouble());

    _popup = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: top,
        child: MouseRegion(
          onEnter: (_) => _hideTimer?.cancel(),
          onExit:  (_) => _scheduleHide(),
          child: _HoverPopup(
            event: widget.event,
            apiService: widget.apiService,
            width: popupW,
            maxHeight: popupMaxH,
          ),
        ),
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_popup!);
  }

  @override
  Widget build(BuildContext context) {
    final posterPath  = widget.event['poster_path'] as String?;
    final title       = (widget.event['title']    as String? ?? '').trim();
    final subtitle    = (widget.event['subtitle'] as String? ?? '').trim();
    final isInLibrary = widget.event['in_library'] as bool? ?? false;
    final type        = (widget.event['type']    as String? ?? '');
    final mediaType   = (widget.event['media_type'] as String? ?? '');
    final isMovie     = type == 'movie' || type == 'trakt_movie' || mediaType == 'Movie';
    final navId       = _navId;
    final canNav      = navId != null && widget.onTap != null;

    // Grön = i biblioteket, orange = film ej i bibl, blå = serie ej i bibl
    final cardAccent = isInLibrary
        ? const Color(0xFF2ECC71)
        : isMovie ? const Color(0xFFE67E22) : const Color(0xFF3498DB);
    final btnColor = cardAccent;

    return MouseRegion(
      cursor: canNav ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: _onEnter,
      onExit:  _onExit,
      child: Listener(
        onPointerDown: isInLibrary && navId != null ? (event) {
          if (event.buttons == kSecondaryMouseButton) {
            widget.onContextMenu?.call(navId, event.position);
          }
        } : null,
        child: GestureDetector(
        key: _key,
        onTap: canNav ? () => widget.onTap!(navId) : null,
        child: Container(
          width: 90,
          margin: const EdgeInsets.only(right: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster — fast 2:3-ratio (90px bred → 135px hög)
              SizedBox(
                height: 135,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: isInLibrary
                        ? Border.all(
                            color: const Color(0xFF2ECC71),
                            width: 2)
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isInLibrary ? 6 : 8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _PosterImage(url: posterPath, isMovie: isMovie),
                        if (canNav)
                          Positioned(
                            bottom: 6, right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: cardAccent.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_forward,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              // Spela (i biblioteket) eller Hämta (ej i biblioteket)
              SizedBox(
                width: double.infinity,
                height: 28,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    side: BorderSide(
                        color: btnColor.withValues(alpha: 0.6), width: 1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    foregroundColor: btnColor,
                  ),
                  onPressed: isInLibrary && canNav
                      ? () => widget.onTap!(navId)
                      : widget.onDownload,
                  icon: Icon(
                    isInLibrary ? Icons.play_arrow_rounded : Icons.download_rounded,
                    size: 13, color: btnColor),
                  label: Text(isInLibrary ? 'Spela' : 'Hämta',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: btnColor)),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ── Hover-popup med plot ───────────────────────────────────────────────────

class _HoverPopup extends StatefulWidget {
  final Map<String, dynamic> event;
  final ApiService apiService;
  final double width;
  final double maxHeight;

  const _HoverPopup({
    required this.event,
    required this.apiService,
    required this.width,
    required this.maxHeight,
  });

  @override
  State<_HoverPopup> createState() => _HoverPopupState();
}

class _HoverPopupState extends State<_HoverPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  String? _plot;
  bool _loadingPlot = true;
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.04, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
    _fetchPlot();
  }

  @override
  void dispose() {
    _anim.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchPlot() async {
    final showId  = widget.event['show_id']  as String?;
    final tmdbId  = widget.event['tmdb_id']  as String?;
    final type    = (widget.event['type']    as String? ?? '');
    final mType   = (widget.event['media_type'] as String? ?? '');
    final isMovie = type == 'movie' || type == 'trakt_movie' || mType == 'Movie';

    final id = showId ??
        (tmdbId != null
            ? (isMovie ? 'external_movie_$tmdbId' : 'external_show_$tmdbId')
            : null);

    if (id == null) {
      if (mounted) setState(() => _loadingPlot = false);
      return;
    }

    try {
      final data = await widget.apiService.fetchMediaDetails(id);
      if (mounted) {
        setState(() {
          _plot = (data['plot'] as String? ?? '').trim();
          _loadingPlot = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPlot = false);
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _scrollCtrl.animateTo(
          (_scrollCtrl.offset + 40).clamp(0.0, _scrollCtrl.position.maxScrollExtent),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _scrollCtrl.animateTo(
          (_scrollCtrl.offset - 40).clamp(0.0, _scrollCtrl.position.maxScrollExtent),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final event      = widget.event;
    final posterPath = event['poster_path'] as String?;
    final title      = (event['title']    as String? ?? '').trim();
    final subtitle   = (event['subtitle'] as String? ?? '').trim();
    final source     = (event['source']   as String? ?? '');
    final inLibrary  = event['in_library'] as bool? ?? true;

    final sourceColor = _CalendarScreenState._colorForSource(source);
    final sourceName  = source == 'trakt'
        ? 'Trakt'
        : source == 'simkl'
            ? 'Simkl'
            : 'Lokalt';

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Material(
          elevation: 12,
          color: Colors.transparent,
          child: Container(
            width: widget.width,
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            decoration: BoxDecoration(
              color: const Color(0xFF12101E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: poster + titel + badges ──
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mini poster
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 52,
                          height: 74,
                          child: _PosterImage(
                              url: posterPath,
                              isMovie: (event['type'] as String? ?? '') ==
                                  'movie'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(subtitle,
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.55),
                                        fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            const SizedBox(height: 6),
                            // Badges
                            Wrap(spacing: 5, runSpacing: 4, children: [
                              _Badge(label: sourceName, color: sourceColor),
                              if (!inLibrary)
                                _Badge(
                                    label: 'Ej i biblioteket',
                                    color: Colors.white30),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Divider ──
                Divider(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.07)),

                // ── Plot (scrollable) ──
                Flexible(
                  child: Focus(
                    focusNode: _focusNode,
                    autofocus: true,
                    onKeyEvent: _handleKey,
                    child: Scrollbar(
                      controller: _scrollCtrl,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        child: _loadingPlot
                            ? Row(children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white
                                          .withValues(alpha: 0.4)),
                                ),
                                const SizedBox(width: 8),
                                Text('Laddar handlingen...',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.4),
                                        fontSize: 12)),
                              ])
                            : (_plot?.isNotEmpty == true
                                ? Text(
                                    _plot!,
                                    style: TextStyle(
                                      color: Colors.white
                                          .withValues(alpha: 0.75),
                                      fontSize: 12,
                                      height: 1.55,
                                    ),
                                  )
                                : Text(
                                    'Ingen handling tillgänglig.',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.3),
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic),
                                  )),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Poster-bild med fallback ───────────────────────────────────────────────

class _PosterImage extends StatelessWidget {
  final String? url;
  final bool isMovie;
  const _PosterImage({this.url, this.isMovie = false});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return Image.network(
        url!,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.grey[900],
            child: const Center(
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF1A1A2E),
        child: Icon(
          isMovie ? Icons.movie_outlined : Icons.tv_outlined,
          size: 32,
          color: Colors.white24,
        ),
      );
}

// ── Toggle-chip i headern ──────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? c : Colors.transparent,
            border: Border.all(color: selected ? c : Colors.grey[700]!),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : Colors.grey,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

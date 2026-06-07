import 'package:flutter/material.dart';
import '../services/api.dart';

// ── Data classes ──────────────────────────────────────────────────────────────

class _InfoRow {
  final String label;
  final String? value;
  const _InfoRow(this.label, this.value);
}

class _VersionData {
  final String id;
  final String resolution;
  final String filename;
  final String filePath;
  final Map<String, dynamic> info;

  const _VersionData({
    required this.id,
    required this.resolution,
    required this.filename,
    required this.filePath,
    required this.info,
  });

  String get dropdownLabel {
    final parts = <String>[];
    if (resolution.isNotEmpty) parts.add(resolution);
    if (filename.isNotEmpty) parts.add(filename);
    return parts.join(' — ');
  }
}

// ── Widget ────────────────────────────────────────────────────────────────────

class MediaInfoDialog extends StatefulWidget {
  final String mediaId;
  final String title;
  final ApiService apiService;

  const MediaInfoDialog({
    super.key,
    required this.mediaId,
    required this.title,
    required this.apiService,
  });

  @override
  State<MediaInfoDialog> createState() => _MediaInfoDialogState();
}

class _MediaInfoDialogState extends State<MediaInfoDialog> {
  List<_VersionData>? _versions;
  String? _error;
  bool _loading = true;
  String? _selectedVersionId; // null = visa alla

  // Expansion state per version: id → [mediaExpanded, fileExpanded, dataExpanded]
  final Map<String, List<bool>> _expanded = {};
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final details = await widget.apiService.fetchMediaDetails(widget.mediaId);
      final rawVersions = (details['versions'] as List?) ?? [];

      final versionList = rawVersions.isNotEmpty
          ? rawVersions
          : <dynamic>[{'id': widget.mediaId, 'file_path': '', 'resolution': ''}];

      final futures = versionList.map((v) async {
        final vid = (v as Map)['id']?.toString() ?? widget.mediaId;
        final info = await widget.apiService.fetchTechInfo(vid);
        return _VersionData(
          id: vid,
          resolution: v['resolution']?.toString() ?? '',
          filename: info['filename']?.toString() ?? '',
          filePath: info['file_path']?.toString() ?? v['file_path']?.toString() ?? '',
          info: Map<String, dynamic>.from(info),
        );
      });

      final versions = await Future.wait(futures);

      for (final v in versions) {
        _expanded[v.id] = [true, true, true];
        _keys[v.id] = GlobalKey();
      }

      if (mounted) setState(() { _versions = versions; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<_VersionData> get _visible {
    if (_versions == null) return [];
    if (_selectedVersionId == null) return _versions!;
    return _versions!.where((v) => v.id == _selectedVersionId).toList();
  }

  bool get _hasMultiple => (_versions?.length ?? 0) > 1;

  void _scrollTo(String versionId) {
    final ctx = _keys[versionId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    // Dialog = 1/4 of screen area (50% width × 50% height), centered by Dialog widget
    final dialogWidth  = screen.width  * 0.50;
    final dialogHeight = screen.height * 0.50;

    return Dialog(
      backgroundColor: const Color(0xFF0E1219),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width:  dialogWidth,
        height: dialogHeight,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(dialogWidth * 0.033, dialogHeight * 0.06, dialogWidth * 0.017, 0),
              child: Row(
                children: [
                  Text('Info',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: (dialogWidth * 0.025).clamp(14, 22),
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(dialogWidth * 0.033, dialogHeight * 0.012, dialogWidth * 0.033, dialogHeight * 0.03),
              child: Text(widget.title,
                  style: TextStyle(color: Colors.white54, fontSize: (dialogWidth * 0.017).clamp(11, 14)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),

            // Dropdown (alltid synlig efter laddning)
            if (!_loading && _versions != null)
              Padding(
                padding: EdgeInsets.fromLTRB(dialogWidth * 0.033, 0, dialogWidth * 0.033, dialogHeight * 0.036),
                child: _buildDropdownRow(),
              ),

            const Divider(color: Colors.white10, height: 1),

            // Innehåll — fyller resten av dialogen
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF)))
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: SelectableText('Fel: $_error',
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                        )
                      : SingleChildScrollView(
                          controller: _scroll,
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _visible.asMap().entries.map((e) {
                              final isLast = e.key == _visible.length - 1;
                              return _buildVersionBlock(e.value, addBottomSep: !isLast);
                            }).toList(),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dropdown ──────────────────────────────────────────────────────────────

  Widget _buildDropdownRow() {
    // Enkel filsökväg om bara en version
    if (!_hasMultiple) {
      return SelectableText(
        _versions!.first.filePath,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      );
    }

    return Row(
      children: [
        Text('Version:',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedVersionId,
                dropdownColor: const Color(0xFF15102A),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                isDense: true,
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Alla versioner'),
                  ),
                  ..._versions!.map((v) => DropdownMenuItem<String?>(
                    value: v.id,
                    child: Text(v.dropdownLabel,
                        overflow: TextOverflow.ellipsis),
                  )),
                ],
                onChanged: (val) {
                  setState(() => _selectedVersionId = val);
                  if (val != null) {
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _scrollTo(val));
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Version block ─────────────────────────────────────────────────────────

  Widget _buildVersionBlock(_VersionData v, {required bool addBottomSep}) {
    final exp = _expanded[v.id] ?? [true, true, true];

    return Container(
      key: _keys[v.id],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Versionsrubrik (bara synlig vid flera versioner)
          if (_hasMultiple)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                border: Border(
                  top: BorderSide(
                      color: const Color(0xFF8A5BFF).withValues(alpha: 0.4),
                      width: 1.5),
                ),
              ),
              child: Row(
                children: [
                  if (v.resolution.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8A5BFF).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: const Color(0xFF8A5BFF)
                                .withValues(alpha: 0.5)),
                      ),
                      child: Text(v.resolution,
                          style: const TextStyle(
                              color: Color(0xFFB593FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Filnamn tydligt
                  Expanded(
                    child: SelectableText(
                      v.filename,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // Filsökväg (alltid synlig)
          Padding(
            padding: EdgeInsets.fromLTRB(20, _hasMultiple ? 8 : 12, 20, 6),
            child: SelectableText(
              v.filePath,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),

          // Media (vänster) + Fil (höger) sida vid sida
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _section(
                    'Media', exp[0],
                    () => setState(() => exp[0] = !exp[0]),
                    _mediaRows(v.info),
                  ),
                ),
                const VerticalDivider(
                    color: Colors.white10, width: 1, thickness: 1),
                Expanded(
                  child: _section(
                    'Fil', exp[1],
                    () => setState(() => exp[1] = !exp[1]),
                    _fileRows(v),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),

          // Data (full bredd)
          _section(
            'Data', exp[2],
            () => setState(() => exp[2] = !exp[2]),
            _dataRows(v.info),
          ),

          if (addBottomSep)
            const Divider(color: Colors.white24, height: 1, thickness: 1),
        ],
      ),
    );
  }

  // ── Section & row ─────────────────────────────────────────────────────────

  Widget _section(
      String label, bool expanded, VoidCallback onToggle, List<_InfoRow> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: const Color(0xFF8A5BFF),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows.map(_row).toList(),
            ),
          ),
      ],
    );
  }

  Widget _row(_InfoRow r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(r.label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12)),
          ),
          Expanded(
            child: SelectableText(
              r.value ?? '—',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Row builders ──────────────────────────────────────────────────────────

  Map<String, dynamic> _vd(Map<String, dynamic> info) =>
      (info['video'] as Map<String, dynamic>?) ?? {};

  Map<String, dynamic> _ad(Map<String, dynamic> info) {
    final list = info['audio'] as List?;
    return (list != null && list.isNotEmpty)
        ? Map<String, dynamic>.from(list[0] as Map)
        : {};
  }

  List<_InfoRow> _mediaRows(Map<String, dynamic> info) {
    final v = _vd(info);
    final a = _ad(info);
    return [
      _InfoRow('Duration',         info['duration_str']?.toString()),
      _InfoRow('Bitrate',          _fmtKbps(info['total_bitrate_kbps'])),
      _InfoRow('Width',            v['width']?.toString()),
      _InfoRow('Height',           v['height']?.toString()),
      _InfoRow('Aspect Ratio',     v['aspect_ratio'] != null ? '${v['aspect_ratio']}:1' : null),
      _InfoRow('Video Resolution', info['resolution']?.toString()),
      _InfoRow('Container',        info['container']?.toString()),
      _InfoRow('Video Frame Rate', v['frame_rate'] != null ? '${v['frame_rate']}p' : null),
      _InfoRow('Audio Profile',    a['profile']?.toString()),
      _InfoRow('Video Profile',    v['profile']?.toString()),
    ];
  }

  List<_InfoRow> _fileRows(_VersionData ver) {
    final a = _ad(ver.info);
    final v = _vd(ver.info);
    return [
      _InfoRow('Duration',      ver.info['duration_str']?.toString()),
      _InfoRow('Filnamn',       ver.filename),
      _InfoRow('Storlek',       _fmtSize(ver.info['file_size_bytes'])),
      _InfoRow('Audio Profile', a['profile']?.toString()),
      _InfoRow('Container',     ver.info['container']?.toString()),
      _InfoRow('Video Profile', v['profile']?.toString()),
    ];
  }

  List<_InfoRow> _dataRows(Map<String, dynamic> info) {
    final v = _vd(info);
    final a = _ad(info);
    return [
      _InfoRow('Codec',               v['codec']?.toString()),
      _InfoRow('Bitrate',             _fmtKbps(v['bitrate_kbps'])),
      _InfoRow('Språk',               _langSv(a['language']?.toString())),
      _InfoRow('Language Tag',        a['language']?.toString()),
      _InfoRow('Bit Depth',           v['bit_depth']?.toString()),
      _InfoRow('Chroma Location',     v['chroma_location']?.toString()),
      _InfoRow('Chroma Subsampling',  v['chroma_subsampling']?.toString()),
      _InfoRow('Coded Height',        v['coded_height']?.toString()),
      _InfoRow('Coded Width',         v['coded_width']?.toString()),
      _InfoRow('Frame Rate',          v['frame_rate'] != null ? '${v['frame_rate']} fps' : null),
      _InfoRow('Height',              v['height']?.toString()),
      _InfoRow('Nivå',                v['level']?.toString()),
    ];
  }

  // ── Formatters ────────────────────────────────────────────────────────────

  String? _fmtKbps(dynamic val) {
    if (val == null) return null;
    final n = int.tryParse(val.toString());
    if (n == null || n == 0) return null;
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} kbps';
  }

  String? _fmtSize(dynamic val) {
    if (val == null) return null;
    final b = int.tryParse(val.toString());
    if (b == null || b == 0) return null;
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '$b B';
  }

  String? _langSv(String? lang) {
    if (lang == null) return null;
    const map = {
      'eng': 'Engelska', 'en': 'Engelska',
      'swe': 'Svenska',  'sv': 'Svenska',
      'nor': 'Norska',   'no': 'Norska',
      'dan': 'Danska',   'da': 'Danska',
      'fin': 'Finska',   'fi': 'Finska',
      'ger': 'Tyska',    'de': 'Tyska',
      'fre': 'Franska',  'fr': 'Franska',
      'spa': 'Spanska',  'es': 'Spanska',
      'ita': 'Italienska','it': 'Italienska',
      'jpn': 'Japanska', 'ja': 'Japanska',
      'chi': 'Kinesiska','zh': 'Kinesiska',
      'kor': 'Koreanska','ko': 'Koreanska',
      'rus': 'Ryska',    'ru': 'Ryska',
      'ara': 'Arabiska', 'ar': 'Arabiska',
      'por': 'Portugisiska','pt': 'Portugisiska',
      'dut': 'Holländska','nl': 'Holländska',
    };
    return map[lang.toLowerCase()] ?? lang.toUpperCase();
  }
}

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
  final String label;       // display label in dropdown
  String filePath;
  Map<String, dynamic> info;

  _VersionData({
    required this.id,
    required this.label,
    required this.filePath,
    required this.info,
  });
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
  bool _loadingVersion = false;
  String? _selectedVersionId;
  bool _isShow = false;

  final Map<String, List<bool>> _expanded = {};
  final Map<String, GlobalKey> _keys = {};
  final ScrollController _scroll = ScrollController();

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
      final type = details['type']?.toString() ?? '';
      _isShow = type == 'Show';

      List<_VersionData> versionList;

      if (_isShow) {
        // For shows: use episodes as versions — lazy-load tech info
        final episodes = (details['episodes'] as List?) ?? [];
        versionList = episodes.map((ep) {
          final s = ep['season_number']?.toString().padLeft(2, '0') ?? '01';
          final e = ep['episode_number']?.toString().padLeft(2, '0') ?? '01';
          final epTitle = ep['title']?.toString() ?? '';
          final label = 'S${s}E$e${epTitle.isNotEmpty ? ' — $epTitle' : ''}';
          return _VersionData(
            id: ep['id']?.toString() ?? '',
            label: label,
            filePath: ep['file_path']?.toString() ?? '',
            info: {},
          );
        }).toList();

        if (versionList.isEmpty) {
          // Fallback: use show ID (tech-info will pick first episode)
          versionList = [_VersionData(id: widget.mediaId, label: 'Avsnitt', filePath: '', info: {})];
        }
      } else {
        // For movies: use versions
        final rawVersions = (details['versions'] as List?) ?? [];
        final raw = rawVersions.isNotEmpty
            ? rawVersions
            : <dynamic>[{'id': widget.mediaId, 'file_path': '', 'resolution': '', 'release_version': ''}];

        final futures = raw.map((v) async {
          final vid = (v as Map)['id']?.toString() ?? widget.mediaId;
          final info = await widget.apiService.fetchTechInfo(vid);
          final res = v['resolution']?.toString() ?? '';
          final ver = v['release_version']?.toString() ?? '';
          final filename = info['filename']?.toString() ?? '';
          final parts = <String>[if (res.isNotEmpty) res, if (ver.isNotEmpty) ver, if (filename.isNotEmpty) filename];
          return _VersionData(
            id: vid,
            label: parts.join(' — '),
            filePath: info['file_path']?.toString() ?? v['file_path']?.toString() ?? '',
            info: Map<String, dynamic>.from(info),
          );
        });

        versionList = await Future.wait(futures);
      }

      for (final v in versionList) {
        _expanded[v.id] = [true, true, true];
        _keys[v.id] = GlobalKey();
      }

      if (mounted) {
        setState(() {
          _versions = versionList;
          _selectedVersionId = versionList.isNotEmpty ? versionList.first.id : null;
          _loading = false;
        });
      }

      // For shows: load tech info for the first episode
      if (_isShow && versionList.isNotEmpty) {
        await _loadTechInfoFor(versionList.first.id);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadTechInfoFor(String versionId) async {
    final ver = _versions?.firstWhere((v) => v.id == versionId, orElse: () => _VersionData(id: '', label: '', filePath: '', info: {}));
    if (ver == null || ver.id.isEmpty || ver.info.isNotEmpty) return;
    setState(() => _loadingVersion = true);
    try {
      final info = await widget.apiService.fetchTechInfo(versionId);
      ver.info = Map<String, dynamic>.from(info);
      if (ver.filePath.isEmpty) ver.filePath = info['file_path']?.toString() ?? '';
      if (mounted) setState(() => _loadingVersion = false);
    } catch (_) {
      if (mounted) setState(() => _loadingVersion = false);
    }
  }

  _VersionData? get _selected {
    if (_versions == null || _selectedVersionId == null) return null;
    try {
      return _versions!.firstWhere((v) => v.id == _selectedVersionId);
    } catch (_) {
      return _versions!.isNotEmpty ? _versions!.first : null;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
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

            // Dropdown
            if (!_loading && _versions != null)
              Padding(
                padding: EdgeInsets.fromLTRB(dialogWidth * 0.033, 0, dialogWidth * 0.033, dialogHeight * 0.036),
                child: _buildDropdown(dialogWidth),
              ),

            const Divider(color: Colors.white10, height: 1),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF)))
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: SelectableText('Fel: $_error',
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                        )
                      : _loadingVersion
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF)))
                          : SingleChildScrollView(
                              controller: _scroll,
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _selected != null
                                  ? _buildVersionBlock(_selected!)
                                  : const SizedBox.shrink(),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Dropdown ──────────────────────────────────────────────────────────────

  Widget _buildDropdown(double dialogWidth) {
    final versions = _versions ?? [];

    if (versions.length == 1 && !_isShow) {
      return SelectableText(
        versions.first.filePath,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      );
    }

    final label = _isShow ? 'Avsnitt:' : 'Version:';

    return Row(
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
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
              child: DropdownButton<String>(
                value: _selectedVersionId,
                dropdownColor: const Color(0xFF15102A),
                style: const TextStyle(color: Colors.white, fontSize: 12),
                isDense: true,
                isExpanded: true,
                items: versions.map((v) => DropdownMenuItem<String>(
                  value: v.id,
                  child: Text(v.label, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (val) async {
                  if (val == null || val == _selectedVersionId) return;
                  setState(() => _selectedVersionId = val);
                  await _loadTechInfoFor(val);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Version block ─────────────────────────────────────────────────────────

  Widget _buildVersionBlock(_VersionData v) {
    final exp = _expanded[v.id] ?? [true, true, true];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (v.filePath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: SelectableText(
              v.filePath,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),

        // Media + Fil sida vid sida
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _section('Media', exp[0], () => setState(() => exp[0] = !exp[0]), _mediaRows(v.info)),
              ),
              const VerticalDivider(color: Colors.white10, width: 1, thickness: 1),
              Expanded(
                child: _section('Fil', exp[1], () => setState(() => exp[1] = !exp[1]), _fileRows(v)),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),

        // Ljud (alla spår)
        _buildAudioSection(v.info, exp),

        // Undertext
        _buildSubtitleSection(v.info, exp),

        // Data (tech details)
        _section('Data', exp[2], () => setState(() => exp[2] = !exp[2]), _dataRows(v.info)),
      ],
    );
  }

  Widget _buildAudioSection(Map<String, dynamic> info, List<bool> exp) {
    final audioList = (info['audio'] as List?) ?? [];
    if (audioList.isEmpty) return const SizedBox.shrink();

    final rows = <_InfoRow>[];
    for (int i = 0; i < audioList.length; i++) {
      final a = Map<String, dynamic>.from(audioList[i] as Map);
      final lang = _langSv(a['language']?.toString()) ?? 'Okänt';
      final codec = a['codec']?.toString() ?? '';
      final channels = a['channels']?.toString() ?? '';
      final kbps = _fmtKbps(a['bitrate_kbps']);
      final title = a['title']?.toString();
      final parts = <String>[
        if (codec.isNotEmpty) codec,
        if (channels.isNotEmpty) '${channels}ch',
        if (kbps != null) kbps,
        if (title != null && title.isNotEmpty) title,
      ];
      rows.add(_InfoRow('Spår ${i + 1}  $lang', parts.join(' · ')));
    }

    final expanded = exp.length > 3 ? exp[3] : true;
    return Column(
      children: [
        _section('Ljud', expanded, () {
          if (exp.length > 3) {
            setState(() => exp[3] = !exp[3]);
          } else {
            exp.add(!expanded);
            setState(() {});
          }
        }, rows),
        const Divider(color: Colors.white10, height: 1),
      ],
    );
  }

  Widget _buildSubtitleSection(Map<String, dynamic> info, List<bool> exp) {
    final subList = (info['subtitles'] as List?) ?? [];
    if (subList.isEmpty) return const SizedBox.shrink();

    final rows = <_InfoRow>[];
    for (int i = 0; i < subList.length; i++) {
      final s = Map<String, dynamic>.from(subList[i] as Map);
      final lang = _langSv(s['language']?.toString()) ?? 'Okänt';
      final codec = s['codec']?.toString() ?? '';
      final title = s['title']?.toString();
      final parts = <String>[
        if (codec.isNotEmpty) codec,
        if (title != null && title.isNotEmpty) title,
      ];
      rows.add(_InfoRow('Spår ${i + 1}  $lang', parts.isNotEmpty ? parts.join(' · ') : lang));
    }

    final expanded = exp.length > 4 ? exp[4] : true;
    return Column(
      children: [
        _section('Undertext', expanded, () {
          if (exp.length > 4) {
            setState(() => exp[4] = !exp[4]);
          } else {
            while (exp.length < 5) exp.add(true);
            exp[4] = !expanded;
            setState(() {});
          }
        }, rows),
        const Divider(color: Colors.white10, height: 1),
      ],
    );
  }

  // ── Section & row ─────────────────────────────────────────────────────────

  Widget _section(String label, bool expanded, VoidCallback onToggle, List<_InfoRow> rows) {
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
                  expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  color: const Color(0xFF8A5BFF),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
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
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
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

  List<_InfoRow> _mediaRows(Map<String, dynamic> info) {
    final v = _vd(info);
    final audioList = (info['audio'] as List?) ?? [];
    final firstAudio = audioList.isNotEmpty ? Map<String, dynamic>.from(audioList[0] as Map) : <String, dynamic>{};
    return [
      _InfoRow('Duration',         info['duration_str']?.toString()),
      _InfoRow('Bitrate',          _fmtKbps(info['total_bitrate_kbps'])),
      _InfoRow('Video Resolution', info['resolution']?.toString()),
      _InfoRow('Container',        info['container']?.toString()),
      _InfoRow('Frame Rate',       v['frame_rate'] != null ? '${v['frame_rate']}p' : null),
      _InfoRow('Aspect Ratio',     v['aspect_ratio'] != null ? '${v['aspect_ratio']}:1' : null),
      _InfoRow('Audio',            firstAudio['codec']?.toString()),
      _InfoRow('Video Profile',    v['profile']?.toString()),
    ];
  }

  List<_InfoRow> _fileRows(_VersionData ver) {
    final v = _vd(ver.info);
    return [
      _InfoRow('Filnamn',       ver.label.isNotEmpty ? ver.label : (ver.info['filename']?.toString())),
      _InfoRow('Storlek',       _fmtSize(ver.info['file_size_bytes'])),
      _InfoRow('Container',     ver.info['container']?.toString()),
      _InfoRow('Video Codec',   v['codec']?.toString()),
      _InfoRow('Video Profile', v['profile']?.toString()),
    ];
  }

  List<_InfoRow> _dataRows(Map<String, dynamic> info) {
    final v = _vd(info);
    return [
      _InfoRow('Codec',               v['codec']?.toString()),
      _InfoRow('Bitrate',             _fmtKbps(v['bitrate_kbps'])),
      _InfoRow('Bit Depth',           v['bit_depth']?.toString()),
      _InfoRow('Chroma Subsampling',  v['chroma_subsampling']?.toString()),
      _InfoRow('Chroma Location',     v['chroma_location']?.toString()),
      _InfoRow('Coded Height',        v['coded_height']?.toString()),
      _InfoRow('Coded Width',         v['coded_width']?.toString()),
      _InfoRow('Frame Rate',          v['frame_rate'] != null ? '${v['frame_rate']} fps' : null),
      _InfoRow('Nivå',                v['level']?.toString()),
      _InfoRow('Width',               v['width']?.toString()),
      _InfoRow('Height',              v['height']?.toString()),
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
      'ita': 'Italienska', 'it': 'Italienska',
      'jpn': 'Japanska', 'ja': 'Japanska',
      'chi': 'Kinesiska', 'zh': 'Kinesiska',
      'kor': 'Koreanska', 'ko': 'Koreanska',
      'rus': 'Ryska',    'ru': 'Ryska',
      'ara': 'Arabiska', 'ar': 'Arabiska',
      'por': 'Portugisiska', 'pt': 'Portugisiska',
      'dut': 'Holländska', 'nl': 'Holländska',
    };
    return map[lang.toLowerCase()] ?? lang.toUpperCase();
  }
}

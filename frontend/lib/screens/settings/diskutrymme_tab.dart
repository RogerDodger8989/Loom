part of '../settings_screen.dart';

extension DiskutrymmeTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Diskutrymme
  // ─────────────────────────────────────────────

  Future<void> _loadDiskStats() async {
    setState(() { _isDiskStatsLoading = true; _diskStats = null; });
    try {
      final data = await widget.apiService.diskStats();
      if (mounted) setState(() { _diskStats = data; _isDiskStatsLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isDiskStatsLoading = false);
    }
  }

  Future<void> _runDiskScan() async {
    setState(() { _isDiskScanning = true; _diskScanError = null; _diskCleanResult = null; _diskCandidates = []; });
    try {
      final data = await widget.apiService.diskScan();
      if (!mounted) return;
      final raw = (data['candidates'] as List<dynamic>? ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map)..['_selected'] = true)
          .toList();
      setState(() {
        _diskCandidates = raw;
        _diskTotalCandidates = data['total_candidates'] as int? ?? 0;
        _diskTotalFreeableGb = (data['total_freeable_gb'] as num?)?.toDouble() ?? 0;
        _isDiskScanning = false;
      });
    } catch (e) {
      if (mounted) setState(() { _isDiskScanning = false; _diskScanError = e.toString(); });
    }
  }

  Future<void> _runDiskCleanup() async {
    final selected = _diskCandidates.where((c) => c['_selected'] == true).toList();
    if (selected.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        title: const Text('Bekräfta rensning', style: TextStyle(color: Colors.white)),
        content: Text(
          'Flytta ${selected.length} objekt till papperskorgen?\nDe märks som AUTO-RADERAT och kan återställas.',
          style: const TextStyle(color: Colors.white70),
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Radera markerade'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() { _isDiskCleaning = true; _diskCleanResult = null; });
    try {
      final ids = selected.map((c) => c['id'] as String).toList();
      final result = await widget.apiService.diskCleanup(ids: ids);
      if (!mounted) return;
      final count = result['deleted_count'] as int? ?? 0;
      setState(() {
        _isDiskCleaning = false;
        _diskCleanResult = '$count objekt flyttades till papperskorgen.';
        _diskCandidates = [];
        _diskTotalCandidates = 0;
        _diskTotalFreeableGb = 0;
      });
      widget.onLibraryChanged?.call();
    } catch (e) {
      if (mounted) setState(() { _isDiskCleaning = false; _diskScanError = e.toString(); });
    }
  }

  Widget _diskStatPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskRuleCard({
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    Widget? configChild,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? color.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enabled ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            secondary: Icon(icon, color: enabled ? color : Colors.white24, size: 20),
            title: Text(title, style: TextStyle(color: enabled ? Colors.white : Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            value: enabled,
            activeThumbColor: color,
            activeTrackColor: color.withValues(alpha: 0.25),
            onChanged: onToggle,
          ),
          if (enabled && configChild != null) ...[
            Divider(color: color.withValues(alpha: 0.12), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: configChild,
            ),
          ],
        ],
      ),
    );
  }

  Widget _diskNumberField(String label, TextEditingController ctrl, {String hint = ''}) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => _scheduleSave(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
            decoration: _inputDeco(hint),
          ),
        ),
      ],
    );
  }

  Widget _buildDiskCandidateRow(Map<String, dynamic> c) {
    final selected = c['_selected'] == true;
    final itemType = c['item_type'] as String? ?? 'movie';
    final sizeMb = (c['file_size_mb'] as num?)?.toInt() ?? 0;
    final sizeLabel = sizeMb >= 1024 ? '${(sizeMb / 1024).toStringAsFixed(1)} GB' : '$sizeMb MB';

    Color typeColor;
    String typeLabel;
    switch (itemType) {
      case 'episode': typeColor = Colors.blue; typeLabel = 'AVSNITT'; break;
      case 'season':  typeColor = Colors.orange; typeLabel = 'SÄSONG'; break;
      case 'show':    typeColor = Colors.purple; typeLabel = 'SERIE'; break;
      default:        typeColor = const Color(0xFF8A5BFF); typeLabel = 'FILM';
    }

    final title = itemType == 'episode'
        ? '${c['show_title']} · S${(c['season_number'] as int? ?? 0).toString().padLeft(2,'0')}E${(c['episode_number'] as int? ?? 0).toString().padLeft(2,'0')}'
        : itemType == 'season'
        ? '${c['show_title']} · Säsong ${c['season_number']}'
        : c['title'] as String? ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.02)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            activeColor: const Color(0xFF8A5BFF),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            onChanged: (v) => setState(() => c['_selected'] = v ?? false),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
            child: Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(sizeLabel, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(c['reason_details'] as String? ?? '', style: const TextStyle(color: Colors.white24, fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildDiskutrymme() {
    final selectedCount = _diskCandidates.where((c) => c['_selected'] == true).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Diskstatistik ─────────────────────────────
          _buildSection('Diskstatistik', Icons.storage_outlined, [
            if (_diskStats != null) ...[
              Row(children: [
                _diskStatPill('Totalt', '${_diskStats!['total_gb']} GB', Colors.white54),
                const SizedBox(width: 8),
                _diskStatPill('Filmer', '${_diskStats!['movies_gb']} GB', const Color(0xFF8A5BFF)),
                const SizedBox(width: 8),
                _diskStatPill('Serier', '${_diskStats!['shows_gb']} GB', Colors.orange),
              ]),
              const SizedBox(height: 8),
              Text(
                '${_diskStats!['movie_count']} filmer · ${_diskStats!['episode_count']} avsnitt',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 10),
            ],
            if (_isDiskStatsLoading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            ElevatedButton.icon(
              onPressed: _isDiskStatsLoading ? null : _loadDiskStats,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(_diskStats == null ? 'Hämta statistik' : 'Uppdatera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                foregroundColor: Colors.white70,
                elevation: 0,
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Regler ────────────────────────────────────
          _buildSection('Regler', Icons.rule_outlined, [
            Text(
              'Välj vilka regler som ska avgöra om en fil ska flyttas till papperskorgen. Reglerna kombineras med ELLER — en fil som träffar minst en aktiverad regel är kandidat. Allt är avstängt som standard.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
            ),
            const SizedBox(height: 14),

            _buildDiskRuleCard(
              enabled: _diskRuleWatchedEnabled,
              onToggle: (v) { setState(() => _diskRuleWatchedEnabled = v); _scheduleSave(); },
              title: 'Sedd',
              subtitle: 'Radera om sedd för mer än X dagar sedan.',
              icon: Icons.check_circle_outline,
              color: Colors.green,
              configChild: _diskNumberField('Dagar efter sedd', _diskWatchedDaysCtrl, hint: 'dagar'),
            ),
            const SizedBox(height: 10),

            _buildDiskRuleCard(
              enabled: _diskRuleUnseenEnabled,
              onToggle: (v) { setState(() => _diskRuleUnseenEnabled = v); _scheduleSave(); },
              title: 'Osedd',
              subtitle: 'Radera om aldrig sedd och tillagd för mer än X dagar sedan.',
              icon: Icons.visibility_off_outlined,
              color: Colors.orange,
              configChild: _diskNumberField('Dagar sedan tillagd', _diskUnseenDaysCtrl, hint: 'dagar'),
            ),
            const SizedBox(height: 10),

            _buildDiskRuleCard(
              enabled: _diskRuleInactiveEnabled,
              onToggle: (v) { setState(() => _diskRuleInactiveEnabled = v); _scheduleSave(); },
              title: 'Inaktiv',
              subtitle: 'Radera om inte spelad på X dagar (räknat från senaste aktivitet).',
              icon: Icons.timer_off_outlined,
              color: Colors.blue,
              configChild: _diskNumberField('Dagar utan aktivitet', _diskInactiveDaysCtrl, hint: 'dagar'),
            ),
            const SizedBox(height: 10),

            _buildDiskRuleCard(
              enabled: _diskRuleSizeEnabled,
              onToggle: (v) { setState(() => _diskRuleSizeEnabled = v); _scheduleSave(); },
              title: 'Filstorlek',
              subtitle: 'Radera filer som är större än X GB.',
              icon: Icons.folder_outlined,
              color: Colors.redAccent,
              configChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _diskNumberField('Storlek (GB)', _diskSizeGbCtrl, hint: 'GB'),
                  const SizedBox(height: 10),
                  _switchTile(
                    'Kräv att sedd',
                    'Radera bara stora filer som redan har setts.',
                    _diskRuleSizeRequireWatched,
                    (v) { setState(() => _diskRuleSizeRequireWatched = v); _scheduleSave(); },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            _buildDiskRuleCard(
              enabled: _diskRuleRatingEnabled,
              onToggle: (v) { setState(() => _diskRuleRatingEnabled = v); _scheduleSave(); },
              title: 'Lågt betyg',
              subtitle: 'Radera om eget betyg är lika med eller lägre än X (skala 0–10).',
              icon: Icons.star_border_outlined,
              color: Colors.amber,
              configChild: _diskNumberField('Max betyg', _diskRatingMaxCtrl, hint: '0–10'),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Seriehantering ────────────────────────────
          _buildSection('Seriehantering', Icons.tv_outlined, [
            Text('Hur ska TV-serier hanteras vid radering?', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
            const SizedBox(height: 12),
            _buildDropdown(
              'Raderingsenhet',
              _diskSeriesMode,
              ['episode', 'season', 'show'],
              (v) { if (v != null) { setState(() => _diskSeriesMode = v); _scheduleSave(); } },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Text(
                _diskSeriesMode == 'season'
                    ? 'Hela säsongen raderas när ALLA avsnitt i säsongen är sedda.'
                    : _diskSeriesMode == 'show'
                    ? 'Hela serien raderas när ALLA avsnitt i alla säsonger är sedda.'
                    : 'Varje avsnitt utvärderas individuellt — serier raderas aldrig i ett svep.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Skydd ─────────────────────────────────────
          _buildSection('Skydd', Icons.shield_outlined, [
            _switchTile(
              'Skydda favoriter',
              'Titlar markerade som favorit raderas aldrig automatiskt.',
              _diskProtectFavorites,
              (v) { setState(() => _diskProtectFavorites = v); _scheduleSave(); },
            ),
          ]),

          const SizedBox(height: 16),

          // ── Dry-run & Rensning ─────────────────────────
          _buildSection('Dry-run & Rensning', Icons.cleaning_services_outlined, [
            Text(
              'Kör en genomsökning utan att radera något (dry-run), granska listan och radera sedan det du vill.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isDiskScanning ? null : _runDiskScan,
                  icon: _isDiskScanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search, size: 16),
                  label: Text(_isDiskScanning ? 'Skannar...' : 'Kör dry-run'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_isDiskCleaning || selectedCount == 0) ? null : _runDiskCleanup,
                  icon: _isDiskCleaning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: Text(_isDiskCleaning ? 'Rensar...' : 'Radera markerade ($selectedCount)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.14),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ]),

            if (_diskScanError != null) ...[
              const SizedBox(height: 10),
              Text(_diskScanError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],

            if (_diskCleanResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.15)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text(_diskCleanResult!, style: const TextStyle(color: Colors.green, fontSize: 13)),
                ]),
              ),
            ],

            if (_diskCandidates.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_diskTotalCandidates kandidater · ${_diskTotalFreeableGb.toStringAsFixed(2)} GB kan frigöras',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: () {
                      final allSelected = _diskCandidates.every((c) => c['_selected'] == true);
                      setState(() {
                        for (final c in _diskCandidates) { c['_selected'] = !allSelected; }
                      });
                    },
                    child: Text(
                      _diskCandidates.every((c) => c['_selected'] == true) ? 'Avmarkera alla' : 'Markera alla',
                      style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ..._diskCandidates.map(_buildDiskCandidateRow),
            ] else if (!_isDiskScanning && _diskTotalCandidates == 0 && _diskCleanResult == null) ...[
              const SizedBox(height: 10),
              Text(
                'Inga kandidater ännu. Aktivera regler och kör dry-run för att se vad som matchar.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
              ),
            ],
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: const Color(0xFF8A5BFF), size: 20),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const Divider(color: Colors.white10, height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    String? hint,
    VoidCallback? onSave,   // override save callback; defaults to _scheduleSave
    bool noAutoSave = false, // set true for fields that must NOT auto-save (e.g. password confirm)
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          onChanged: noAutoSave ? null : (_) => onSave != null ? onSave() : _scheduleSave(),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          contextMenuBuilder: (ctx, state) =>
              AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
          decoration: _inputDeco(hint ?? ''),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options, ValueChanged<String?> onChange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: const Color(0xFF15102A),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              isExpanded: true,
              items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: onChange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOAuthRow({required String label, required bool isConnected, required Color color, required VoidCallback onTap}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(isConnected ? Icons.check_circle : Icons.link, color: isConnected ? Colors.green : color, size: 18),
            const SizedBox(width: 8),
            Text(isConnected ? '$label är kopplad' : 'Koppla till $label',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isConnected ? Colors.white12 : color,
              foregroundColor: isConnected ? Colors.white70 : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              elevation: isConnected ? 0 : 2,
            ),
            onPressed: onTap,
            icon: Icon(isConnected ? Icons.link_off : Icons.login, size: 14),
            label: Text(isConnected ? 'Koppla från' : 'Anslut nu',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _syncOptions(String platform, Color color, bool ratings, bool watched,
      ValueChanged<bool> onRatings, ValueChanged<bool> onWatched) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Synkronisera betyg', style: TextStyle(color: Colors.white, fontSize: 13)),
            value: ratings,
            activeColor: color,
            onChanged: onRatings,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Synkronisera sedda', style: TextStyle(color: Colors.white, fontSize: 13)),
            value: watched,
            activeColor: color,
            onChanged: onWatched,
          ),
        ],
      ),
    );
  }

  Widget _switchTile(String title, String subtitle, bool value, ValueChanged<bool> onChange) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
        value: value,
        activeThumbColor: const Color(0xFF8A5BFF),
        activeTrackColor: const Color(0xFF8A5BFF).withValues(alpha: 0.25),
        onChanged: onChange,
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.3),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white24),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF8A5BFF), width: 1.5)),
  );

  Widget _browseButton({required bool browsing, required VoidCallback onTap}) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.04),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        onPressed: browsing ? null : onTap,
        icon: browsing
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
            : const Icon(Icons.folder_open_outlined, color: Color(0xFFB593FF)),
        label: const Text('Bläddra...'),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Toast widget (moved from dashboard)
// ─────────────────────────────────────────────
class _ToastWidget extends StatefulWidget {
  final String title;
  final String message;
  final bool isSuccess;
  final VoidCallback onDismiss;

  const _ToastWidget({required this.title, required this.message, required this.isSuccess, required this.onDismiss});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fade, _slide;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 40, end: 0).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _ac.forward();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _ac.reverse().then((_) => widget.onDismiss());
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      right: 24,
      child: AnimatedBuilder(
        animation: _ac,
        builder: (_, child) => Opacity(
          opacity: _fade.value,
          child: Transform.translate(offset: Offset(_slide.value, 0), child: child),
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF15102A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isSuccess ? Colors.green.withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20)],
            ),
            child: Row(
              children: [
                Icon(widget.isSuccess ? Icons.check_circle : Icons.error_outline,
                    color: widget.isSuccess ? Colors.green : Colors.redAccent, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(widget.message, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
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

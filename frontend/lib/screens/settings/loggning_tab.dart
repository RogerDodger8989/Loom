part of '../settings_screen.dart';

extension LoggningTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Loggning
  // ─────────────────────────────────────────────
  Widget _buildLoggning() {
    final levels = ['Alla', 'info', 'warn', 'error'];
    final filtered = _logLevelFilter == 'Alla'
        ? _logEntries
        : _logEntries.where((e) => e['level'] == _logLevelFilter).toList();

    return Column(
      children: [
        // ── Toolbar ────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.01),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              // Level filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _logLevelFilter,
                    dropdownColor: const Color(0xFF15102A),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: levels.map((l) => DropdownMenuItem(
                      value: l,
                      child: Text(l == 'Alla' ? 'Alla nivåer' : l.toUpperCase()),
                    )).toList(),
                    onChanged: (v) => setState(() => _logLevelFilter = v ?? 'Alla'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Pause toggle
              GestureDetector(
                onTap: () => setState(() => _logPaused = !_logPaused),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _logPaused
                        ? Colors.orangeAccent.withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _logPaused
                          ? Colors.orangeAccent.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _logPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 14,
                      color: _logPaused ? Colors.orangeAccent : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _logPaused ? 'Pausad' : 'Pausa',
                      style: TextStyle(
                        fontSize: 12,
                        color: _logPaused ? Colors.orangeAccent : Colors.white38,
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              // Auto-scroll toggle
              GestureDetector(
                onTap: () => setState(() => _logAutoScroll = !_logAutoScroll),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _logAutoScroll
                        ? const Color(0xFF8A5BFF).withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _logAutoScroll
                          ? const Color(0xFF8A5BFF).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.vertical_align_bottom,
                        size: 14,
                        color: _logAutoScroll ? const Color(0xFFB593FF) : Colors.white38),
                    const SizedBox(width: 6),
                    Text('Auto-scroll',
                        style: TextStyle(
                          fontSize: 12,
                          color: _logAutoScroll ? const Color(0xFFB593FF) : Colors.white38,
                        )),
                  ]),
                ),
              ),
              const Spacer(),
              // Entry count
              Text('${filtered.length} rader',
                  style: const TextStyle(color: Colors.white24, fontSize: 12)),
              const SizedBox(width: 16),
              // Clear
              TextButton.icon(
                onPressed: _clearLogs,
                icon: const Icon(Icons.clear_all, size: 16, color: Colors.white38),
                label: const Text('Rensa', style: TextStyle(color: Colors.white38, fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const SizedBox(width: 8),
              // Download
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFFB593FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  elevation: 0,
                ),
                onPressed: _downloadLogs,
                icon: const Icon(Icons.download_outlined, size: 15),
                label: const Text('Ladda ner', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        // ── Log view ───────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.terminal_outlined, size: 40, color: Colors.white12),
                      const SizedBox(height: 12),
                      Text(
                        _logPollTimer != null ? 'Väntar på loggposter...' : 'Inga loggar',
                        style: const TextStyle(color: Colors.white24, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : SelectionArea(
                  child: ListView.builder(
                    controller: _logScrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _buildLogLine(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLogLine(Map<String, dynamic> entry) {
    final level = (entry['level'] as String?) ?? 'info';
    final msg = (entry['msg'] as String?) ?? '';
    final time = entry['time'] is int
        ? DateTime.fromMillisecondsSinceEpoch(entry['time'] as int)
        : DateTime.now();
    final timeStr = '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}:${time.second.toString().padLeft(2,'0')}';

    final Color levelColor;
    final Color bgColor;
    switch (level) {
      case 'error':
        levelColor = Colors.redAccent;
        bgColor = Colors.redAccent.withValues(alpha: 0.04);
      case 'warn':
        levelColor = Colors.orangeAccent;
        bgColor = Colors.orangeAccent.withValues(alpha: 0.03);
      case 'debug':
        levelColor = Colors.blueAccent;
        bgColor = Colors.transparent;
      default:
        levelColor = Colors.white38;
        bgColor = Colors.transparent;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timeStr,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Container(
            width: 38,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              level.toUpperCase(),
              style: TextStyle(color: levelColor, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: level == 'error' ? Colors.redAccent.withValues(alpha: 0.9) : Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

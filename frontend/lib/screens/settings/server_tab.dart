part of '../settings_screen.dart';

extension ServerTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Server
  // ─────────────────────────────────────────────
  Future<void> _loadServerInfo() async {
    try {
      final info = await widget.apiService.fetchServerInfo();
      if (mounted) setState(() => _serverInfo = info);
    } catch (_) {}
  }

  Future<void> _optimizeDb() async {
    setState(() { _isOptimizing = true; _optimizeResult = null; });
    try {
      final res = await widget.apiService.optimizeDatabase();
      if (!mounted) return;
      setState(() {
        _optimizeResult = res['success'] == true;
        if (_optimizeResult == true) _loadServerInfo();
      });
    } catch (e) {
      if (mounted) setState(() => _optimizeResult = false);
    } finally {
      if (mounted) setState(() => _isOptimizing = false);
    }
  }

  Future<void> _downloadLogs() async {
    try {
      final bytes = await widget.apiService.downloadLogsBytes();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Spara loggfil',
        fileName: 'loom-logs-$date.txt',
        type: FileType.any,
      );
      if (savePath == null) return;
      await File(savePath).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logg sparad: $savePath'), backgroundColor: const Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export misslyckades: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadBackup() async {
    try {
      final bytes = await widget.apiService.downloadBackupBytes();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Spara backup',
        fileName: 'loom-backup-$date.db',
        type: FileType.any,
      );
      if (savePath == null) return;
      await File(savePath).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup sparad: $savePath'), backgroundColor: const Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup misslyckades: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _restoreDb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final bytes = result.files.single.bytes!;
    final name = result.files.single.name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text('Bekräfta återställning', style: TextStyle(color: Colors.white)),
        content: Text(
          'Den nuvarande databasen ersätts med "$name".\nServern startas om automatiskt.\n\nÄr du säker?',
          style: const TextStyle(color: Colors.white70, height: 1.5),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Återställ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRestoring = true);
    try {
      final res = await widget.apiService.restoreDatabase(bytes, name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message'] ?? 'Återställning pågår...'),
        backgroundColor: const Color(0xFF8A5BFF),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'), backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _confirmRestartServer() async {
    final callerPayload = widget.apiService.currentUserPayload;
    if (callerPayload?['role'] != 'Admin') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text('Starta om servern?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Servern stängs av och startas om. Pågående uppspelningar avbryts.',
          style: TextStyle(color: Colors.white70, height: 1.5),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent.withValues(alpha: 0.85),
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Starta om', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRestarting = true);
    try {
      await widget.apiService.restartServer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Servern startas om...'),
        backgroundColor: Colors.orangeAccent,
        duration: Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isRestarting = false);
    }
  }

  Widget _buildServer() {
    if (_serverInfo == null) Future.microtask(_loadServerInfo);
    final info = _serverInfo;
    final isAdmin = widget.apiService.currentUserPayload?['role'] == 'Admin';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Servernamn ────────────────────────
          _buildSection('Server', Icons.dns_outlined, [
            _buildField('Servernamn', _serverNameCtrl),
            const SizedBox(height: 8),
            if (info != null)
              Text('Port: ${info['port']}  •  Platform: ${info['platform']}  •  Node ${info['nodeVersion']}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            const SizedBox(height: 14),
            // Clock toggle
            Row(children: [
              const Icon(Icons.access_time_outlined, size: 16, color: Colors.white38),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Visa klocka', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                  Text('Klockan visas i sidomenyn, till höger om navigeringspilarna.',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ),
              Switch(
                value: _showClock,
                activeColor: const Color(0xFF8A5BFF),
                onChanged: (v) {
                  setState(() => _showClock = v);
                  // Spara direkt (ingen debounce) — annars hinner inte inställningen sparas
                  widget.apiService.updateSettings({'SHOW_CLOCK': v ? 'true' : 'false'}).catchError((_) {});
                },
              ),
            ]),
            if (isAdmin) ...[
              const SizedBox(height: 14),
              const Divider(color: Colors.white12),
              const SizedBox(height: 14),
              // Restart button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent.withValues(alpha: 0.10),
                    foregroundColor: Colors.orangeAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.35)),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _isRestarting ? null : _confirmRestartServer,
                  icon: _isRestarting
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.orangeAccent)))
                      : const Icon(Icons.restart_alt_rounded, size: 18),
                  label: Text(_isRestarting ? 'Startar om...' : 'Starta om servern',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          // ── Databasinformation ────────────────
          _buildSection('Databas', Icons.storage_outlined, [
            if (info == null)
              Center(child: TextButton.icon(
                onPressed: _loadServerInfo,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Hämta info'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFB593FF)),
              ))
            else ...[
              _infoRow(Icons.folder_outlined, 'Databasstorlek', _formatBytes(info['dbSizeBytes'] as int)),
              _infoRow(Icons.movie_outlined, 'Medieföremål', '${info['mediaCount']} titlar, ${info['episodeCount']} avsnitt'),
              _infoRow(Icons.people_outline, 'Användare', '${info['userCount']} st'),
              _infoRow(Icons.timer_outlined, 'Upptime', _formatUptime(info['uptimeSeconds'] as int)),
            ],
            const SizedBox(height: 14),
            // Optimize
            Row(children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFFB593FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3))),
                  elevation: 0,
                ),
                onPressed: _isOptimizing ? null : _optimizeDb,
                icon: _isOptimizing
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFB593FF))))
                    : const Icon(Icons.auto_fix_high_outlined, size: 16),
                label: const Text('Optimera databas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (_optimizeResult != null) ...[
                const SizedBox(width: 12),
                Icon(_optimizeResult! ? Icons.check_circle : Icons.error_outline,
                    color: _optimizeResult! ? Colors.greenAccent : Colors.redAccent, size: 18),
                const SizedBox(width: 6),
                Text(_optimizeResult! ? 'Klar!' : 'Misslyckades',
                    style: TextStyle(color: _optimizeResult! ? Colors.greenAccent : Colors.redAccent, fontSize: 13)),
              ],
            ]),
          ]),
          const SizedBox(height: 16),
          // ── Backup & Återställning ─────────────
          _buildSection('Backup & Återställning', Icons.backup_outlined, [
            Text('Backup laddar ned hela databasen som en .db-fil. '
                'Återställning ersätter databasen och startar om servern.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5)),
            const SizedBox(height: 16),
            Row(children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.withValues(alpha: 0.12),
                  foregroundColor: Colors.tealAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.teal.withValues(alpha: 0.3))),
                  elevation: 0,
                ),
                onPressed: _downloadBackup,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Ladda ned backup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                  foregroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3))),
                  elevation: 0,
                ),
                onPressed: _isRestoring ? null : _restoreDb,
                icon: _isRestoring
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.redAccent)))
                    : const Icon(Icons.restore_outlined, size: 16),
                label: const Text('Återställ från backup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          // ── Exportera / Importera inställningar ───
          _buildSection('Exportera / Importera inställningar', Icons.swap_vert_outlined, [
            Text('Välj vad du vill inkludera i ZIP-filen. Inställningar och biblioteksvägar är valda som standard.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _expChip('Inställningar', _expSettings, (v) => setState(() => _expSettings = v)),
              _expChip('Biblioteksvägar', _expLibraryPaths, (v) => setState(() => _expLibraryPaths = v)),
              _expChip('Användare', _expUsers, (v) => setState(() => _expUsers = v)),
              _expChip('Spelhistorik', _expWatchHistory, (v) => setState(() => _expWatchHistory = v)),
              _expChip('Bevakningslista', _expWatchlist, (v) => setState(() => _expWatchlist = v)),
              _expChip('Markörer', _expMarkers, (v) => setState(() => _expMarkers = v)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFFB593FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.35))),
                  elevation: 0,
                ),
                onPressed: (_isExporting || (!_expSettings && !_expLibraryPaths && !_expUsers && !_expWatchHistory && !_expWatchlist && !_expMarkers))
                    ? null : _doExport,
                icon: _isExporting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFB593FF))))
                    : const Icon(Icons.download_outlined, size: 16),
                label: const Text('Exportera ZIP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                  foregroundColor: Colors.orangeAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.orange.withValues(alpha: 0.3))),
                  elevation: 0,
                ),
                onPressed: _isImporting ? null : _doImport,
                icon: _isImporting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.orangeAccent)))
                    : const Icon(Icons.upload_outlined, size: 16),
                label: const Text('Importera ZIP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ]),
            if (_importResult != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Import slutförd:', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...(_importResult!['results'] as Map<String, dynamic>).entries.map((e) =>
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('• ${e.value}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          _buildExportSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _expChip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: value ? Colors.white : Colors.white54,
      )),
      selected: value,
      onSelected: onChanged,
      selectedColor: const Color(0xFF8A5BFF).withValues(alpha: 0.25),
      backgroundColor: Colors.white.withValues(alpha: 0.04),
      checkmarkColor: const Color(0xFFB593FF),
      side: BorderSide(color: value
          ? const Color(0xFF8A5BFF).withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: true,
    );
  }

  Future<void> _doExport() async {
    setState(() { _isExporting = true; });
    try {
      final bytes = await widget.apiService.exportBackup(
        settings: _expSettings,
        libraryPaths: _expLibraryPaths,
        users: _expUsers,
        watchHistory: _expWatchHistory,
        watchlist: _expWatchlist,
        markers: _expMarkers,
      );
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final filename = 'loom_backup_$date.zip';
      if (kIsWeb) {
        final blob = html.Blob([Uint8List.fromList(bytes)], 'application/zip');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Spara backup-ZIP',
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        if (savePath != null) {
          await File(savePath).writeAsBytes(bytes);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup sparad: $savePath'), backgroundColor: const Color(0xFF8A5BFF)),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export misslyckades: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _doImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Välj backup-ZIP',
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() { _isImporting = true; _importResult = null; });
    try {
      final res = await widget.apiService.importBackup(bytes, file.name);
      if (mounted) setState(() => _importResult = res);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import misslyckades: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: const Color(0xFF8A5BFF)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatUptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

}

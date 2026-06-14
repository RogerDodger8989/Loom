part of '../settings_screen.dart';

extension BibliotekTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Bibliotek
  // ─────────────────────────────────────────────
  Widget _buildBibliotek() {
    return DefaultTabController(
      length: 3,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Sub-tab bar
                Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.01),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: TabBar(
                    indicatorColor: const Color(0xFF8A5BFF),
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white38,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                    ),
                    tabs: const [
                      Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.movie_outlined, size: 16), SizedBox(width: 6), Text('Filmer')])),
                      Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.tv_outlined, size: 16), SizedBox(width: 6), Text('TV-Serier')])),
                      Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.music_note_outlined, size: 16), SizedBox(width: 6), Text('Musik')])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        body: TabBarView(children: [
          _buildScannerSubTab('Movie'),
          _buildScannerSubTab('Show'),
          _buildScannerSubTab('Music'),
        ]),
      ),
    );
  }

  Widget _buildScannerSubTab(String type) {
    final paths = _libraryPaths.where((p) => p['type'] == type).toList();
    final typeLabel = type == 'Show' ? 'TV-seriemappar' : type == 'Movie' ? 'filmmappar' : 'musikmappar';
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Konfigurerade $typeLabel',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isScanning)
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))))
              else if (paths.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _triggerScanAllPaths(paths),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Skanna alla'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (paths.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.01),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Text('Inga mappar tillagda för $typeLabel.',
                  style: const TextStyle(color: Colors.white24)),
            )
          else
            ...paths.map((p) => _buildFolderListItem(p)),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          Text(
            'Lägg till ${type == 'Show' ? 'TV-seriemapp' : type == 'Movie' ? 'filmmapp' : 'musikmapp'}',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildAddFolderForm(type),
          const SizedBox(height: 24),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          _buildScanFilterSection(),
          if (type != 'Music') ...[
            const SizedBox(height: 24),
            _buildSection('Metadata', Icons.translate_outlined, [
              Row(children: [
                Expanded(child: _buildDropdown('Metadataspråk', _metadataLanguage, ['sv-SE', 'en-US', 'no-NO'], (v) { setState(() => _metadataLanguage = v!); _scheduleSave(); })),
                const SizedBox(width: 16),
                Expanded(child: _buildDropdown('Fallback-språk', _fallbackLanguage, ['sv-SE', 'en-US', 'no-NO'], (v) { setState(() => _fallbackLanguage = v!); _scheduleSave(); })),
                const SizedBox(width: 16),
                Expanded(child: _buildDropdown('JustWatch-region', _watchProviderRegion, ['SE', 'US', 'NO', 'GB'], (v) { setState(() => _watchProviderRegion = v!); _scheduleSave(); })),
                const SizedBox(width: 16),
                Expanded(child: _buildDropdown('Titeldisplay', _titleDisplayStyle, ['Translated', 'Original'], (v) { setState(() => _titleDisplayStyle = v!); _scheduleSave(); })),
              ]),
              const SizedBox(height: 12),
              _switchTile('Föredra lokal NFO-metadata', 'Använd .nfo-filer framför online-metadata.', _preferLocalNfo, _setPreferLocalNfo),
              _switchTile('Visa utgåva/version i titel', 'T.ex. visar "[Director\'s Cut]" efter titeln.', _showReleaseVersion, (v) { setState(() => _showReleaseVersion = v); _scheduleSave(); }),
            ]),
          ],
          if (type == 'Music') ...[
            const SizedBox(height: 24),
            _buildSection('Allmänt & Språk', Icons.language, [
              Row(children: [
                Expanded(child: _buildDropdown('Metadataspråk', _metadataLanguage, ['sv-SE', 'en-US', 'no-NO'], (v) { setState(() => _metadataLanguage = v!); _scheduleSave(); })),
                const SizedBox(width: 16),
                Expanded(child: _buildDropdown('Fallback-språk', _fallbackLanguage, ['sv-SE', 'en-US', 'no-NO'], (v) { setState(() => _fallbackLanguage = v!); _scheduleSave(); })),
                const SizedBox(width: 16),
                Expanded(child: _buildDropdown('Titeldisplay', _titleDisplayStyle, ['Translated', 'Original'], (v) { setState(() => _titleDisplayStyle = v!); _scheduleSave(); })),
              ]),
            ]),
            const SizedBox(height: 16),
            _buildSection('Skanning & Lokala taggar', Icons.tag, [
              _switchTile('Föredra inbäddade taggar', 'Föredra ID3/Vorbis/FLAC-taggar inuti filerna framför online-metadata.', _preferLocalNfo, (v) { setState(() => _preferLocalNfo = v); _scheduleSave(); }),
              _switchTile('Visa utgåva/version i titel', 'T.ex. visar "[Remastered]" efter titeln om det anges.', _showReleaseVersion, (v) { setState(() => _showReleaseVersion = v); _scheduleSave(); }),
              _switchTile('Länka soundtracks', 'Automatiskt länka soundtracks till filmbiblioteket om de matchar i titel/ID.', _linkSoundtracksAutomatically, (v) { setState(() => _linkSoundtracksAutomatically = v); _scheduleSave(); }),
            ]),
            const SizedBox(height: 16),
            _buildSection('Online-leverantörer', Icons.cloud_outlined, [
              _switchTile('Använd MusicBrainz för spårmatchning', 'Används för att finna korrekt metadata online.', _useMusicBrainz, (v) { setState(() => _useMusicBrainz = v); _scheduleSave(); }),
              _switchTile('Läs MusicBrainz-taggar', 'Använd om inbäddade MusicBrainz-ID:n redan finns i filerna.', _readMusicBrainzTags, (v) { setState(() => _readMusicBrainzTags = v); _scheduleSave(); }),
              _switchTile('Aktivera AcoustID-fingeravtryck', 'Skanna ljudfilernas fingeravtryck om metadata saknas helt.', _enableAcoustId, (v) { setState(() => _enableAcoustId = v); _scheduleSave(); }),
              _switchTile('Hämta fördjupad trivia från Wikidata', 'Kan innefatta artistfakta eller albumrecensioner.', _fetchWikidataTrivia, (v) { setState(() => _fetchWikidataTrivia = v); _scheduleSave(); }),
              _switchTile('Hämta grafik från Fanart.tv & TheAudioDB', 'Hämtar högupplösta bakgrunder och logotyper.', _fetchFanartAndAudioDb, (v) { setState(() => _fetchFanartAndAudioDb = v); _scheduleSave(); }),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildScanFilterSection() {
    return _buildSection('Skanningfilter', Icons.filter_list, [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hoppa över ord i filnamn',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _scanSkipWordsCtrl,
            onChanged: (_) => _scheduleSave(),
            style: const TextStyle(color: Colors.white),
            contextMenuBuilder: (ctx, state) =>
                AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
            decoration: InputDecoration(
              hintText: 'commentary, extras, trailer, sample...',
              hintStyle: TextStyle(color: Colors.white24),
              fillColor: Colors.white.withValues(alpha: 0.04),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              helperText: 'Kommaseparerade ord. Filer vars namn innehåller dessa hoppar över.',
              helperStyle: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Minsta filstorlek (MB)',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _scanMinSizeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _scheduleSave(),
                      style: const TextStyle(color: Colors.white),
                      contextMenuBuilder: (ctx, state) =>
                          AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: Colors.white24),
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        helperText: '0 = ingen begränsning',
                        helperStyle: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: const SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    ]);
  }

  Widget _buildExportSection() {
    return _buildSection('Exportera data', Icons.download_outlined, [
      Text(
        'Exportera din sedda-status och betyg från hela biblioteket.',
        style: TextStyle(color: Colors.white54, fontSize: 13),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            icon: const Icon(Icons.data_object, size: 18),
            label: const Text('Exportera JSON'),
            onPressed: () => _doWatchedExport('json'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('Exportera CSV'),
            onPressed: () => _doWatchedExport('csv'),
          ),
        ],
      ),
    ]);
  }

  Future<void> _doWatchedExport(String format) async {
    try {
      final bytes = await widget.apiService.exportWatched(format: format);
      final ext = format == 'csv' ? 'csv' : 'json';
      final filename = 'loom-export-${DateTime.now().toIso8601String().substring(0, 10)}.$ext';

      if (kIsWeb) {
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Spara export',
          fileName: filename,
          type: FileType.any,
        );
        if (savePath == null) return;
        await File(savePath).writeAsBytes(bytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export sparad: $savePath'),
          backgroundColor: Colors.greenAccent.shade700,
        ));
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Export nedladdad!'),
        backgroundColor: Colors.greenAccent,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export misslyckades: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Widget _buildFolderListItem(dynamic p) {
    final isThisScanning = _isScanning && (_currentlyScanningPath == p['path'] || _currentlyScanningPath == null);
    final mediaCount = (p['media_count'] as int?) ?? 0;
    final watchEnabled = (p['watch_for_changes'] == 1 || p['watch_for_changes'] == true);
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, color: const Color(0xFFB593FF).withValues(alpha: 0.8), size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['path'], style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8A5BFF).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$mediaCount ${p['type'] == 'Movie' ? 'filmer' : p['type'] == 'Show' ? 'avsnitt' : 'låtar'}',
                                style: const TextStyle(color: Color(0xFFB593FF), fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () async {
                                final newVal = !watchEnabled;
                                try {
                                  await widget.apiService.toggleWatchPath(p['id'] as String, newVal);
                                  setState(() {
                                    p['watch_for_changes'] = newVal ? 1 : 0;
                                  });
                                } catch (_) {}
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    watchEnabled ? Icons.remove_red_eye : Icons.visibility_off_outlined,
                                    size: 14,
                                    color: watchEnabled ? Colors.greenAccent : Colors.white38,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Bevaka',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: watchEnabled ? Colors.greenAccent : Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showEditPathDialog(p),
                    icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                    tooltip: 'Redigera',
                  ),
                  IconButton(
                    onPressed: _isScanning ? null : () => _triggerScanOfSpecificPath(p['path'], p['type']),
                    icon: const Icon(Icons.sync_outlined, color: Colors.greenAccent, size: 20),
                    tooltip: 'Skanna nu',
                  ),
                  IconButton(
                    onPressed: () => _deletePath(p['id']),
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    tooltip: 'Ta bort',
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isThisScanning && _isScanning) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8A5BFF)),
                minHeight: 3,
              ),
            ),
          ),
          if (_scanLog.isNotEmpty) _buildScanLogPanel(),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildScanLogPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.all(10),
      height: 160,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListView.builder(
        reverse: true,
        itemCount: _scanLog.length,
        itemBuilder: (context, i) {
          final event = _scanLog[_scanLog.length - 1 - i];
          final type = event['type'] as String? ?? '';
          Color color;
          IconData icon;
          switch (type) {
            case 'item_added': color = Colors.greenAccent; icon = Icons.add_circle_outline; break;
            case 'item_updated': color = Colors.blueAccent; icon = Icons.update; break;
            case 'item_skipped': color = Colors.white38; icon = Icons.skip_next; break;
            case 'scan_start': color = const Color(0xFF8A5BFF); icon = Icons.play_arrow; break;
            case 'scan_complete': color = Colors.greenAccent; icon = Icons.check_circle_outline; break;
            case 'scan_error': color = Colors.redAccent; icon = Icons.error_outline; break;
            default: color = Colors.white54; icon = Icons.info_outline;
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event['message'] as String? ?? '',
                    style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddFolderForm(String type) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  contextMenuBuilder: (ctx, state) =>
                      AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                  decoration: _inputDeco('Ange sökväg eller klicka Bläddra...'),
                ),
              ),
              const SizedBox(width: 12),
              _browseButton(browsing: _isBrowsingDirectory, onTap: _selectFolderNatively),
            ],
          ),
          const SizedBox(height: 12),
          _switchTile('Föredra lokal NFO-metadata',
              'Importera från .nfo-filer istället för online.',
              _preferLocalNfo, _setPreferLocalNfo),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final folder = _pathCtrl.text.trim();
                if (folder.isNotEmpty) {
                  _addNewPath(folder, type);
                  _pathCtrl.clear();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Välj eller ange en mappsökväg')),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: Text(
                'Lägg till ${type == 'Show' ? 'TV-seriemapp' : type == 'Movie' ? 'filmmapp' : 'musikmapp'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

part of '../settings_screen.dart';

extension KallorTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Källor & Integrationer
  // ─────────────────────────────────────────────
  Widget _buildKallor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildAutoSaveIndicator(),
              const SizedBox(width: 12),
              if (_isManualSyncing) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF00E676)))),
                      const SizedBox(width: 8),
                      Text('${(_manualSyncProgress * 100).toInt()}% — $_manualSyncStep',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    foregroundColor: const Color(0xFF00E676),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.4))),
                  ),
                  onPressed: _startManualSync,
                  icon: const Icon(Icons.sync, color: Color(0xFF00E676)),
                  label: const Text('Synkronisera nu', style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          _buildSection('TMDB', Icons.movie_outlined, [
            _buildField('TMDB API-nyckel', _tmdbKeyCtrl, obscure: true),
            const SizedBox(height: 12),
            _buildField('TMDB User Auth', _tmdbAuthCtrl, obscure: true),
          ]),
          const SizedBox(height: 16),
          _buildSection('OMDb', Icons.star_outlined, [
            _buildField('OMDb API-nyckel', _omdbKeyCtrl, obscure: true),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _openUrl('https://www.omdbapi.com/apikey.aspx'),
              child: const Text('Skaffa en gratis OMDb API-nyckel här',
                  style: TextStyle(color: Colors.white38, fontSize: 11, decoration: TextDecoration.underline)),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection('Simkl', Icons.link_outlined, [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Simkl Integration', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => _openUrl('https://simkl.com/settings/developer/'),
                  icon: const Icon(Icons.open_in_new, size: 12, color: Colors.green),
                  label: const Text('Skapa Simkl App', style: TextStyle(color: Colors.green, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildField('Simkl Client ID', _simklKeyCtrl, obscure: true),
            const SizedBox(height: 10),
            _buildField('Simkl Client Secret', _simklSecretCtrl, obscure: true),
            const SizedBox(height: 6),
            Text('Redirect URI: http://localhost:8080/api/oauth/simkl/callback',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            const SizedBox(height: 12),
            _buildOAuthRow(
              label: 'Simkl',
              isConnected: _simklTokenCtrl.text.isNotEmpty,
              color: Colors.green,
              onTap: () async {
                if (_simklTokenCtrl.text.isNotEmpty) {
                  setState(() => _simklTokenCtrl.clear());
                  await _saveSettings();
                } else {
                  await _saveSettings();
                  await _openUrl('${widget.apiService.baseUrl}/api/oauth/simkl/authorize');
                  Timer.periodic(const Duration(seconds: 2), (timer) async {
                    if (timer.tick > 30) { timer.cancel(); return; }
                    final s = await widget.apiService.getSettings();
                    if ((s['SIMKL_ACCESS_TOKEN'] ?? '').toString().isNotEmpty) {
                      setState(() => _simklTokenCtrl.text = s['SIMKL_ACCESS_TOKEN']);
                      timer.cancel();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Simkl ansluten! ✅'), backgroundColor: Colors.green),
                      );
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            _buildField('Simkl Access Token', _simklTokenCtrl, obscure: true),
            if (_simklTokenCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              _syncOptions('Simkl', Colors.green, _syncSimklRatings, _syncSimklWatched,
                  (v) { setState(() => _syncSimklRatings = v); _scheduleSave(); },
                  (v) { setState(() => _syncSimklWatched = v); _scheduleSave(); }),
            ],
          ]),
          const SizedBox(height: 16),
          _buildSection('Trakt.tv', Icons.movie_filter_outlined, [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Trakt.tv Integration', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => _openUrl('https://trakt.tv/oauth/applications'),
                  icon: const Icon(Icons.open_in_new, size: 12, color: Colors.redAccent),
                  label: const Text('Skapa Trakt App', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildField('Trakt API Key (Client ID)', _traktKeyCtrl, obscure: true),
            const SizedBox(height: 10),
            _buildField('Trakt Client Secret', _traktSecretCtrl, obscure: true),
            const SizedBox(height: 6),
            Text('Redirect URI: http://localhost:8080/api/oauth/trakt/callback',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            const SizedBox(height: 12),
            _buildOAuthRow(
              label: 'Trakt.tv',
              isConnected: _traktTokenCtrl.text.isNotEmpty,
              color: Colors.redAccent,
              onTap: () async {
                if (_traktTokenCtrl.text.isNotEmpty) {
                  setState(() => _traktTokenCtrl.clear());
                  await _saveSettings();
                } else {
                  await _saveSettings();
                  await _openUrl('${widget.apiService.baseUrl}/api/oauth/trakt/authorize');
                  Timer.periodic(const Duration(seconds: 2), (timer) async {
                    if (timer.tick > 30) { timer.cancel(); return; }
                    final s = await widget.apiService.getSettings();
                    if ((s['TRAKT_ACCESS_TOKEN'] ?? '').toString().isNotEmpty) {
                      setState(() => _traktTokenCtrl.text = s['TRAKT_ACCESS_TOKEN']);
                      timer.cancel();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Trakt.tv ansluten! ✅'), backgroundColor: Colors.green),
                      );
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            _buildField('Trakt Access Token', _traktTokenCtrl, obscure: true),
            if (_traktTokenCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              _syncOptions('Trakt.tv', Colors.redAccent, _syncTraktRatings, _syncTraktWatched,
                  (v) { setState(() => _syncTraktRatings = v); _scheduleSave(); },
                  (v) { setState(() => _syncTraktWatched = v); _scheduleSave(); }),
            ],
          ]),
          const SizedBox(height: 16),
          // ── IMDb ─────────────────────────────
          _buildSection('IMDb', Icons.star_rate_outlined, [
            // Rubrik
            const Text(
              'IMDb Watchlist',
              style: TextStyle(color: Color(0xFFF5C518), fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Viktig info om offentlig lista
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5C518).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF5C518).withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFF5C518), size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Din IMDb-watchlist måste vara offentlig',
                          style: TextStyle(color: Color(0xFFF5C518), fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Gå till din Watchlist på imdb.com → kopiera URL:en från adressfältet (t.ex. imdb.com/list/ls003160623) → klistra in den nedan. Se till att "Public" är On.',
                          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // User ID-fält
            const Text(
              'IMDb User ID',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final raw = _imdbUserIdCtrl.text.trim();
              // Extract ls/ur ID from pasted URL or bare ID
              final lsId = RegExp(r'ls\d+').firstMatch(raw)?.group(0);
              final urId = RegExp(r'ur[\w]+').firstMatch(raw)?.group(0);
              final isDigitsOnly = RegExp(r'^\d+$').hasMatch(raw);
              final isValid = raw.isEmpty || lsId != null || urId != null || isDigitsOnly;
              final hasError = raw.isNotEmpty && !isValid;

              String? errorText;
              if (hasError) {
                errorText = 'Ogiltigt format. Klistra in din watchlist-URL (t.ex. https://www.imdb.com/list/ls003160623) eller bara ID:t (ls003160623 / ur12345678).';
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _imdbUserIdCtrl,
                    onChanged: (_) { setState(() {}); _scheduleSave(); },
                    style: TextStyle(color: hasError ? Colors.redAccent : Colors.white),
                    contextMenuBuilder: (ctx, state) =>
                        AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                    decoration: InputDecoration(
                      hintText: 'https://www.imdb.com/list/ls003160623  eller bara  ls003160623',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12),
                      filled: true,
                      fillColor: hasError
                          ? Colors.redAccent.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: hasError ? Colors.redAccent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: hasError ? Colors.redAccent : const Color(0xFFF5C518)),
                      ),
                      prefixIcon: Icon(
                        hasError ? Icons.error_outline : Icons.person_outline,
                        color: hasError ? Colors.redAccent : const Color(0xFFF5C518),
                        size: 18,
                      ),
                      suffixText: (!hasError && raw.isNotEmpty) ? '✓' : '',
                      suffixStyle: const TextStyle(color: Color(0xFFF5C518)),
                    ),
                  ),
                  if (hasError && errorText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Colors.redAccent, size: 15),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorText,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Hitta ditt User ID: gå till imdb.com, logga in → klicka din profilbild → "Ditt konto" → titta på URL:en: imdb.com/user/ur12345678/',
                        style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ] else if (!hasError && raw.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      lsId != null
                          ? 'RSS: rss.imdb.com/list/$lsId/'
                          : urId != null
                              ? 'RSS: rss.imdb.com/user/$urId/watchlist'
                              : 'RSS: rss.imdb.com/user/ur$raw/watchlist',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
                    ),
                  ],
                ],
              );
            }),
          ]),
          const SizedBox(height: 16),
          // ── RSS ──────────────────────────────
          _buildSection('RSS-flöden', Icons.rss_feed_outlined, [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_rssFeeds.length} flöden', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Row(children: [
                  if (_isRefreshingRss)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))))
                  else
                    TextButton.icon(
                      onPressed: _rssRefresh,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Uppdatera', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFB593FF)),
                    ),
                  if (_rssFeeds.isEmpty && !_isLoadingRss)
                    const SizedBox.shrink()
                  else
                    IconButton(
                      onPressed: _isLoadingRss ? null : _loadRssFeeds,
                      icon: const Icon(Icons.sync, color: Colors.white24, size: 16),
                      tooltip: 'Ladda om lista',
                    ),
                ]),
              ],
            ),
            const SizedBox(height: 8),
            if (_rssFeeds.isEmpty && !_isLoadingRss)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: const Text('Inga RSS-flöden tillagda', style: TextStyle(color: Colors.white24, fontSize: 13)),
              )
            else
              ..._rssFeeds.map((f) => _buildRssFeedItem(f as Map<String, dynamic>)),
            const SizedBox(height: 12),
            // Lägg till flöde
            Row(children: [
              Expanded(child: TextField(
                controller: _rssFeedUrlCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                contextMenuBuilder: (ctx, state) =>
                    AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                decoration: _inputDeco('https://exempel.com/feed.rss'),
              )),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                onPressed: _isLoadingRss ? null : _addRssFeed,
                icon: _isLoadingRss
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : const Icon(Icons.add, size: 16),
                label: const Text('Lägg till', style: TextStyle(fontSize: 13)),
              ),
            ]),
            if (_rssItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 8),
              const Text('Senaste poster', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ..._rssItems.take(10).map((item) => _buildRssItem(item as Map<String, dynamic>)),
            ],
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _loadRssFeeds() async {
    if (_isLoadingRss) return;
    setState(() => _isLoadingRss = true);
    try {
      final feeds = await widget.apiService.fetchRssFeeds();
      final items = await widget.apiService.fetchRssItems();
      if (mounted) setState(() { _rssFeeds = feeds; _rssItems = items; });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingRss = false);
    }
  }

  Future<void> _addRssFeed() async {
    final url = _rssFeedUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _isLoadingRss = true);
    try {
      await widget.apiService.addRssFeed(url);
      _rssFeedUrlCtrl.clear();
      await _loadRssFeeds();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RSS-flöde tillagt!'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoadingRss = false);
    }
  }

  Future<void> _rssRefresh() async {
    setState(() => _isRefreshingRss = true);
    try {
      final result = await widget.apiService.refreshRssFeeds();
      await _loadRssFeeds();
      if (!mounted) return;
      final n = result['newItems'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n > 0 ? '$n nya poster hämtade!' : 'Allt redan uppdaterat.'), backgroundColor: const Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isRefreshingRss = false);
    }
  }

  Widget _buildRssFeedItem(Map<String, dynamic> feed) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        const Icon(Icons.rss_feed, color: Color(0xFFB593FF), size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(feed['title'] as String? ?? feed['url'] as String,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
          Text(feed['url'] as String? ?? '',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ])),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
          onPressed: () async {
            try {
              await widget.apiService.deleteRssFeed(feed['id'] as String);
              _loadRssFeeds();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent));
            }
          },
          tooltip: 'Ta bort',
        ),
      ]),
    );
  }

  Widget _buildRssItem(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 4, height: 4, margin: const EdgeInsets.only(top: 6, right: 10),
          decoration: const BoxDecoration(color: Color(0xFF8A5BFF), shape: BoxShape.circle),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['title'] as String? ?? '—',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis),
          Text(item['feed_title'] as String? ?? '',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
        ])),
      ]),
    );
  }

}

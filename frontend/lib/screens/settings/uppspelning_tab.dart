part of '../settings_screen.dart';

extension UppspelningTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Uppspelning
  // ─────────────────────────────────────────────
  Widget _buildResolutionPriorityList() {
    final items = _versionPriority.split(',').map((s) => s.trim()).toList();

    return SizedBox(
      height: 52,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, _, __) => Material(
          color: Colors.transparent,
          child: child,
        ),
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final item = items.removeAt(oldIndex);
            items.insert(newIndex, item);
            _versionPriority = items.join(',');
          });
          _scheduleSave();
        },
        children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              key: ValueKey(items[i]),
              padding: const EdgeInsets.only(right: 8),
              child: ReorderableDragStartListener(
                index: i,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5BFF).withValues(alpha: i == 0 ? 0.20 : 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF8A5BFF).withValues(alpha: i == 0 ? 0.50 : 0.20),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.star, color: const Color(0xFFB593FF), size: 14),
                        ),
                      Text(
                        items[i],
                        style: TextStyle(
                          color: i == 0 ? Colors.white : Colors.white60,
                          fontSize: 14,
                          fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.drag_indicator, color: Colors.white.withValues(alpha: 0.3), size: 16),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUppspelning() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildSection('Standardspråk', Icons.language_outlined, [
            Row(children: [
              Expanded(child: _buildDropdown('Standardljudspråk', _defaultAudioLanguage, ['sv', 'en', 'no'], (v) { setState(() => _defaultAudioLanguage = v!); _scheduleSave(); })),
              const SizedBox(width: 16),
              Expanded(child: _buildDropdown('Standardundertextspråk', _defaultSubLangCtrl.text, ['sv', 'en', 'no', 'None'], (v) { if (v != null) { setState(() => _defaultSubLangCtrl.text = v); _scheduleSave(); } })),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _buildDropdown('Fallback för undertext (vid saknad)', _fallbackSubLangCtrl.text.isEmpty ? 'en' : _fallbackSubLangCtrl.text, ['sv', 'en', 'no', 'None'], (v) { if (v != null) { setState(() => _fallbackSubLangCtrl.text = v); _scheduleSave(); } })),
              const SizedBox(width: 16),
              Expanded(child: const SizedBox()), // Empty space for alignment
            ]),
          ]),
          const SizedBox(height: 16),
          _buildSection('Standardversion', Icons.layers_outlined, [
            Text(
              'Dra för att ändra ordning — överst = högst prioritet',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildResolutionPriorityList(),
            const SizedBox(height: 6),
            Text(
              'Styr vilken version som väljs automatiskt när en film har flera versioner.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, height: 1.5),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection('TV-Serier', Icons.tv_outlined, [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visa kommande avsnitt', style: TextStyle(color: Colors.white70, fontSize: 14)),
              subtitle: const Text('Visar ej tillgängliga avsnitt som gråade i avsnittslistan', style: TextStyle(color: Colors.white38, fontSize: 12)),
              value: _showUpcomingEpisodes,
              onChanged: (v) {
                setState(() => _showUpcomingEpisodes = v);
                _scheduleSave();
              },
              activeColor: const Color(0xFF8A5BFF),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection('Fönster', Icons.window_outlined, [
            _switchTile('Alltid överst', 'Håller Loom-fönstret ovanpå alla andra fönster.',
                _alwaysOnTop, (val) async {
              if (!kIsWeb) {
                try {
                  await windowManager.setAlwaysOnTop(val);
                  setState(() => _alwaysOnTop = val);
                  _scheduleSave();
                } catch (_) {}
              }
            }),
          ]),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

}

part of '../media_details_screen.dart';

extension MediaPlaybackTabExtension on _MediaDetailsScreenState {
Widget _buildPlaybackSelectors(Map<String, dynamic> metadata) {
    // Prefer tracks from the selected version; fall back to global metadata
    final allVersions = (_mediaData?['versions'] as List? ?? []).cast<Map<String, dynamic>>();
    final selectedVer = allVersions.isNotEmpty
        ? allVersions.firstWhere(
            (v) => v['id']?.toString() == _selectedVersionId,
            orElse: () => {},
          )
        : <String, dynamic>{};
    final subtitleTracks = (selectedVer['subtitle_tracks'] is List)
        ? (selectedVer['subtitle_tracks'] as List).cast<Map>()
        : (metadata['subtitle_tracks'] is List)
            ? (metadata['subtitle_tracks'] as List).cast<Map>()
            : <Map>[];
    final audioTracks = (selectedVer['audio_tracks'] is List)
        ? (selectedVer['audio_tracks'] as List).cast<Map>()
        : (metadata['audio_tracks'] is List)
            ? (metadata['audio_tracks'] as List).cast<Map>()
            : <Map>[];

    Widget dropdown<T>({
      required IconData icon,
      required String label,
      required T value,
      required List<DropdownMenuItem<T>> items,
      required ValueChanged<T?> onChanged,
    }) {
      return Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF8A5BFF), size: 14),
            const SizedBox(width: 6),
            Text('$label: ',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
            Flexible(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  dropdownColor: const Color(0xFF15102A),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  isDense: true,
                  isExpanded: true,
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Quality items
    final qualityItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'direct', child: Text('Direct play')),
      const DropdownMenuItem(value: '2000k', child: Text('Transcode 2 Mb')),
      const DropdownMenuItem(value: '5000k', child: Text('Transcode 5 Mb')),
      const DropdownMenuItem(value: '8000k', child: Text('Transcode 8 Mb')),
    ];

    // Subtitle items
    final subtitleItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'none', child: Text('Av')),
      ...subtitleTracks.map((t) {
        final idx = t['index']?.toString() ?? '';
        final label = t['label']?.toString() ?? t['codec']?.toString() ?? idx;
        final lang = t['language']?.toString() ?? '';
        return DropdownMenuItem(
          value: idx,
          child: Text(lang.isEmpty ? label : '$label · $lang',
              overflow: TextOverflow.ellipsis),
        );
      }),
    ];

    // Audio items — no "Auto", user must pick a track
    final audioItems = <DropdownMenuItem<String?>>[
      ...audioTracks.map((t) {
        final idx = t['index']?.toString() ?? '';
        final codec = t['codec']?.toString() ?? 'Audio';
        final lang = t['language']?.toString() ?? '';
        final ch = t['channels']?.toString() ?? '';
        final label = [codec, if (ch.isNotEmpty) '${ch}ch', if (lang.isNotEmpty) lang].join(' · ');
        return DropdownMenuItem(value: idx, child: Text(label, overflow: TextOverflow.ellipsis));
      }),
    ];

    // Build version items
    final versions = _sortedVersions();
    final singleVersion = versions.length <= 1;
    final versionItems = versions.map((v) {
      final id = v['id']?.toString() ?? '';
      return DropdownMenuItem<String>(
        value: id,
        child: Text(_MediaDetailsScreenState._buildVersionLabel(v), overflow: TextOverflow.ellipsis),
      );
    }).toList();
    // Ensure selected value is valid
    final effectiveVersionId = versionItems.any((i) => i.value == _selectedVersionId)
        ? _selectedVersionId
        : (versionItems.isNotEmpty ? versionItems.first.value : widget.mediaId);

    String? effectiveAudio;
    if (audioTracks.isNotEmpty) {
      final firstIdx = audioTracks.first['index']?.toString();
      effectiveAudio = audioItems.any((i) => i.value == _selectedAudioIndex)
          ? _selectedAudioIndex
          : firstIdx;
      if (effectiveAudio != _selectedAudioIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedAudioIndex = effectiveAudio);
        });
      }
    }

    return Row(
      children: [
        if (versionItems.isNotEmpty) ...[
          Expanded(
            child: Opacity(
              opacity: singleVersion ? 0.45 : 1.0,
              child: dropdown<String>(
                icon: Icons.layers_outlined,
                label: 'Version',
                value: effectiveVersionId!,
                items: versionItems,
                onChanged: singleVersion
                    ? (_) {}
                    : (v) {
                        if (v == null) return;
                        setState(() {
                          _selectedVersionId = v;
                          _selectedSubtitleIndex = 'none';
                          _selectedAudioIndex = null;
                        });
                        final ver = (_mediaData?['versions'] as List? ?? [])
                            .cast<Map<String, dynamic>>()
                            .firstWhere((ver) => ver['id']?.toString() == v, orElse: () => {});
                        if (ver.isNotEmpty) _applyLanguageDefaults(Map<String, dynamic>.from(ver));
                      },
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: dropdown<String>(
            icon: Icons.hd_outlined,
            label: 'Kvalitet',
            value: _selectedQuality,
            items: qualityItems,
            onChanged: (v) {
              if (v != null) setState(() => _selectedQuality = v);
              _savePlaybackSettings();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: dropdown<String>(
            icon: Icons.subtitles_outlined,
            label: 'Undertext',
            value: subtitleItems.any((i) => i.value == _selectedSubtitleIndex)
                ? _selectedSubtitleIndex
                : 'none',
            items: subtitleItems,
            onChanged: (v) {
              if (v != null) setState(() => _selectedSubtitleIndex = v);
            },
          ),
        ),
        if (audioTracks.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: dropdown<String?>(
              icon: Icons.audio_file_outlined,
              label: 'Ljud',
              value: effectiveAudio,
              items: audioItems,
              onChanged: (v) => setState(() => _selectedAudioIndex = v),
            ),
          ),
        ],
      ],
    );
  }

}

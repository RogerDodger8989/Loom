import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class UnifiedPosterCard extends StatefulWidget {
  final dynamic item;
  final bool isHomeCard;
  final bool inLibrary;
  final int index;
  final String posterPrefix;
  final String? continueEpisodeLabel;

  final String titleDisplayStyle;
  final double posterScale;
  final Set<String> selectedItems;
  final bool selectionMode;
  
  final void Function(dynamic item)? onPlayTap;
  final void Function(dynamic item, int index)? onToggleSelection;
  final void Function(dynamic item, bool isHomeCard, Offset globalPos)? onContextMenu;
  final void Function(dynamic item)? onEdit;
  final void Function(String key, bool isHovered)? onHoverChanged;
  final void Function(dynamic item, bool isHomeCard)? onPosterTap;

  const UnifiedPosterCard({
    super.key,
    required this.item,
    required this.isHomeCard,
    this.inLibrary = true,
    this.index = 0,
    required this.posterPrefix,
    this.continueEpisodeLabel,
    required this.titleDisplayStyle,
    required this.posterScale,
    required this.selectedItems,
    required this.selectionMode,
    this.onPlayTap,
    this.onToggleSelection,
    this.onContextMenu,
    this.onEdit,
    this.onHoverChanged,
    this.onPosterTap,
  });


  @override
  State<UnifiedPosterCard> createState() => _UnifiedPosterCardState();
}

class _UnifiedPosterCardState extends State<UnifiedPosterCard> {
  bool _isHovered = false;

  /// Normalise any resolution string to a human-friendly label.
  static String? _normaliseResolution(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;

    final u = s.toUpperCase();
    if (u.contains('X')) {
      final parts = u.split('X');
      if (parts.length == 2) {
        final w = int.tryParse(parts[0].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final h = int.tryParse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (w >= 3800 || h >= 2000) return '4K';
        if (w >= 1900 || h >= 1000) return '1080P';
        if (w >= 1200 || h >= 700)  return '720P';
        if (w >= 700  || h >= 420)  return '480P';
        return '${h}P';
      }
    }
    if (u.contains('4K') || u.contains('2160') || u.contains('3840')) return '4K';
    if (u.contains('1080')) return '1080P';
    if (u.contains('720'))  return '720P';
    if (u.contains('480'))  return '480P';
    if (u.contains('360'))  return '360P';
    return u;
  }

  Widget _buildPosterActionButton({
    required IconData icon,
    VoidCallback? onPressed,
    void Function(TapDownDetails)? onTapDown,
  }) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        onTapDown: onTapDown,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final title = (widget.titleDisplayStyle == 'Original' &&
            widget.item['original_title'] != null &&
            (widget.item['original_title'] as String).isNotEmpty)
        ? widget.item['original_title'] as String
        : (widget.item['title'] ?? 'Okänd').toString();

    final type = (widget.item['type'] ?? 'Movie').toString();

    // Collect unique non-null resolutions from all versions; fall back to metadata keys
    final versions = widget.item['versions'] as List? ?? [];
    final resolutionSet = <String>{};
    for (final v in versions) {
      final r = _normaliseResolution(v['resolution']?.toString());
      if (r != null) resolutionSet.add(r);
    }
    if (resolutionSet.isEmpty) {
      final meta = widget.item['metadata'];
      final raw = meta is Map
          ? (meta['resolution'] ??
                  meta['video_resolution'] ??
                  meta['quality'] ??
                  meta['video_quality'])
              ?.toString()
          : null;
      final r = raw ?? widget.item['resolution']?.toString();
      final n = _normaliseResolution(r);
      if (n != null) resolutionSet.add(n);
      // Last resort: derive from stored video dimensions
      if (resolutionSet.isEmpty && meta is Map) {
        final h = int.tryParse(meta['video_height']?.toString() ?? '');
        if (h != null && h > 0) {
          final derived = _normaliseResolution('${h}p');
          if (derived != null) resolutionSet.add(derived);
        }
      }
    }
    final resolutionLabel = resolutionSet.isEmpty ? null : resolutionSet.join(' · ');

    final versionsCount = versions.isNotEmpty ? versions.length : 1;
    final metadata = widget.item['metadata'] ?? {};
    final posterPath = widget.item['poster_path'];
    final posterKey = '${widget.posterPrefix}_${widget.item['id'] ?? widget.item['tmdb_id']}';
    
    final itemId = widget.item['id']?.toString();
    final isSelected = itemId != null && widget.selectedItems.contains(itemId);
    final posterTextScale = widget.posterScale.clamp(0.85, 1.25).toDouble();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onHoverChanged?.call(posterKey, true);
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        widget.onHoverChanged?.call(posterKey, false);
      },
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            widget.onContextMenu?.call(widget.item, widget.isHomeCard, event.position);
          }
        },
        child: GestureDetector(
        onTap: () => widget.onPosterTap?.call(widget.item, widget.isHomeCard),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Poster area (fills remaining cell height after text section) ──
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF8A5BFF).withValues(alpha: 0.05),
                        const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                      ],
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Poster image
                      if (posterPath != null && (posterPath as String).isNotEmpty)
                        Opacity(
                          opacity: widget.inLibrary ? 1.0 : 0.45,
                          child: Image.network(
                            posterPath,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                                type == 'Movie' ? Icons.movie_outlined : Icons.tv_outlined,
                                color: Colors.white24,
                                size: 36,
                              ),
                            ),
                          ),
                        )
                      else
                        Center(
                          child: Icon(
                            type == 'Movie' ? Icons.movie_outlined : Icons.tv_outlined,
                            color: Colors.white24,
                            size: 36,
                          ),
                        ),

                      if (!widget.inLibrary)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Icon(Icons.cloud_off, color: Colors.white70, size: 36),
                            ),
                          ),
                        ),

                      // Hover light overlay
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _isHovered ? 1 : 0,
                            child: Container(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                        ),
                      ),

                      // Play button (hover only)
                      if (widget.inLibrary)
                      Positioned.fill(
                        child: Center(
                          child: IgnorePointer(
                            ignoring: !_isHovered,
                            child: GestureDetector(
                              onTap: () => widget.onPlayTap?.call(widget.item),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: _isHovered ? 1 : 0,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.3),
                                  ),
                                  child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Selection checkbox (all views)
                      if (widget.inLibrary)
                      Positioned(
                        top: 10,
                        right: 10,
                          child: GestureDetector(
                            onTap: () => widget.onToggleSelection?.call(widget.item, widget.index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF8A5BFF) : Colors.black.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? Colors.white : Colors.white24, width: 1),
                              ),
          child: Icon(isSelected ? Icons.check : Icons.circle_outlined, color: Colors.white, size: 16),
                            ),
                          ),
                        ),

                      // "..." button (bottom-left)
                      if (widget.inLibrary && widget.onContextMenu != null)
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _isHovered ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !_isHovered,
                              child: _buildPosterActionButton(
                                icon: Icons.more_horiz,
                                onTapDown: (details) =>
                                    widget.onContextMenu?.call(widget.item, widget.isHomeCard, details.globalPosition),
                              ),
                            ),
                          ),
                        ),

                      // Edit button (bottom-right)
                      if (widget.inLibrary && widget.onEdit != null)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _isHovered ? 1 : 0,
                            child: IgnorePointer(
                              ignoring: !_isHovered,
                              child: _buildPosterActionButton(
                                icon: Icons.edit,
                                onPressed: () => widget.onEdit?.call(widget.item),
                              ),
                            ),
                          ),
                        ),

                      // "Premiär" banner for new season premieres
                      if (type == 'Show' && metadata['has_season_premiere'] == '1')
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFFF6B35).withValues(alpha: 0.95),
                                  const Color(0xFFFFAB40).withValues(alpha: 0.95),
                                ],
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.star, size: 10, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'PREMIÄR',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.star, size: 10, color: Colors.white),
                              ],
                            ),
                          ),
                        ),

                      // Watched checkmark (top-left)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Builder(builder: (context) {
                          if (metadata['watch_status'] == 'watched') {
                            return Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFF00E676).withValues(alpha: 0.3), blurRadius: 6),
                                ],
                              ),
                              child: const Icon(Icons.check, color: Color(0xFF00E676), size: 14),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ),

                      // Favorite star (below watched icon, top-left area)
                      if (!widget.isHomeCard)
                        Positioned(
                          top: metadata['watch_status'] == 'watched' ? 38 : 10,
                          left: 10,
                          child: Builder(builder: (context) {
                            final isFav = widget.item['is_favorite'] as bool? ?? false;
                            if (!isFav) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.star, color: Color(0xFFFFD65C), size: 14),
                            );
                          }),
                        ),

                      // Selection checkbox restored to top-right (no resolution badge here)

                      // Progress bar (bottom)
                      Builder(builder: (context) {
                        final progress = int.tryParse((metadata['playback_progress']?.toString() ?? '0')) ?? 0;
                        if (progress <= 0) return const SizedBox.shrink();
                        int duration = int.tryParse((metadata['duration']?.toString() ?? '0')) ?? 0;
                        if (duration == 0) {
                          final runtimeMinutes = int.tryParse((metadata['runtime']?.toString() ?? '0')) ?? 0;
                          duration = runtimeMinutes * 60;
                        }
                        if (duration == 0) duration = 7200;
                        final ratio = (progress / duration).clamp(0.0, 1.0);
                        return Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 6,
                            color: Colors.white12,
                            child: LinearProgressIndicator(
                              value: ratio,
                              color: const Color(0xFF8A5BFF),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // ── Text section below poster ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.0 * posterTextScale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (widget.continueEpisodeLabel != null) ...[
                      Text(
                        widget.continueEpisodeLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFB593FF),
                          fontSize: 10.0 * posterTextScale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            (widget.item['year'] != null && widget.item['year'].toString().isNotEmpty && widget.item['year'].toString() != 'null')
                                ? widget.item['year'].toString()
                                : '',
                            style: TextStyle(color: Colors.white38, fontSize: 11.0 * posterTextScale),
                          ),
                          if (resolutionLabel != null)
                            Text(
                              resolutionLabel,
                              style: TextStyle(
                                color: const Color(0xFFB593FF),
                                fontSize: 10.0 * posterTextScale,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (!widget.isHomeCard && versionsCount > 1)
                            Text(
                              '$versionsCount ver.',
                              style: TextStyle(
                                color: const Color(0xFFB593FF).withValues(alpha: 0.8),
                                fontSize: 11.0 * posterTextScale,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
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

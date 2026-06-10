part of '../media_details_screen.dart';

extension MediaInfoTabExtension on _MediaDetailsScreenState {
Widget _buildSimilarCarousel() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _similarItemsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media laddas...',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media kunde inte laddas.',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Liknande media saknas.',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        final similarItems = (snapshot.data!['items'] as List<dynamic>?) ?? [];
        if (similarItems.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Inga liknande titlar finns i biblioteket.',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ),
          );
        }

        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text('Liknande Media',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 240,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                scrollDirection: Axis.horizontal,
                itemCount: similarItems.length,
                  itemBuilder: (context, index) {
                    final item = similarItems[index];
                    final itemId = item['id']?.toString();
                    final tmdbId = item['tmdb_id']?.toString();
                    final inLibrary = item['in_library'] as bool? ?? true;
                    final type = (item['type'] as String?)?.toLowerCase() == 'show' ? 'show' : 'movie';
                    final targetId = itemId ?? 'external_${type}_$tmdbId';

                    return Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: SizedBox(
                        width: 140,
                        child: UnifiedPosterCard(
                          item: item,
                          isHomeCard: false,
                          index: index,
                          inLibrary: inLibrary,
                          posterPrefix: 'col_similar',
                          titleDisplayStyle: _titleDisplayStyle,
                          posterScale: 1.0,

                          selectedItems: const {},
                          selectionMode: false,
                          onPlayTap: inLibrary && itemId != null ? (i) => widget.onMediaSelected?.call(itemId) : null,
                          onContextMenu: (i, isHome, pos) => _mediaActionsHelper.openPosterActionsMenu(i, isHomeCard: isHome, globalPos: pos),
                                onEdit: inLibrary ? _mediaActionsHelper.openMediaEditor : null,
                          onPosterTap: (i, isHome) {
                            if (widget.onMediaSelected != null) {
                              widget.onMediaSelected!(targetId);
                            } else {
                              if (targetId.startsWith('external_')) {
                                Navigator.pushNamed(context, '/media_details', arguments: {'id': targetId, 'isExternal': true});
                              } else {
                                Navigator.pushNamed(context, '/media_details', arguments: {'id': targetId});
                              }
                            }
                          },
                        ),
                      ),
                    );
                  }
              ),
            ),
            const SizedBox(height: 60),
          ],
        );
      },
    );
  }

Widget _buildCrewRow(String label, List<Map<String, dynamic>> people) {
    if (people.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: people.map((person) {
          final name = person['name'] as String? ?? '';
          final id = person['id']?.toString();
          return ActionChip(
            mouseCursor: id != null ? SystemMouseCursors.click : MouseCursor.defer,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            label: RichText(
              text: TextSpan(children: [
                TextSpan(text: '$label ', style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                TextSpan(text: name, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
            onPressed: id != null ? () {
              if (widget.onPersonSelected != null) {
                widget.onPersonSelected!(id);
              } else {
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => PersonDetailsScreen(personId: id, apiService: widget.apiService),
                ));
              }
            } : null,
          );
        }).toList(),
      ),
    );
  }

Widget _buildRatingRow(String source, String value, Color color,
      {String? url, String? votes}) {
    Widget badge;
    if (source.toLowerCase() == 'imdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF5C518),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'IMDb',
          style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: -0.5),
        ),
      );
    } else if (source.toLowerCase() == 'simkl') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF21C65E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'SIMKL',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 0.5),
        ),
      );
    } else if (source.toLowerCase() == 'trakt') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFED2224),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'TRAKT',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.5),
        ),
      );
    } else if (source.toLowerCase() == 'tmdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF03B6E1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'TMDB',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      );
    } else {
      badge = Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
    }

    return MouseRegion(
      cursor: url != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: url != null ? () async {
          try {
            await Process.run('cmd', ['/c', 'start', '', url]);
          } catch (_) {
            await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          }
        } : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: url != null
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: url != null
                ? Border.all(color: Colors.white.withValues(alpha: 0.04))
                : null,
          ),
          child: Row(
            children: [
              badge,
              const SizedBox(width: 12),
              if (url != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new, color: Colors.white24, size: 12),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  if (votes != null && votes.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(votes,
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 11)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

Widget _buildMyRatingControl() {
    final displayRating = _isRatingHovering && _ratingPreview != null
        ? _ratingPreview!
        : _myRating;
    final displayText = displayRating.toStringAsFixed(0);
    final glowColor = _isRatingFlashing
        ? const Color(0xFFFFD65C)
        : (_isRatingHovering
            ? const Color(0xFFB593FF)
            : const Color(0xFF8A5BFF));

    Widget buildChip(int rating) {
      final isSelected = rating == displayRating.round();
      final isHovered = _isRatingHovering && _ratingPreview?.round() == rating;
      final chipGlow = _isRatingFlashing && isSelected
          ? const Color(0xFFFFD65C)
          : (isHovered ? const Color(0xFFB593FF) : const Color(0xFF8A5BFF));

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() {
          _isRatingHovering = true;
          _ratingPreview = rating.toDouble();
        }),
        child: GestureDetector(
          onTap: () => _onRatingChangeEnd(rating.toDouble()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? chipGlow.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: chipGlow.withValues(
                      alpha: isSelected || isHovered ? 0.9 : 0.22),
                  width: isSelected ? 1.3 : 1.0),
              boxShadow: [
                BoxShadow(
                  color: chipGlow.withValues(
                      alpha: isHovered || isSelected ? 0.36 : 0.08),
                  blurRadius: isHovered || isSelected ? 10 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '$rating',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onExit: (_) => setState(() {
        _isRatingHovering = false;
        _ratingPreview = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Colors.white.withValues(
                  alpha: _isRatingHovering || _isRatingFlashing ? 0.12 : 0.04)),
        ),
        child: Row(
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isResetHovering = true),
              onExit: (_) => setState(() => _isResetHovering = false),
              child: GestureDetector(
                onTap: () => _onRatingChangeEnd(0.0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isResetHovering
                        ? const Color(0xFFB9536F)
                        : const Color(0xFF8A5BFF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  child: Text(
                    _isResetHovering ? 'NOLLSTÄLL BETYG' : 'MITT BETYG',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(10, (index) {
                    final rating = index + 1;
                    if (index != 0) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: buildChip(rating),
                      );
                    }
                    return buildChip(rating);
                  }),
                ),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedScale(
              scale: _isRatingFlashing ? 1.12 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 1.3, end: 1.0).animate(
                          CurvedAnimation(
                              parent: animation, curve: Curves.easeOutBack)),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  displayText,
                  key: ValueKey('rating-$_ratingFlashNonce-$displayText'),
                  style: TextStyle(
                    color: _isRatingFlashing
                        ? const Color(0xFFFFF4B0)
                        : const Color(0xFFE7D7FF),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    shadows: [
                      Shadow(
                          color: glowColor.withValues(alpha: 0.8),
                          blurRadius: _isRatingFlashing ? 12 : 8),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('/ 10',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

}

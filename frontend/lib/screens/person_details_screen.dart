import 'package:flutter/material.dart';
import 'dart:html' as html;
import '../services/api.dart';
import 'media_details_screen.dart';

class PersonDetailsScreen extends StatefulWidget {
  final String personId;
  final ApiService apiService;
  final VoidCallback? onBack;
  final ValueChanged<String>? onMediaSelected;

  const PersonDetailsScreen({
    super.key,
    required this.personId,
    required this.apiService,
    this.onBack,
    this.onMediaSelected,
  });

  @override
  State<PersonDetailsScreen> createState() => _PersonDetailsScreenState();
}

class _PersonDetailsScreenState extends State<PersonDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _personData;

  // Search, Filter & Sort States
  String _searchQuery = '';
  String _departmentFilter = 'Alla'; 
  String _sortBy = 'Year'; // 'Year', 'Popularity', 'Rating'
  bool _sortAscending = false;
  String _viewMode = 'List'; // 'List', 'Grid', 'Card'
  int _visibleCount = 50;
  bool _bioExpanded = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPersonDetails();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchPersonDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final data = await widget.apiService.fetchPersonDetails(widget.personId);
      setState(() {
        _personData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<dynamic> _getProcessedCredits() {
    if (_personData == null) return [];

    final cast = _personData!['cast'] as List<dynamic>? ?? [];
    final crew = _personData!['crew'] as List<dynamic>? ?? [];

    // Tag source departments
    final castWithDept = cast.map((c) => {...c as Map<String, dynamic>, 'department': 'Cast'}).toList();
    final crewWithDept = crew.map((c) => {...c as Map<String, dynamic>, 'department': c['department']?.toString() ?? 'Crew'}).toList();

    // Combine
    List<dynamic> combined = [...castWithDept, ...crewWithDept];

    // Filter by department
    if (_departmentFilter == 'Cast') {
      combined = combined.where((c) => c['department'] == 'Cast').toList();
    } else if (_departmentFilter == 'Directing') {
      combined = combined.where((c) => c['department'] == 'Directing' || c['job'] == 'Director').toList();
    } else if (_departmentFilter == 'Writing') {
      combined = combined.where((c) => c['department'] == 'Writing').toList();
    } else if (_departmentFilter == 'Production') {
      combined = combined.where((c) => c['department'] == 'Production').toList();
    } else if (_departmentFilter == 'Sound') {
      combined = combined.where((c) => c['department'] == 'Sound' || c['department'] == 'Music').toList();
    } else if (_departmentFilter == 'Crew') {
      combined = combined.where((c) =>
          c['department'] != 'Cast' &&
          c['department'] != 'Directing' &&
          c['job'] != 'Director' &&
          c['department'] != 'Writing' &&
          c['department'] != 'Production' &&
          c['department'] != 'Sound' &&
          c['department'] != 'Music').toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      combined = combined.where((c) {
        final title = (c['title']?.toString() ?? '').toLowerCase();
        final character = (c['character']?.toString() ?? '').toLowerCase();
        final job = (c['job']?.toString() ?? '').toLowerCase();
        return title.contains(query) || character.contains(query) || job.contains(query);
      }).toList();
    }

    // Remove duplicates by TMDB ID
    final Set<String> seenIds = {};
    final List<dynamic> uniqueCombined = [];
    for (final item in combined) {
      final id = item['id']?.toString() ?? '';
      if (id.isNotEmpty && !seenIds.contains(id)) {
        seenIds.add(id);
        uniqueCombined.add(item);
      }
    }

    // Sort
    uniqueCombined.sort((a, b) {
      dynamic valA;
      dynamic valB;

      if (_sortBy == 'Year') {
        valA = a['year'] ?? 0;
        valB = b['year'] ?? 0;
      } else if (_sortBy == 'Popularity') {
        valA = a['popularity'] ?? 0.0;
        valB = b['popularity'] ?? 0.0;
      } else if (_sortBy == 'Rating') {
        valA = a['vote_average'] ?? 0.0;
        valB = b['vote_average'] ?? 0.0;
      }

      int compareResult = 0;
      if (valA is num && valB is num) {
        compareResult = valA.compareTo(valB);
      } else {
        compareResult = valA.toString().compareTo(valB.toString());
      }

      return _sortAscending ? compareResult : -compareResult;
    });

    return uniqueCombined;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0714),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF8A5BFF))),
      );
    }

    if (_error != null || _personData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0714),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              Text('Kunde inte hämta personuppgifter:\n$_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 12),
              const Text(
                'Använd vänstermenyn för att gå tillbaka.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    }

    final person = _personData!;
    final cast = person['cast'] as List<dynamic>? ?? [];
    final crew = person['crew'] as List<dynamic>? ?? [];
    final name = person['name'] ?? 'Okänd';
    final biography = person['biography']?.toString().isNotEmpty == true ? person['biography'] : 'Biografi saknas på både svenska och engelska.';
    final birthday = person['birthday'] ?? '';
    final deathday = person['deathday'] ?? '';
    final placeOfBirth = person['place_of_birth'] ?? '';
    final profilePath = person['profile_path'];

    String lifeSpan = '';
    if (birthday.isNotEmpty) {
      lifeSpan = birthday;
      if (deathday.isNotEmpty) {
        lifeSpan += ' - $deathday';
      }
    }
    final ageLabel = _buildAgeLabel(birthday, deathday);
    final processedCredits = _getProcessedCredits();
    final pagedCredits = processedCredits.take(_visibleCount).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: widget.onBack != null ? IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ) : null,
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bio & Profile Info (Laying it out elegantly)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Avatar Column (Left side)
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                    ),
                    child: Column(
                      children: [
                        // Circular Avatar
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF8A5BFF), width: 3),
                            image: profilePath != null
                                ? DecorationImage(image: NetworkImage(profilePath), fit: BoxFit.cover)
                                : null,
                          ),
                          child: profilePath == null
                              ? const Center(child: Icon(Icons.person, size: 80, color: Colors.white24))
                              : null,
                        ),
                        const SizedBox(height: 20),
                        if (lifeSpan.isNotEmpty) ...[
                          Text(
                            lifeSpan,
                            style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          if (ageLabel.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              ageLabel,
                              style: const TextStyle(color: Color(0xFFB593FF), fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                          const SizedBox(height: 8),
                        ],
                        if (placeOfBirth.isNotEmpty) ...[
                          Text(
                            placeOfBirth,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                        ],
                        
                        // External Badges Row
                        const Text('Externa Länkar', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            if (person['imdb_id'] != null)
                              _buildExternalBadge('IMDb', 'https://www.imdb.com/name/${person['imdb_id']}', Colors.amber),
                            _buildExternalBadge('Wikipedia', 'https://sv.wikipedia.org/wiki/${Uri.encodeComponent(name)}', Colors.white70),
                            _buildExternalBadge('TMDB', 'https://www.themoviedb.org/person/${person['id']}', Colors.blueAccent),
                            _buildExternalBadge('Simkl', 'https://simkl.com/people/${person['id']}', Colors.green),
                            _buildExternalBadge('Trakt', 'https://trakt.tv/people/${person['id']}', Colors.redAccent),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 40),

                // Biography & General Information Block (Right side)
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Biografi',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          alignment: Alignment.topLeft,
                          child: Text(
                            biography,
                            maxLines: _bioExpanded ? null : 10,
                            overflow: _bioExpanded ? TextOverflow.clip : TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
                          ),
                        ),
                        if (biography.split('\n').length > 10 || biography.length > 550) ...[
                          const SizedBox(height: 14),
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () => setState(() => _bioExpanded = !_bioExpanded),
                              child: Text(
                                _bioExpanded ? '... mindre' : '... mer',
                                style: const TextStyle(
                                  color: Color(0xFF8A5BFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Controls Row: Search, Department Filters, Sort, View Modes
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Search box
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                              _visibleCount = 50; // Reset pagination
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Sök efter filmtitel eller roll...',
                            hintStyle: const TextStyle(color: Colors.white24),
                            prefixIcon: const Icon(Icons.search, color: Colors.white30),
                            suffixIcon: _searchQuery.isNotEmpty ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white54),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _visibleCount = 50;
                                });
                              },
                            ) : null,
                            filled: true,
                            fillColor: Colors.black26,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),

                      // Department Selection Tabs
                      Row(
                        children: [
                          _buildDeptChip('Alla', 'Alla', true),
                          _buildDeptChip('Cast', 'Skådespelare', cast.isNotEmpty),
                          _buildDeptChip('Directing', 'Regissör', crew.any((c) => c['department'] == 'Directing' || c['job'] == 'Director')),
                          _buildDeptChip('Writing', 'Författare', crew.any((c) => c['department'] == 'Writing')),
                          _buildDeptChip('Production', 'Producent', crew.any((c) => c['department'] == 'Production')),
                          _buildDeptChip('Sound', 'Kompositör', crew.any((c) => c['department'] == 'Sound' || c['department'] == 'Music')),
                          _buildDeptChip('Crew', 'Övriga', crew.any((c) =>
                              c['department'] != 'Cast' &&
                              c['department'] != 'Directing' &&
                              c['job'] != 'Director' &&
                              c['department'] != 'Writing' &&
                              c['department'] != 'Production' &&
                              c['department'] != 'Sound' &&
                              c['department'] != 'Music')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Sorting & View Modes Row
                  Row(
                    children: [
                      // Sort Criteria
                      const Text('Sortera på: ', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const SizedBox(width: 8),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          dropdownColor: const Color(0xFF15102A),
                          value: _sortBy,
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 'Year', child: Text('År')),
                            DropdownMenuItem(value: 'Popularity', child: Text('Popularitet')),
                            DropdownMenuItem(value: 'Rating', child: Text('Betyg')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _sortBy = val;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Sort Direction Icon
                      IconButton(
                        icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, color: const Color(0xFF8A5BFF), size: 20),
                        tooltip: _sortAscending ? 'Sortera Stigande' : 'Sortera Fallande',
                        onPressed: () {
                          setState(() {
                            _sortAscending = !_sortAscending;
                          });
                        },
                      ),
                      const Spacer(),

                      // View Mode Toggles
                      const Text('Layout: ', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      const SizedBox(width: 8),
                      _buildViewModeButton('List', Icons.format_list_bulleted, 'Lista'),
                      const SizedBox(width: 8),
                      _buildViewModeButton('Grid', Icons.grid_view, 'Covers'),
                      const SizedBox(width: 8),
                      _buildViewModeButton('Card', Icons.chrome_reader_mode, 'Kort (Handling)'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Filmography Results Label
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Produktioner (${processedCredits.length} st)',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                if (processedCredits.length > _visibleCount)
                  Text(
                    'Visar 1–${pagedCredits.length}',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // Render Credits based on layout
            if (pagedCredits.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Text('Inga filmer matchar dina val.', style: TextStyle(color: Colors.white30, fontSize: 15)),
                ),
              )
            else ...[
              _buildViewModeLayout(pagedCredits),
              
              // Load More Pagination Button
              if (processedCredits.length > _visibleCount) ...[
                const SizedBox(height: 30),
                Center(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF281E46),
                      foregroundColor: const Color(0xFFD4C7FF),
                      side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () {
                      setState(() {
                        _visibleCount += 50;
                      });
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(
                      'Visa fler (+${processedCredits.length - _visibleCount})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeButton(String mode, IconData icon, String tooltip) {
    final isSelected = _viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => setState(() => _viewMode = mode),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF8A5BFF).withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? const Color(0xFF8A5BFF) : Colors.white10),
            ),
            child: Icon(icon, color: isSelected ? const Color(0xFF8A5BFF) : Colors.white38, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeLayout(List<dynamic> credits) {
    if (_viewMode == 'Grid') {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 24,
          crossAxisSpacing: 18,
          childAspectRatio: 0.64,
        ),
        itemCount: credits.length,
        itemBuilder: (context, index) {
          final credit = credits[index];
          return _buildGridCard(credit);
        },
      );
    } else if (_viewMode == 'Card') {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: credits.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final credit = credits[index];
          return _buildSplitCard(credit);
        },
      );
    } else {
      // Default: List view
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: credits.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final credit = credits[index];
          return _buildListRow(credit);
        },
      );
    }
  }

  // --- List View Mode Item ---
  Widget _buildListRow(dynamic credit) {
    final title = credit['title'] ?? 'Okänd titel';
    final year = credit['year'] != null ? '(${credit['year']})' : '';
    final role = credit['department'] == 'Director' ? (credit['job'] ?? 'Regissör') : (credit['character'] ?? '');
    final localId = credit['local_id']?.toString();
    final tmdbId = credit['id']?.toString();
    final poster = credit['poster_path'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          // Small Poster
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _handleOnCardTap(localId, title, tmdbId),
              child: Container(
                width: 40,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white10,
                  image: poster != null ? DecorationImage(image: NetworkImage(poster), fit: BoxFit.cover) : null,
                ),
                child: poster == null ? const Icon(Icons.movie, color: Colors.white24, size: 20) : null,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Metadata
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _handleOnCardTap(localId, title, tmdbId),
                    child: Text(
                      '$title $year',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role.isNotEmpty ? role : (credit['department'] == 'Director' ? 'Regissör' : 'Skådespelare'),
                  style: const TextStyle(color: Colors.white38, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Rating indicators
          if (credit['vote_average'] != null && credit['vote_average'] > 0) ...[
            Icon(Icons.star, color: Colors.amber.withValues(alpha: 0.8), size: 16),
            const SizedBox(width: 4),
            Text(
              (credit['vote_average'] as double).toStringAsFixed(1),
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 6),
            const Text(
              'TMDB',
              style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600, fontSize: 11),
            ),
            const SizedBox(width: 24),
          ],

          // Play locally button / indicator
          _buildPlayControl(localId, credit['id']?.toString(), title),
        ],
      ),
    );
  }

  // --- Grid View Mode Item ---
  Widget _buildGridCard(dynamic credit) {
    final title = credit['title'] ?? 'Okänd titel';
    final year = credit['year'] != null ? ' (${credit['year']})' : '';
    final localId = credit['local_id']?.toString();
    final poster = credit['poster_path'];
    final isWatched = credit['watch_status'] == 'watched';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _handleOnCardTap(localId, title, credit['id']?.toString()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (poster != null)
                      Image.network(poster, fit: BoxFit.cover)
                    else
                      const Center(child: Icon(Icons.movie, size: 40, color: Colors.white24)),
                    
                    // Owned indicator overlay badge in top-right
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: localId != null ? const Color(0xFF8A5BFF) : Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: localId != null ? Colors.white30 : Colors.white12),
                        ),
                        child: Text(
                          localId != null ? 'ÄGD' : 'EJ ÄGD',
                          style: TextStyle(
                            color: localId != null ? Colors.white : Colors.white30,
                            fontWeight: FontWeight.bold,
                            fontSize: 8,
                          ),
                        ),
                      ),
                    ),

                    // Top-left watched checkmark
                    if (isWatched)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF00E676).withValues(alpha: 0.3), blurRadius: 4)
                            ],
                          ),
                          child: const Icon(Icons.check, color: Color(0xFF00E676), size: 10),
                        ),
                      ),

                    // Progress bar
                    Builder(builder: (context) {
                      final progress = int.tryParse((credit['playback_progress']?.toString() ?? '0')) ?? 0;
                      if (progress > 0) {
                        int duration = int.tryParse((credit['duration']?.toString() ?? '0')) ?? 0;
                        if (duration == 0) {
                          final runtimeMinutes = int.tryParse((credit['runtime']?.toString() ?? '0')) ?? 0;
                          duration = runtimeMinutes * 60;
                        }
                        if (duration == 0) {
                          duration = 7200;
                        }
                        final ratio = (progress / duration).clamp(0.0, 1.0);
                        return Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 4,
                            color: Colors.white12,
                            child: LinearProgressIndicator(
                              value: ratio,
                              color: const Color(0xFF8A5BFF),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$title$year',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // --- Card/Split View Mode Item ---
  Widget _buildSplitCard(dynamic credit) {
    final title = credit['title'] ?? 'Okänd titel';
    final year = credit['year'] != null ? ' (${credit['year']})' : '';
    final role = credit['department'] == 'Director' ? (credit['job'] ?? 'Regissör') : (credit['character'] ?? '');
    final overview = credit['overview']?.toString().isNotEmpty == true ? credit['overview'] : 'Filmbeskrivning saknas.';
    final localId = credit['local_id']?.toString();
    final poster = credit['poster_path'];
    final isWatched = credit['watch_status'] == 'watched';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover left side
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _handleOnCardTap(localId, title, credit['id']?.toString()),
              child: Container(
                width: 100,
                height: 150,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white10,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (poster != null)
                      Image.network(poster, fit: BoxFit.cover)
                    else
                      const Center(child: Icon(Icons.movie, size: 36, color: Colors.white24)),
                    
                    // Top-left checkmark
                    if (isWatched)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                          ),
                          child: const Icon(Icons.check, color: Color(0xFF00E676), size: 10),
                        ),
                      ),

                    // Progress bar
                    Builder(builder: (context) {
                      final progress = int.tryParse((credit['playback_progress']?.toString() ?? '0')) ?? 0;
                      if (progress > 0) {
                        int duration = int.tryParse((credit['duration']?.toString() ?? '0')) ?? 0;
                        if (duration == 0) {
                          final runtimeMinutes = int.tryParse((credit['runtime']?.toString() ?? '0')) ?? 0;
                          duration = runtimeMinutes * 60;
                        }
                        if (duration == 0) {
                          duration = 7200;
                        }
                        final ratio = (progress / duration).clamp(0.0, 1.0);
                        return Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 4,
                            color: Colors.white12,
                            child: LinearProgressIndicator(
                              value: ratio,
                              color: const Color(0xFF8A5BFF),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),

          // Overview right side
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$title$year',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Owned Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: localId != null ? const Color(0xFF8A5BFF).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: localId != null ? const Color(0xFF8A5BFF) : Colors.white10),
                      ),
                      child: Text(
                        localId != null ? 'I DITT LOOM-BIBLIOTEK' : 'INTE ÄGD',
                        style: TextStyle(
                          color: localId != null ? const Color(0xFFD4C7FF) : Colors.white30,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      role.isNotEmpty ? role : (credit['department'] == 'Director' ? 'Regissör' : 'Skådespelare'),
                      style: const TextStyle(color: Color(0xFFB593FF), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    if (credit['vote_average'] != null && credit['vote_average'] > 0) ...[
                      const SizedBox(width: 16),
                      Icon(Icons.star, color: Colors.amber.withValues(alpha: 0.8), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        (credit['vote_average'] as double).toStringAsFixed(1),
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  overview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),

          // Play Locally Button
          _buildPlayControl(localId, credit['id']?.toString(), title),
        ],
      ),
    );
  }

  Widget _buildPlayControl(String? localId, String? tmdbId, String title) {
    if (localId != null) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8A5BFF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        onPressed: () {
          if (widget.onMediaSelected != null) {
            widget.onMediaSelected!(localId);
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MediaDetailsScreen(
                  mediaId: localId,
                  apiService: widget.apiService,
                ),
              ),
            );
          }
        },
        icon: const Icon(Icons.play_arrow, size: 16),
        label: const Text('Spela', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      );
    } else {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF281E46),
          foregroundColor: const Color(0xFFD4C7FF),
          side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        onPressed: () => _handleOnCardTap(localId, title, tmdbId),
        icon: const Icon(Icons.info_outline, size: 16),
        label: const Text('Lägg till Watchlist', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      );
    }
  }

  void _handleOnCardTap(String? localId, String title, String? tmdbId) {
    final String targetId = localId ?? 'external_movie_$tmdbId';
    if (widget.onMediaSelected != null) {
      widget.onMediaSelected!(targetId);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MediaDetailsScreen(
            mediaId: targetId,
            apiService: widget.apiService,
          ),
        ),
      );
    }
  }

  Widget _buildExternalBadge(String label, String url, Color color) {
    Widget badge;
    if (label.toLowerCase() == 'imdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF5C518),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'IMDb',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: -0.5),
        ),
      );
    } else if (label.toLowerCase() == 'wikipedia') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, color: Colors.white70, size: 12),
            SizedBox(width: 4),
            Text(
              'Wikipedia',
              style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ],
        ),
      );
    } else if (label.toLowerCase() == 'tmdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF03B6E1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'TMDB',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
        ),
      );
    } else if (label.toLowerCase() == 'simkl') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF21C65E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'SIMKL',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
        ),
      );
    } else if (label.toLowerCase() == 'trakt') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFED2224),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'TRAKT',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
        ),
      );
    } else {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          html.window.open(url, '_blank');
        },
        child: badge,
      ),
    );
  }

  Widget _buildDeptChip(String filterKey, String label, bool isEnabled) {
    final isSelected = _departmentFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label, 
          style: TextStyle(
            color: isSelected 
                ? Colors.white 
                : (isEnabled ? Colors.white60 : Colors.white24), 
            fontWeight: FontWeight.bold
          )
        ),
        selected: isSelected,
        selectedColor: const Color(0xFF8A5BFF),
        disabledColor: Colors.transparent,
        backgroundColor: Colors.white.withValues(alpha: 0.01),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected 
                ? const Color(0xFF8A5BFF) 
                : (isEnabled ? Colors.white10 : Colors.white.withValues(alpha: 0.02))
          )
        ),
        onSelected: isEnabled ? (selected) {
          if (selected) {
            setState(() {
              _departmentFilter = filterKey;
              _visibleCount = 50; // Reset pagination
            });
          }
        } : null,
      ),
    );
  }

  String _buildAgeLabel(dynamic birthday, dynamic deathday) {
    final birthdayText = birthday?.toString() ?? '';
    if (birthdayText.isEmpty) return '';

    final birthDate = DateTime.tryParse(birthdayText);
    if (birthDate == null) return '';

    final deathDateText = deathday?.toString() ?? '';
    final endDate = deathDateText.isNotEmpty ? DateTime.tryParse(deathDateText) : DateTime.now();
    if (endDate == null) return '';

    var age = endDate.year - birthDate.year;
    final birthdayPassed = endDate.month > birthDate.month ||
        (endDate.month == birthDate.month && endDate.day >= birthDate.day);
    if (!birthdayPassed) {
      age -= 1;
    }

    if (age < 0) return '';
    return '$age år';
  }
}

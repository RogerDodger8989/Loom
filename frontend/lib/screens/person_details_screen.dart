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

  @override
  void initState() {
    super.initState();
    _fetchPersonDetails();
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
              Text('Failed to load person details:\n$_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
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
    final name = person['name'] ?? 'Unknown';
    final biography = person['biography'] ?? 'No biography available.';
    final birthday = person['birthday'] ?? '';
    final deathday = person['deathday'] ?? '';
    final placeOfBirth = person['place_of_birth'] ?? '';
    final profilePath = person['profile_path'];
    final castCredits = person['cast'] as List<dynamic>? ?? [];
    final crewCredits = person['crew'] as List<dynamic>? ?? [];

    String lifeSpan = '';
    if (birthday.isNotEmpty) {
      lifeSpan = birthday;
      if (deathday.isNotEmpty) {
        lifeSpan += ' - $deathday';
      }
    }
    final ageLabel = _buildAgeLabel(birthday, deathday);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Profile Column
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  // Circular Avatar
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF8A5BFF), width: 3),
                      image: profilePath != null
                          ? DecorationImage(image: NetworkImage(profilePath), fit: BoxFit.cover)
                          : null,
                    ),
                    child: profilePath == null
                        ? const Center(child: Icon(Icons.person, size: 100, color: Colors.white24))
                        : null,
                  ),
                  const SizedBox(height: 24),
                  if (lifeSpan.isNotEmpty) ...[
                    Text(
                      lifeSpan,
                      style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    if (ageLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        ageLabel,
                        style: const TextStyle(color: Color(0xFFB593FF), fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                  if (placeOfBirth.isNotEmpty) ...[
                    Text(
                      placeOfBirth,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // External Links Row
                  const Text('Externa Länkar', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      if (person['imdb_id'] != null)
                        _buildExternalBadge('IMDb', 'https://www.imdb.com/name/${person['imdb_id']}', Colors.amber),
                      _buildExternalBadge('TMDB', 'https://www.themoviedb.org/person/${person['id']}', Colors.blueAccent),
                      _buildExternalBadge('Simkl', 'https://simkl.com/people/${person['id']}', Colors.green),
                      _buildExternalBadge('Trakt', 'https://trakt.tv/people/${person['id']}', Colors.redAccent),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 60),

            // Right Biography & Credits Column
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Biografi',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    biography,
                    style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
                  ),
                  const SizedBox(height: 40),

                  // Filmography
                  if (castCredits.isNotEmpty) ...[
                    const Text(
                      'Filmografi (Roller)',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: castCredits.length > 30 ? 30 : castCredits.length,
                      itemBuilder: (context, index) {
                        final credit = castCredits[index];
                        return _buildCreditRow(credit);
                      },
                    ),
                  ],

                  if (crewCredits.isNotEmpty) ...[
                    const SizedBox(height: 40),
                    const Text(
                      'Regi',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: crewCredits.length > 15 ? 15 : crewCredits.length,
                      itemBuilder: (context, index) {
                        final credit = crewCredits[index];
                        return _buildCreditRow(credit, isCrew: true);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalBadge(String label, String url, Color color) {
    Widget badge;
    if (label.toLowerCase() == 'imdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5C518),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'IMDb',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: -0.5),
        ),
      );
    } else if (label.toLowerCase() == 'tmdb') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF03B6E1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'TMDB',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );
    } else if (label.toLowerCase() == 'simkl') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF21C65E),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'SIMKL',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
        ),
      );
    } else if (label.toLowerCase() == 'trakt') {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFED2224),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: const Text(
          'TRAKT',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
        ),
      );
    } else {
      badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
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

  Widget _buildCreditRow(dynamic credit, {bool isCrew = false}) {
    final title = credit['title'] ?? 'Unknown Title';
    final year = credit['year'] != null ? '(${credit['year']})' : '';
    final role = isCrew ? (credit['job'] ?? 'Director') : (credit['character'] ?? '');
    final localId = credit['local_id'];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          // Small Poster Thumb
          Container(
            width: 40,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Colors.white10,
              image: credit['poster_path'] != null
                  ? DecorationImage(image: NetworkImage(credit['poster_path']), fit: BoxFit.cover)
                  : null,
            ),
            child: credit['poster_path'] == null
                ? const Icon(Icons.movie, color: Colors.white24, size: 20)
                : null,
          ),
          const SizedBox(width: 16),

          // Title & Role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$title $year',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: const TextStyle(color: Colors.white38, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Finns i ditt bibliotek Indicator
          if (localId != null)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: () {
                if (widget.onMediaSelected != null) {
                  widget.onMediaSelected!(localId.toString());
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MediaDetailsScreen(
                        mediaId: localId.toString(),
                        apiService: widget.apiService,
                      ),
                    ),
                  );
                }
              },
              child: const Text('Spela lokalt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Ej ägd', style: TextStyle(color: Colors.white30, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/api.dart';

class FixMatchDialog extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;
  final String currentTitle;
  final String currentYear;
  final bool isShow;
  final VoidCallback onMatchSuccess;

  const FixMatchDialog({
    super.key,
    required this.mediaId,
    required this.apiService,
    required this.currentTitle,
    required this.currentYear,
    required this.onMatchSuccess,
    this.isShow = false,
  });

  @override
  State<FixMatchDialog> createState() => _FixMatchDialogState();
}

class _FixMatchDialogState extends State<FixMatchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _directIdController = TextEditingController();

  bool _searching = false;
  bool _matching = false;
  String? _error;
  List<dynamic> _candidates = [];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.currentTitle;
    _yearController.text = widget.currentYear;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchCandidates();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _yearController.dispose();
    _directIdController.dispose();
    super.dispose();
  }

  Future<void> _searchCandidates() async {
    if (_searchController.text.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.apiService.searchTmdbCandidates(
        widget.mediaId,
        _searchController.text.trim(),
        year: _yearController.text.trim(),
      );
      setState(() {
        _candidates = results;
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Kunde inte söka: ${e.toString()}';
        _searching = false;
      });
    }
  }

  Future<void> _applyMatch(String tmdbId) async {
    setState(() {
      _matching = true;
      _error = null;
    });
    try {
      await widget.apiService.fixMatch(widget.mediaId, tmdbId);
      widget.onMatchSuccess();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Matchningen uppdaterades och mediauppgifterna har laddats om!'),
            backgroundColor: Color(0xFF8A5BFF),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Kunde inte korrigera matchning: ${e.toString()}';
        _matching = false;
      });
    }
  }

  void _applyDirectMatch() {
    String input = _directIdController.text.trim();
    if (input.isEmpty) return;

    String tmdbId = input;
    final movieRegExp = RegExp(r'themoviedb\.org/movie/(\d+)');
    final tvRegExp = RegExp(r'themoviedb\.org/tv/(\d+)');
    if (movieRegExp.hasMatch(input)) {
      tmdbId = movieRegExp.firstMatch(input)!.group(1)!;
    } else if (tvRegExp.hasMatch(input)) {
      tmdbId = tvRegExp.firstMatch(input)!.group(1)!;
    }

    _applyMatch(tmdbId);
  }

  @override
  Widget build(BuildContext context) {
    final hintExample = widget.isShow
        ? 'T.ex. 1396 eller https://www.themoviedb.org/tv/1396-breaking-bad'
        : 'T.ex. 272 eller https://www.themoviedb.org/movie/272-batman-begins';
    final searchHint = widget.isShow ? 'Sök efter serietitel...' : 'Sök efter filmtitel...';
    final emptyText = widget.isShow ? 'Inga matchande serier hittades.' : 'Inga matchande filmer hittades.';
    final noIconFallback = widget.isShow ? Icons.tv : Icons.movie;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 700,
          height: 600,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0B1E).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Korrigera matchning',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                      label: const Text(
                        'Stäng',
                        style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10, height: 1),

              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: const TextStyle(color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Match Direct Section
                      const Text(
                        'Matcha med TMDB ID eller Länk direkt',
                        style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _directIdController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: hintExample,
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Tooltip(
                            message: 'Matcha den här titeln direkt mot en TMDB-post',
                            child: ElevatedButton.icon(
                              onPressed: _matching ? null : _applyDirectMatch,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF9A75FF),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(176, 50),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: _matching
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.link, size: 18),
                              label: _matching
                                  ? const Text('Matchar...', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))
                                  : const Text('Matcha direkt', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            ),
                          ),
                        ],
                      ),

                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20.0),
                        child: Row(
                          children: [
                            Expanded(child: Divider(color: Colors.white10)),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text('ELLER SÖK PÅ TMDB',
                                  style: TextStyle(color: Colors.white30, fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            Expanded(child: Divider(color: Colors.white10)),
                          ],
                        ),
                      ),

                      // Search Inputs
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Sökord (Titel)',
                                labelStyle: const TextStyle(color: Colors.white60),
                                hintText: searchHint,
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: _yearController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'År',
                                labelStyle: const TextStyle(color: Colors.white60),
                                hintText: 'T.ex. 2008',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _searching ? null : _searchCandidates,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8A5BFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: _searching
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.search, size: 18),
                            label: Text(
                              _searching ? 'Söker...' : 'Sök',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Results List
                      const Text(
                        'Sökresultat',
                        style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),

                      if (_searching)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: CircularProgressIndicator(color: Color(0xFF8A5BFF)),
                          ),
                        )
                      else if (_candidates.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40.0),
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'Skriv in sökord för att hitta kandidater.'
                                  : emptyText,
                              style: const TextStyle(color: Colors.white38),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _candidates.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final candidate = _candidates[index];
                            final title = candidate['title'] ?? 'Okänd titel';
                            final originalTitle = candidate['original_title'];
                            final releaseDate = candidate['release_date'] ?? '';
                            final releaseYear = releaseDate.split('-').first;
                            final posterPath = candidate['poster_path'];
                            final candidateId = candidate['id']?.toString() ?? '';

                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _matching ? null : () => _applyMatch(candidateId),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.02),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  ),
                                  child: Row(
                                    children: [
                                      // Poster Thumbnail
                                      Container(
                                        width: 45,
                                        height: 65,
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius: BorderRadius.circular(8),
                                          image: posterPath != null
                                              ? DecorationImage(
                                                  image: NetworkImage('https://image.tmdb.org/t/p/w200$posterPath'),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                        ),
                                        child: posterPath == null
                                            ? Icon(noIconFallback, color: Colors.white30, size: 20)
                                            : null,
                                      ),
                                      const SizedBox(width: 16),

                                      // Metadata
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (releaseYear.isNotEmpty) ...[
                                                  Text(
                                                    releaseYear,
                                                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                                                  ),
                                                  const SizedBox(width: 10),
                                                ],
                                                if (originalTitle != null && originalTitle != title) ...[
                                                  Expanded(
                                                    child: Text(
                                                      '($originalTitle)',
                                                      style: const TextStyle(
                                                          color: Colors.white38,
                                                          fontSize: 13,
                                                          fontStyle: FontStyle.italic),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Select Button / Icon
                                      const Icon(Icons.chevron_right, color: Colors.white38),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

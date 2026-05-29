import 'package:flutter/material.dart';
import '../services/api.dart';
import 'dart:ui';

class MediaDetailsScreen extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;

  const MediaDetailsScreen({
    Key? key,
    required this.mediaId,
    required this.apiService,
  }) : super(key: key);

  @override
  State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _mediaData;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      final data = await widget.apiService.fetchMediaDetails(widget.mediaId);
      setState(() {
        _mediaData = data;
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

    if (_error != null || _mediaData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0714),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              Text('Failed to load media details:\n$_error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final media = _mediaData!;
    final title = media['title'] ?? 'Unknown Title';
    final year = media['year']?.toString() ?? '';
    final plot = media['plot'] ?? 'No overview available.';
    final genre = media['genre'] ?? '';
    final posterPath = media['poster_path'];
    final fanartPath = media['fanart_path'];
    
    final metadata = media['metadata'] ?? {};
    final ratings = metadata['ratings'] ?? {};
    final cast = metadata['cast'] as List<dynamic>? ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Force Refresh Metadata',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Force refresh triggered in backend (coming soon)')));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Fanart Section
            Stack(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  width: double.infinity,
                  child: fanartPath != null
                      ? Image.network(fanartPath, fit: BoxFit.cover)
                      : Container(color: const Color(0xFF15102A)),
                ),
                // Gradient overlay
                Container(
                  height: MediaQuery.of(context).size.height * 0.6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        const Color(0xFF0A0714).withOpacity(0.5),
                        const Color(0xFF0A0714),
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
                // Poster and Title Content overlay
                Positioned(
                  bottom: 0,
                  left: 40,
                  right: 40,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Poster Image
                      if (posterPath != null)
                        Container(
                          width: 200,
                          height: 300,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10)),
                            ],
                            image: DecorationImage(image: NetworkImage(posterPath), fit: BoxFit.cover),
                          ),
                        ),
                      const SizedBox(width: 40),
                      // Title and Meta
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold, height: 1.1),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (year.isNotEmpty) ...[
                                  Text(year, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                                  const SizedBox(width: 16),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(border: Border.all(color: Colors.white30), borderRadius: BorderRadius.circular(4)),
                                  child: const Text('PG-13', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)), // Mocked rating
                                ),
                                const SizedBox(width: 16),
                                Text(genre, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                              ],
                            ),
                            const SizedBox(height: 24),
                            // Actions
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.play_arrow, size: 28),
                                  label: const Text('Play', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8A5BFF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline, size: 32, color: Colors.white70),
                                  onPressed: () {},
                                  tooltip: 'Mark as Played',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.more_horiz, size: 32, color: Colors.white70),
                                  onPressed: () {},
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Details Section
            Padding(
              padding: const EdgeInsets.all(40),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Plot and Settings (2/3 width)
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plot,
                          style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
                        ),
                        const SizedBox(height: 40),
                        const Text('Audio & Subtitles', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdown('Audio Track', ['English (AAC 5.1)', 'Director Commentary']),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _buildDropdown('Subtitles', ['None', 'Swedish (SRT)', 'English (SDH)']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 60),
                  // Ratings (1/3 width)
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ratings', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        if (ratings['tmdb'] != null)
                          _buildRatingRow('TMDB', '${ratings['tmdb']} / 10', Colors.blue),
                        if (ratings['imdb'] != null)
                          _buildRatingRow('IMDb', ratings['imdb'], Colors.yellow),
                        if (ratings['rotten_tomatoes'] != null)
                          _buildRatingRow('Rotten Tomatoes', ratings['rotten_tomatoes'], Colors.red),
                        if (ratings.isEmpty)
                          const Text('No ratings available.', style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Cast Section
            if (cast.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text('Cast', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  scrollDirection: Axis.horizontal,
                  itemCount: cast.length,
                  itemBuilder: (context, index) {
                    final actor = cast[index];
                    return Container(
                      width: 140,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 160,
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                              image: actor['profile_path'] != null 
                                ? DecorationImage(image: NetworkImage(actor['profile_path']), fit: BoxFit.cover)
                                : null,
                            ),
                            child: actor['profile_path'] == null 
                                ? const Center(child: Icon(Icons.person, size: 50, color: Colors.white24)) 
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(actor['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(actor['character'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 60),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRatingRow(String source, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 12),
          Text(source, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDropdown(String label, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: options.first,
              dropdownColor: const Color(0xFF15102A),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              items: options.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt,
                  child: Text(opt, style: const TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: (val) {},
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../services/api.dart';
import 'dart:ui';
import 'dart:html' as html;
import 'person_details_screen.dart';
import 'resume_playback_modal.dart';

class MediaDetailsScreen extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;
  final VoidCallback? onBack;
  final ValueChanged<String>? onGenreSelected;

  const MediaDetailsScreen({
    super.key,
    required this.mediaId,
    required this.apiService,
    this.onBack,
    this.onGenreSelected,
  });

  @override
  State<MediaDetailsScreen> createState() => _MediaDetailsScreenState();
}

class _MediaDetailsScreenState extends State<MediaDetailsScreen> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _mediaData;
  double _myRating = 0.0;
  bool _isWatched = false;
  int _savedProgressSeconds = 0;
  String _titleDisplayStyle = 'Translated';
  String _selectedAudioTrack = 'English (AAC 5.1)';
  String _selectedSubtitle = 'None';

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
      
      // Extract ratings / watch status if saved
      final metadata = data['metadata'] ?? {};
      final savedRating = double.tryParse(metadata['my_rating']?.toString() ?? '0') ?? 0.0;
      final savedWatchStatus = metadata['watch_status'] == 'watched';
      final progress = int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;

      // Load settings to fetch default options
      String titleStyle = 'Translated';
      String subLang = 'sv';
      String audioLang = 'en';
      try {
        final settings = await widget.apiService.getSettings();
        if (settings.containsKey('TITLE_DISPLAY_STYLE')) {
          titleStyle = settings['TITLE_DISPLAY_STYLE'];
        }
        subLang = settings['DEFAULT_SUBTITLE_LANG'] ?? 'sv';
        audioLang = settings['DEFAULT_AUDIO_LANG'] ?? 'en';
      } catch (e) {
        debugPrint('Error loading settings in details: $e');
      }

      // Pre-select based on settings
      final audioTrack = (audioLang.toLowerCase() == 'sv' || audioLang.toLowerCase() == 'swedish') 
          ? 'Swedish (Stereo)' 
          : 'English (AAC 5.1)';
      final subtitle = (subLang.toLowerCase() == 'sv' || subLang.toLowerCase() == 'swedish') 
          ? 'Swedish (SRT)' 
          : (subLang.toLowerCase() == 'en' || subLang.toLowerCase() == 'english')
              ? 'English (SDH)'
              : 'None';

      setState(() {
        _mediaData = data;
        _myRating = savedRating;
        _isWatched = savedWatchStatus;
        _savedProgressSeconds = progress;
        _titleDisplayStyle = titleStyle;
        _selectedAudioTrack = audioTrack;
        _selectedSubtitle = subtitle;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onRatingChanged(double val) {
    setState(() {
      _myRating = val;
    });
  }

  Future<void> _onRatingChangeEnd(double val) async {
    // Sync locally and queue background Trakt/Simkl syncs once dragging stops
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Betyg uppdaterat till ${val.toStringAsFixed(1)}! Synkas med Trakt/Simkl.'),
            backgroundColor: const Color(0xFF8A5BFF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _toggleWatchStatus() async {
    setState(() {
      _isWatched = !_isWatched;
    });
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isWatched ? 'Markerad som sedd! Synkar...' : 'Markerad som osedd! Synkar...'),
          backgroundColor: const Color(0xFF8A5BFF),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _showFixMatchDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return _FixMatchDialog(
          mediaId: widget.mediaId,
          apiService: widget.apiService,
          currentTitle: _mediaData?['title'] ?? '',
          currentYear: _mediaData?['year']?.toString() ?? '',
          onMatchSuccess: () {
            _fetchDetails();
          },
        );
      },
    );
  }

  void _playMedia() {
    if (_savedProgressSeconds > 0) {
      showDialog(
        context: context,
        builder: (context) => ResumePlaybackModal(
          savedPositionSeconds: _savedProgressSeconds,
          onResume: () {
            _startPlayback(_savedProgressSeconds);
          },
          onStartOver: () {
            _startPlayback(0);
          },
        ),
      );
    } else {
      _startPlayback(0);
    }
  }

  void _startPlayback(int startFromSeconds) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(startFromSeconds > 0 
          ? 'Startar uppspelning från ${startFromSeconds}s...' 
          : 'Startar uppspelning...'),
        backgroundColor: const Color(0xFF8A5BFF),
      ),
    );
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
    final plot = media['plot'] ?? 'Ingen beskrivning tillgänglig.';
    final posterPath = media['poster_path'];
    final fanartPath = media['fanart_path'];
    final directorName = media['director'];
    final collectionName = media['collection_name'];
    final trailerUrl = media['metadata']?['trailer_url'];
    
    final genresList = (media['genre'] as String? ?? '').split(', ').filter((g) => g.isNotEmpty).toList();
    final metadata = (media['metadata'] is Map) ? media['metadata'] as Map<String, dynamic> : {};
    final ratings = (metadata['ratings'] is Map) ? metadata['ratings'] as Map<String, dynamic> : {};
    final cast = (metadata['cast'] is List) ? metadata['cast'] as List<dynamic> : [];
    final providers = (metadata['watch_providers'] is Map && metadata['watch_providers']['SE'] is Map)
        ? (metadata['watch_providers']['SE']['flatrate'] as List<dynamic>? ?? [])
        : [];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fanart & Hero Column
            Stack(
              children: [
                // Background fanart with mask
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  width: double.infinity,
                  child: fanartPath != null
                      ? ShaderMask(
                          shaderCallback: (rect) {
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.9),
                                Colors.black.withOpacity(0.3),
                                const Color(0xFF0A0714),
                              ],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: Image.network(fanartPath, fit: BoxFit.cover),
                        )
                      : Container(color: const Color(0xFF15102A)),
                ),

                // Hero Content overlay
                Positioned(
                  bottom: 0,
                  left: 40,
                  right: 40,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Interactive Cover on the Left
                      if (posterPath != null)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _playMedia,
                            child: Container(
                              width: 220,
                              height: 330,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 24, offset: const Offset(0, 12)),
                                ],
                                image: DecorationImage(image: NetworkImage(posterPath), fit: BoxFit.cover),
                              ),
                              child: Stack(
                                children: [
                                  // Hover Play Overlay
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  const Center(
                                    child: CircleAvatar(
                                      radius: 36,
                                      backgroundColor: Color(0xCC8A5BFF),
                                      child: Icon(Icons.play_arrow, size: 40, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 40),

                      // Title & Metadata info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title (Year) with translated/original logic
                            Builder(
                              builder: (context) {
                                final originalTitle = media['original_title'] as String?;
                                final hasOriginal = originalTitle != null && originalTitle.isNotEmpty;
                                final isOriginalStyle = _titleDisplayStyle == 'Original';
                                
                                String mainDisplayTitle = title;
                                String? subtitleDisplayTitle;

                                if (isOriginalStyle && hasOriginal) {
                                  mainDisplayTitle = originalTitle;
                                  if (originalTitle.toLowerCase() != title.toLowerCase()) {
                                    subtitleDisplayTitle = 'Översatt titel: $title';
                                  }
                                } else if (!isOriginalStyle && hasOriginal) {
                                  mainDisplayTitle = title;
                                  if (originalTitle.toLowerCase() != title.toLowerCase()) {
                                    subtitleDisplayTitle = 'Originaltitel: $originalTitle';
                                  }
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      year.isNotEmpty ? '$mainDisplayTitle ($year)' : mainDisplayTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 44,
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    if (subtitleDisplayTitle != null) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        subtitleDisplayTitle,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.55),
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                            // Awards Row
                            _buildAwardsRow(metadata['awards'] as String?),
                            const SizedBox(height: 12),

                            // Subtitle Metadata details
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white30),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('PG-13', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 16),
                                
                                // Collection Banner
                                if (collectionName != null) ...[
                                  const Icon(Icons.layers, color: Color(0xFFB593FF), size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    collectionName,
                                    style: const TextStyle(color: Color(0xFFB593FF), fontSize: 16, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 16),
                                ],

                                // Director
                                if (directorName != null) ...[
                                  const Text('Regi: ', style: TextStyle(color: Colors.white38, fontSize: 16)),
                                  MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: () {
                                        // Search Director or Open bio if ID exists
                                      },
                                      child: Text(
                                        directorName,
                                        style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Clickable Genre Badges
                            Wrap(
                              spacing: 8,
                              children: genresList.map((g) {
                                return ActionChip(
                                  backgroundColor: Colors.white.withOpacity(0.06),
                                  side: BorderSide(color: Colors.white.withOpacity(0.08)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  label: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  onPressed: () {
                                    if (widget.onGenreSelected != null) {
                                      widget.onGenreSelected!(g);
                                    } else {
                                      Navigator.pop(context, g);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),

                            // Control Actions Row
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _playMedia,
                                  icon: const Icon(Icons.play_arrow, size: 28),
                                  label: const Text('Spela', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8A5BFF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    elevation: 8,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                
                                // Trailer Button
                                if (trailerUrl != null) ...[
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      html.window.open(trailerUrl, '_blank');
                                    },
                                    icon: const Icon(Icons.slideshow, size: 22, color: Colors.white),
                                    label: const Text('Trailer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.white54, width: 1.5),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],

                                // Watch Status button
                                IconButton(
                                  icon: Icon(
                                    _isWatched ? Icons.check_circle : Icons.check_circle_outline,
                                    size: 32,
                                    color: _isWatched ? const Color(0xFF8A5BFF) : Colors.white70,
                                  ),
                                  onPressed: _toggleWatchStatus,
                                  tooltip: 'Markera som sedd/osedd',
                                ),
                                const SizedBox(width: 16),
                                
                                // More actions button (re-match)
                                IconButton(
                                  icon: const Icon(
                                    Icons.more_horiz,
                                    size: 32,
                                    color: Colors.white70,
                                  ),
                                  onPressed: _showFixMatchDialog,
                                  tooltip: 'Korrigera matchning',
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

            // Content & Ratings
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overview & Streams info (2/3 width)
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plot,
                          style: const TextStyle(color: Colors.white70, fontSize: 17, height: 1.6),
                        ),
                        const SizedBox(height: 40),
                        
                        // Streaming Watch Providers
                        if (providers.isNotEmpty) ...[
                          const Text('Finns att strömma på', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Row(
                            children: providers.map((prov) {
                              final logoPath = prov['logo_path'];
                              final name = prov['provider_name'];
                              if (logoPath == null) return const SizedBox();
                              return Container(
                                margin: const EdgeInsets.only(right: 16),
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                  image: DecorationImage(
                                    image: NetworkImage('https://image.tmdb.org/t/p/w500$logoPath'),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Tooltip(message: name ?? ''),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 40),
                        ],

                        const Text('Ljudspår & Undertexter', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdown(
                                'Audio Track', 
                                _selectedAudioTrack, 
                                ['English (AAC 5.1)', 'Swedish (Stereo)'], 
                                (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedAudioTrack = val;
                                    });
                                  }
                                }
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _buildDropdown(
                                'Subtitles', 
                                _selectedSubtitle, 
                                ['None', 'Swedish (SRT)', 'English (SDH)'], 
                                (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedSubtitle = val;
                                    });
                                  }
                                }
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 60),

                  // Ratings Panel (1/3 width)
                  Expanded(
                    flex: 1,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.04)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Betyg', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 20),
                          if (ratings['tmdb'] != null)
                            _buildRatingRow('TMDB', '${ratings['tmdb']} / 10', Colors.blueAccent),
                          if (media['imdb_id'] != null)
                            _buildRatingRow('IMDb', '7.8 / 10', Colors.amber), // Simulated IMDb score
                          _buildRatingRow('Simkl', '82%', Colors.green), // Simulated Simkl score
                          
                          const Divider(color: Colors.white12, height: 32),

                          // Eget Betyg slider
                          const Text('Mitt Betyg', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: const Color(0xFF8A5BFF),
                                    inactiveTrackColor: Colors.white12,
                                    thumbColor: const Color(0xFF8A5BFF),
                                    overlayColor: const Color(0x298A5BFF),
                                  ),
                                  child: Slider(
                                    value: _myRating,
                                    min: 0.0,
                                    max: 10.0,
                                    divisions: 10,
                                    label: _myRating.toStringAsFixed(1),
                                    onChanged: _onRatingChanged,
                                    onChangeEnd: _onRatingChangeEnd,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${_myRating.toStringAsFixed(0)}/10',
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cast Carousel
            if (cast.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text('Skådespelare', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 230,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  scrollDirection: Axis.horizontal,
                  itemCount: cast.length,
                  itemBuilder: (context, index) {
                    final actor = cast[index];
                    final actorId = actor['id']?.toString();

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          if (actorId != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PersonDetailsScreen(
                                  personId: actorId,
                                  apiService: widget.apiService,
                                ),
                              ),
                            );
                          }
                        },
                        child: Container(
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
                                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                                  image: actor['profile_path'] != null 
                                    ? DecorationImage(image: NetworkImage(actor['profile_path']), fit: BoxFit.cover)
                                    : null,
                                ),
                                child: actor['profile_path'] == null 
                                    ? const Center(child: Icon(Icons.person, size: 50, color: Colors.white24)) 
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              Text(actor['name'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(actor['character'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
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

  Widget _buildDropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
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
              value: value,
              dropdownColor: const Color(0xFF15102A),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
              items: options.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt,
                  child: Text(opt, style: const TextStyle(color: Colors.white)),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAwardsRow(String? awardsString) {
    if (awardsString == null || awardsString.trim().isEmpty) return const SizedBox();
    
    // Parse using regex
    int oscarsWins = 0;
    int oscarsNoms = 0;
    int globesWins = 0;
    int globesNoms = 0;
    int baftaWins = 0;
    int baftaNoms = 0;
    int totalWins = 0;
    int totalNoms = 0;

    // RegEx patterns
    final oscarWinPattern = RegExp(r'Won\s+(\d+)\s+Oscars?', caseSensitive: false);
    final oscarNomPattern = RegExp(r'Nominated\s+for\s+(\d+)\s+Oscars?', caseSensitive: false);
    final globeWinPattern = RegExp(r'Won\s+(\d+)\s+Golden\s+Globes?', caseSensitive: false);
    final globeNomPattern = RegExp(r'Nominated\s+for\s+(\d+)\s+Golden\s+Globes?', caseSensitive: false);
    final baftaWinPattern = RegExp(r'Won\s+(\d+)\s+BAFTAs?', caseSensitive: false);
    final baftaNomPattern = RegExp(r'Nominated\s+for\s+(\d+)\s+BAFTAs?', caseSensitive: false);
    final winPattern = RegExp(r'(\d+)\s+win', caseSensitive: false);
    final nomPattern = RegExp(r'(\d+)\s+nomination', caseSensitive: false);

    // Matching
    var match = oscarWinPattern.firstMatch(awardsString);
    if (match != null) oscarsWins = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = oscarNomPattern.firstMatch(awardsString);
    if (match != null) oscarsNoms = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = globeWinPattern.firstMatch(awardsString);
    if (match != null) globesWins = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = globeNomPattern.firstMatch(awardsString);
    if (match != null) globesNoms = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = baftaWinPattern.firstMatch(awardsString);
    if (match != null) baftaWins = int.tryParse(match.group(1) ?? '0') ?? 0;

    match = baftaNomPattern.firstMatch(awardsString);
    if (match != null) baftaNoms = int.tryParse(match.group(1) ?? '0') ?? 0;

    for (final m in winPattern.allMatches(awardsString)) {
      final val = int.tryParse(m.group(1) ?? '0') ?? 0;
      if (val > totalWins) totalWins = val;
    }
    for (final m in nomPattern.allMatches(awardsString)) {
      final val = int.tryParse(m.group(1) ?? '0') ?? 0;
      if (val > totalNoms) totalNoms = val;
    }

    final List<Widget> badges = [];

    Widget buildBadge({
      required IconData icon,
      required Color color,
      required String label,
      required String tooltip,
    }) {
      return Container(
        margin: const EdgeInsets.only(right: 12, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
        ),
        child: Tooltip(
          message: tooltip,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color.withAlpha(240),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (oscarsWins > 0) {
      badges.add(buildBadge(
        icon: Icons.emoji_events,
        color: const Color(0xFFFFD700), // Gold
        label: '$oscarsWins Oscar${oscarsWins > 1 ? "s" : ""}',
        tooltip: '$oscarsWins Oscars-vinster',
      ));
    } else if (oscarsNoms > 0) {
      badges.add(buildBadge(
        icon: Icons.emoji_events_outlined,
        color: const Color(0xFFC0C0C0), // Silver
        label: '$oscarsNoms Oscar-nom',
        tooltip: '$oscarsNoms Oscars-nomineringar',
      ));
    }

    if (globesWins > 0) {
      badges.add(buildBadge(
        icon: Icons.public,
        color: const Color(0xFFFF8C00),
        label: '$globesWins Globe${globesWins > 1 ? "s" : ""}',
        tooltip: '$globesWins Golden Globe-vinster',
      ));
    } else if (globesNoms > 0) {
      badges.add(buildBadge(
        icon: Icons.public,
        color: const Color(0xFFFFB300),
        label: '$globesNoms Globe-nom',
        tooltip: '$globesNoms Golden Globe-nomineringar',
      ));
    }

    if (baftaWins > 0) {
      badges.add(buildBadge(
        icon: Icons.military_tech,
        color: const Color(0xFFCE93D8),
        label: '$baftaWins BAFTA${baftaWins > 1 ? "s" : ""}',
        tooltip: '$baftaWins BAFTA-vinster',
      ));
    } else if (baftaNoms > 0) {
      badges.add(buildBadge(
        icon: Icons.military_tech_outlined,
        color: const Color(0xFFE1BEE7),
        label: '$baftaNoms BAFTA-nom',
        tooltip: '$baftaNoms BAFTA-nomineringar',
      ));
    }

    if (totalWins > 0) {
      badges.add(buildBadge(
        icon: Icons.workspace_premium,
        color: const Color(0xFF00FFCC),
        label: '$totalWins vinst${totalWins > 1 ? "er" : ""}',
        tooltip: '$totalWins vinster totalt',
      ));
    }

    if (totalNoms > 0) {
      badges.add(buildBadge(
        icon: Icons.stars,
        color: const Color(0xFF64B5F6),
        label: '$totalNoms nom',
        tooltip: '$totalNoms nomineringar totalt',
      ));
    }

    if (badges.isEmpty) {
      badges.add(buildBadge(
        icon: Icons.emoji_events,
        color: const Color(0xFFB593FF),
        label: awardsString,
        tooltip: awardsString,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Wrap(
          children: badges,
        ),
      ],
    );
  }
}

extension FilterList<T> on List<T> {
  List<T> filter(bool Function(T) test) {
    return where(test).toList();
  }
}

class _FixMatchDialog extends StatefulWidget {
  final String mediaId;
  final ApiService apiService;
  final String currentTitle;
  final String currentYear;
  final VoidCallback onMatchSuccess;

  const _FixMatchDialog({
    super.key,
    required this.mediaId,
    required this.apiService,
    required this.currentTitle,
    required this.currentYear,
    required this.onMatchSuccess,
  });

  @override
  State<_FixMatchDialog> createState() => _FixMatchDialogState();
}

class _FixMatchDialogState extends State<_FixMatchDialog> {
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
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 700,
          height: 600,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0B1E).withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
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
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60),
                      onPressed: () => Navigator.pop(context),
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
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
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
                                hintText: 'T.ex. 272 eller https://www.themoviedb.org/movie/272-batman-begins',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
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
                          ElevatedButton(
                            onPressed: _matching ? null : _applyDirectMatch,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8A5BFF),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _matching 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Matcha direkt', style: TextStyle(fontWeight: FontWeight.bold)),
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
                              child: Text('ELLER SÖK PÅ TMDB', style: TextStyle(color: Colors.white30, fontSize: 12, fontWeight: FontWeight.bold)),
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
                                hintText: 'Sök efter filmtitel...',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
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
                                labelText: 'År (Valfritt)',
                                labelStyle: const TextStyle(color: Colors.white60),
                                hintText: 'T.ex. 2008',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.04),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _searching ? null : _searchCandidates,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.08),
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withOpacity(0.12)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _searching 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.search),
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
                              _searchController.text.isEmpty ? 'Skriv in sökord för att hitta kandidater.' : 'Inga matchande filmer hittades.',
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
                                    color: Colors.white.withOpacity(0.02),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white.withOpacity(0.06)),
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
                                            ? const Icon(Icons.movie, color: Colors.white30, size: 20)
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
                                                      style: const TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
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

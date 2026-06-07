import 'package:flutter/material.dart';
import '../services/api.dart';
import 'video_player_screen.dart';

class EpisodeDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> episode;
  final String showTitle;
  final String? showFanartPath;
  final ApiService apiService;
  final VoidCallback? onStatusChanged;

  const EpisodeDetailsScreen({
    super.key,
    required this.episode,
    required this.showTitle,
    this.showFanartPath,
    required this.apiService,
    this.onStatusChanged,
  });

  @override
  State<EpisodeDetailsScreen> createState() => _EpisodeDetailsScreenState();
}

class _EpisodeDetailsScreenState extends State<EpisodeDetailsScreen> {
  late bool _isWatched;
  late int _progress;

  @override
  void initState() {
    super.initState();
    final ep = widget.episode;
    _isWatched = ep['is_watched'] == 1 || ep['is_watched'] == true;
    _progress  = int.tryParse(ep['playback_progress']?.toString() ?? '0') ?? 0;
  }

  String get _epId    => widget.episode['id']?.toString() ?? '';
  int    get _seasonN => int.tryParse(widget.episode['season_number']?.toString() ?? '1') ?? 1;
  int    get _epN     => int.tryParse(widget.episode['episode_number']?.toString() ?? '1') ?? 1;
  String get _label   => 'S${_seasonN.toString().padLeft(2,'0')}E${_epN.toString().padLeft(2,'0')}';
  String get _title   => widget.episode['title']?.toString() ?? 'Avsnitt $_epN';
  String get _airDate => widget.episode['air_date']?.toString() ?? '';
  String get _overview => widget.episode['overview']?.toString() ?? '';
  String? get _stillPath => widget.episode['still_path']?.toString();
  bool   get _hasFile => _epId.isNotEmpty && (widget.episode['file_path'] != null);
  bool   get _hasProgress => _progress > 60 && !_isWatched;

  void _play([int startFrom = 0]) {
    if (_epId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          mediaId: _epId,
          apiService: widget.apiService,
          startFromSeconds: startFrom,
        ),
      ),
    ).then((_) {
      _reload();
      widget.onStatusChanged?.call();
    });
  }

  Future<void> _reload() async {
    if (_epId.isEmpty) return;
    try {
      final data = await widget.apiService.fetchEpisodeStatus(_epId);
      if (!mounted) return;
      setState(() {
        _isWatched = data['is_watched'] == true || data['is_watched'] == 1;
        _progress  = int.tryParse(data['playback_progress']?.toString() ?? '0') ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _toggleWatched() async {
    final target = !_isWatched;
    setState(() => _isWatched = target);
    try {
      await widget.apiService.toggleEpisodeSeenStatus(_epId, target);
      widget.onStatusChanged?.call();
    } catch (_) {
      if (mounted) setState(() => _isWatched = !target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backdropPath = _stillPath ?? widget.showFanartPath;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Still / backdrop image
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.45,
              width: double.infinity,
              child: backdropPath != null
                  ? ShaderMask(
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black, Colors.black, Colors.transparent],
                        stops: [0.0, 0.5, 1.0],
                      ).createShader(rect),
                      blendMode: BlendMode.dstIn,
                      child: Image.network(backdropPath, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(color: const Color(0xFF15102A))),
                    )
                  : Container(color: const Color(0xFF15102A)),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show breadcrumb
                  Text(
                    widget.showTitle,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
                  ),
                  const SizedBox(height: 6),

                  // Episode label chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8A5BFF).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _label,
                      style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Title
                  Text(
                    _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                      letterSpacing: -0.4,
                    ),
                  ),

                  // Air date
                  if (_airDate.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _airDate,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      if (_hasFile) ...[
                        ElevatedButton.icon(
                          onPressed: () => _play(_hasProgress ? _progress : 0),
                          icon: Icon(
                            _hasProgress ? Icons.play_circle_outline : Icons.play_arrow,
                            size: 26,
                          ),
                          label: Text(
                            _hasProgress ? 'Återuppta' : 'Spela',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8A5BFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 8,
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Watched toggle
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _toggleWatched,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: _isWatched
                                    ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: _isWatched ? const Color(0xFF4CAF50) : Colors.white24,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isWatched ? Icons.check_circle : Icons.radio_button_unchecked,
                                    color: _isWatched ? const Color(0xFF4CAF50) : Colors.white54,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isWatched ? 'Sedd' : 'Markera som sedd',
                                    style: TextStyle(
                                      color: _isWatched ? const Color(0xFF4CAF50) : Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        // Not yet available
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule, color: Colors.white38, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _airDate.isNotEmpty ? 'Sänds $_airDate' : 'Ej tillgänglig ännu',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.40), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Progress bar if in progress
                  if (_hasProgress) ...[
                    const SizedBox(height: 16),
                    Builder(builder: (context) {
                      final dur = int.tryParse(widget.episode['duration']?.toString() ?? '0') ?? 0;
                      if (dur == 0) return const SizedBox.shrink();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_progress / dur).clamp(0.0, 1.0),
                          minHeight: 4,
                          color: const Color(0xFF8A5BFF),
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                        ),
                      );
                    }),
                  ],

                  // Overview
                  if (_overview.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      _overview,
                      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6),
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
}

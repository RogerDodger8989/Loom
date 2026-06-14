import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'dart:math' as math;

class SoundtrackScreen extends StatefulWidget {
  final Map<String, dynamic> soundtrackData;
  final String movieTitle;
  final String movieId;

  const SoundtrackScreen({
    Key? key,
    required this.soundtrackData,
    required this.movieTitle,
    required this.movieId,
  }) : super(key: key);

  @override
  State<SoundtrackScreen> createState() => _SoundtrackScreenState();
}

class _SoundtrackScreenState extends State<SoundtrackScreen> with SingleTickerProviderStateMixin {
  late AudioPlayer _player;
  late AnimationController _spinController;
  bool _isPlaying = false;
  
  // Exempel-låt för att testa just_audio med FLAC
  // Byt ut mot riktig FLAC/mp3 stream url från backend senare
  final String _testAudioUrl = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';

  @override
  void initState() {
    super.initState();
    _initAudio();
    
    // Snurrande animation för discart
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  Future<void> _initAudio() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    
    _player = AudioPlayer();
    
    _player.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
        if (state.playing) {
          _spinController.repeat();
        } else {
          _spinController.stop();
        }
      }
    });

    try {
      await _player.setUrl(_testAudioUrl);
    } catch (e) {
      debugPrint("Kunde inte ladda ljud: $e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _spinController.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumTitle = widget.soundtrackData['album'] ?? 'Okänt Album';
    final artist = widget.soundtrackData['artist'] ?? 'Okänd Artist';
    final coverPath = widget.soundtrackData['cover_path'];
    
    // Om vi har en discart URL från Fanart.tv (annars en placeholder/generisk skiva)
    final discartPath = widget.soundtrackData['discart_path'] ?? 'https://raw.githubusercontent.com/FortAwesome/Font-Awesome/master/svgs/solid/compact-disc.svg';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Soundtrack'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Vinyl-läge med Discart Animation
            SizedBox(
              width: 400,
              height: 300,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Discart (snurrar och glider ut till höger när den spelas)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutBack,
                    left: _isPlaying ? 120 : 20, // Glider ut när den spelas
                    child: AnimatedBuilder(
                      animation: _spinController,
                      builder: (_, child) {
                        return Transform.rotate(
                          angle: _spinController.value * 2 * math.pi,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 15,
                              offset: const Offset(5, 5),
                            )
                          ],
                        ),
                        // Om vi har en riktig transparent PNG, använd Image.network
                        // För demo, ritar vi en vinyl-liknande cirkel
                        child: ClipOval(
                          child: discartPath.endsWith('.svg') 
                              ? Container(
                                  color: Colors.black87,
                                  child: Center(
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: Colors.red[900],
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                )
                              : Image.network(discartPath, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),

                  // Album Omslag (ligger ovanpå till vänster)
                  Positioned(
                    left: 0,
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.8),
                            blurRadius: 20,
                            offset: const Offset(10, 0),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: coverPath != null
                            ? Image.network(coverPath, fit: BoxFit.cover)
                            : Container(color: const Color(0xFF2A2438)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            
            Text(
              albumTitle,
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              artist,
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 18),
            ),
            const SizedBox(height: 30),
            
            // Uppspelningskontroller
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 40,
                  color: Colors.white,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () {},
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: _togglePlay,
                  child: CircleAvatar(
                    radius: 35,
                    backgroundColor: const Color(0xFF8A5BFF),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                IconButton(
                  iconSize: 40,
                  color: Colors.white,
                  icon: const Icon(Icons.skip_next),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 50),
            
            // Omvänd upptäckt - "Se filmen"
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              icon: const Icon(Icons.movie, color: Colors.white),
              label: Text(
                'Se filmen: ${widget.movieTitle}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              onPressed: () {
                // Returnerar eller pushar media details screen för filmen
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

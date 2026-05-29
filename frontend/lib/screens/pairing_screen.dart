import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final ApiService _apiService = ApiService();
  
  String? _pairingCode;
  String? _deviceId;
  bool _isLoading = true;
  bool _isPaired = false;
  String? _pairedUser;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startPairingFlow();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  /**
   * Initializes the Plex-like PIN generation handshake and starts polling the server
   */
  Future<void> _startPairingFlow() async {
    setState(() {
      _isLoading = true;
      _isPaired = false;
    });

    try {
      final data = await _apiService.requestPairingCode();
      setState(() {
        _pairingCode = data['code'];
        _deviceId = data['deviceId'];
        _isLoading = false;
      });

      // Start polling status every 5 seconds
      _pollingTimer?.cancel();
      _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        if (_deviceId != null) {
          try {
            final status = await _apiService.checkPairingStatus(_deviceId!);
            if (status['paired'] == true) {
              timer.cancel();
              setState(() {
                _isPaired = true;
                _pairedUser = status['user']['username'];
              });
            }
          } catch (e) {
            debugPrint('Error polling pairing status: $e');
          }
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error contacting LOOM server: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F0C1B), // Very deep dark purple
              Color(0xFF15102A), // Dark royal violet
              Color(0xFF05020A), // Blackout edge
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 550,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  )
                ],
              ),
              child: _isLoading 
                ? _buildLoadingState()
                : _isPaired 
                  ? _buildSuccessState()
                  : _buildPairingState(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8A5BFF)),
        ),
        SizedBox(height: 24),
        Text(
          'Connecting to LOOM...',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildPairingState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // App Identity Header
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF8A5BFF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.play_circle_fill,
                color: Color(0xFF8A5BFF),
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            const Text(
              'LOOM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 35),
        const Text(
          'Pair Your Device',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Enter the code below in your Loom admin panel to link this screen.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white54,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 35),

        // Pairing Code Box (glowing and beautifully spaced)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 45),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF8A5BFF).withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8A5BFF).withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 2,
              )
            ],
          ),
          child: Text(
            _pairingCode ?? '----',
            style: const TextStyle(
              color: Color(0xFFB593FF),
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
          ),
        ),
        const SizedBox(height: 35),

        // Loading/Polling indicator
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white30),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Waiting for confirmation...',
              style: TextStyle(
                color: Colors.white30,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 25),
        const Divider(color: Colors.white10),
        const SizedBox(height: 15),

        // Text Action Button to refresh
        TextButton.icon(
          onPressed: _startPairingFlow,
          icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
          label: const Text(
            'Generate New Code',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Success Glowing Checkmark Icon
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF10B981).withOpacity(0.4),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.check,
            color: Color(0xFF10B981),
            size: 48,
          ),
        ),
        const SizedBox(height: 30),
        const Text(
          'Device Paired!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Successfully connected to server as "$_pairedUser". Welcome to LOOM.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 40),

        // Big Action Button to Enter App
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A5BFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
            onPressed: () {
              // Standard action: Navigate to Main Library Screen
              debugPrint('Entering LOOM dashboard...');
            },
            child: const Text(
              'Enter Library',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

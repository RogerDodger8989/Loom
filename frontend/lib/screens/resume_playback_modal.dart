import 'package:flutter/material.dart';

class ResumePlaybackModal extends StatelessWidget {
  final int savedPositionSeconds;
  final VoidKeyCallback? onResume;
  final VoidKeyCallback? onStartOver;

  const ResumePlaybackModal({
    super.key,
    required this.savedPositionSeconds,
    this.onResume,
    this.onStartOver,
  });

  String _formatDuration(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedTime = _formatDuration(savedPositionSeconds);

    return AlertDialog(
      backgroundColor: const Color(0xFF15102A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      title: const Row(
        children: [
          Icon(Icons.history, color: Color(0xFF8A5BFF), size: 28),
          SizedBox(width: 12),
          Text(
            'Fortsätt titta?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: Text(
        'Du har en sparad position för denna film. Vill du fortsätta titta från $formattedTime eller börja om från början?',
        style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
      ),
      actionsPadding: const EdgeInsets.all(20),
      actions: [
        // Play from beginning
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            if (onStartOver != null) onStartOver!();
          },
          child: Text(
            'Börja om',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 8),

        // Resume Playback
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8A5BFF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () {
            Navigator.pop(context);
            if (onResume != null) onResume!();
          },
          child: Text(
            'Fortsätt från $formattedTime',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

typedef VoidKeyCallback = void Function();

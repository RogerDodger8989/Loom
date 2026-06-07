import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef VoidKeyCallback = void Function();

class ResumePlaybackModal extends StatefulWidget {
  final int savedPositionSeconds;
  final VoidKeyCallback? onResume;
  final VoidKeyCallback? onStartOver;

  const ResumePlaybackModal({
    super.key,
    required this.savedPositionSeconds,
    this.onResume,
    this.onStartOver,
  });

  @override
  State<ResumePlaybackModal> createState() => _ResumePlaybackModalState();
}

class _ResumePlaybackModalState extends State<ResumePlaybackModal> {
  // 0 = Börja om (left), 1 = Fortsätt (right, default focused)
  int _focused = 1;

  String _formatDuration(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _activate() {
    if (_focused == 0) {
      Navigator.of(context).pop();
      widget.onStartOver?.call();
    } else {
      Navigator.of(context).pop();
      widget.onResume?.call();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() => _focused = 0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() => _focused = 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _activate();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final formattedTime = _formatDuration(widget.savedPositionSeconds);

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: AlertDialog(
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Du har en sparad position för denna film. Vill du fortsätta titta från $formattedTime eller börja om från början?',
              style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.keyboard, size: 13, color: Colors.white24),
                const SizedBox(width: 6),
                Text(
                  '← → för att navigera  •  Enter för att välja',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.all(20),
        actions: [
          // Börja om (left, index 0)
          _focused == 0
              ? ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onStartOver?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF8A5BFF), width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Börja om', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                )
              : OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onStartOver?.call();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.25), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text('Börja om', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                ),

          const SizedBox(width: 8),

          // Fortsätt (right, index 1)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A5BFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: _focused == 1
                    ? const BorderSide(color: Colors.white, width: 2)
                    : BorderSide.none,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onResume?.call();
            },
            child: Text(
              'Fortsätt från $formattedTime',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

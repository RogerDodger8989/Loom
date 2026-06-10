part of '../settings_screen.dart';

extension PapperskorgTabExtension on _SettingsScreenState {
  // ─────────────────────────────────────────────
  //  Category: Papperskorg
  // ─────────────────────────────────────────────
  Widget _buildPapperskorg() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Papperskorg',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: TrashScreen(
              apiService: widget.apiService,
              onRestored: widget.onLibraryChanged,
            ),
          ),
        ],
      ),
    );
  }

}

part of '../media_details_screen.dart';

extension MediaBadgesTabExtension on _MediaDetailsScreenState {
Widget _buildShowStatusBadge(String status, {Map<String, dynamic>? nextEpisodeToAir}) {
    final String label;
    final Color color;
    final IconData icon;
    String? returnDate;

    switch (status.toLowerCase()) {
      case 'returning series':
        color = const Color(0xFF4CAF50);
        icon = Icons.fiber_manual_record;
        if (nextEpisodeToAir != null) {
          final airDate = nextEpisodeToAir['air_date']?.toString() ?? '';
          if (airDate.isNotEmpty) {
            returnDate = airDate;
            label = 'Återkommer $airDate';
          } else {
            label = 'Pågående';
          }
        } else {
          label = 'Pågående';
        }
        break;
      case 'ended':
        label = 'Avslutat';
        color = Colors.white38;
        icon = Icons.stop_circle_outlined;
        break;
      case 'canceled':
      case 'cancelled':
        label = 'Inställt';
        color = Colors.redAccent;
        icon = Icons.cancel_outlined;
        break;
      case 'in production':
        label = 'Under produktion';
        color = const Color(0xFFFFAB40);
        icon = Icons.construction_outlined;
        break;
      case 'planned':
        label = 'Planerad';
        color = const Color(0xFF64B5F6);
        icon = Icons.schedule_outlined;
        break;
      default:
        label = status;
        color = Colors.white38;
        icon = Icons.info_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(returnDate != null ? Icons.calendar_today_outlined : icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        ],
      ),
    );
  }

Widget _buildQualityBadgesRow(String? filePath, String? resolution,
      {Map<dynamic, dynamic>? metadata}) {
    final badges = <Widget>[];

    Widget qualityBadge(String label,
        {Color color = const Color(0xFFB593FF), IconData? icon}) {
      return Container(
        margin: const EdgeInsets.only(right: 8, top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 4,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
          ],
        ),
      );
    }

    // Resolution badge
    final res = resolution?.toUpperCase() ?? '';
    if (res.contains('4K') || res.contains('2160')) {
      badges.add(
          qualityBadge('4K', color: const Color(0xFF00C9FF), icon: Icons.hd));
    } else if (res.contains('1080')) {
      badges.add(qualityBadge('1080p', color: const Color(0xFF7AB8F5)));
    } else if (res.contains('720')) {
      badges.add(qualityBadge('720p', color: Colors.white70));
    } else {
      badges.add(qualityBadge('HD', color: const Color(0xFF7AB8F5)));
    }

    // Audio format badges based on filename patterns and real DB probed audio tracks
    final path = (filePath ?? '').toLowerCase();

    // Check real db tracks first
    final List<dynamic> audioTracks =
        (metadata != null && metadata['audio_tracks'] is List)
            ? metadata['audio_tracks'] as List<dynamic>
            : [];
    final List<dynamic> subtitleTracks =
        (metadata != null && metadata['subtitle_tracks'] is List)
            ? metadata['subtitle_tracks'] as List<dynamic>
            : [];

    if (audioTracks.isNotEmpty) {
      for (final track in audioTracks) {
        final String codec = track['codec']?.toString().toUpperCase() ?? '';
        final String lang = track['language']?.toString().toUpperCase() ?? '';
        final int channels =
            int.tryParse(track['channels']?.toString() ?? '') ?? 2;
        final String chLabel = channels >= 8
            ? '7.1'
            : channels >= 6
                ? '5.1'
                : 'Stereo';

        if (codec.isNotEmpty) {
          badges.add(qualityBadge('$lang $codec $chLabel',
              color: const Color(0xFFB593FF)));
        }
      }
    } else {
      // Resilient Filename-based quality fallbacks when ffprobe results are empty
      bool hasAudioFallback = false;
      if (path.contains('dts-hd') ||
          path.contains('dtshd') ||
          path.contains('dts.hd')) {
        badges.add(qualityBadge('DTS-HD', color: const Color(0xFFFFD700)));
        hasAudioFallback = true;
      } else if (path.contains('dts')) {
        badges.add(qualityBadge('DTS', color: const Color(0xFFFFD700)));
        hasAudioFallback = true;
      } else if (path.contains('atmos') || path.contains('truehd')) {
        badges.add(qualityBadge('Atmos', color: const Color(0xFF00E5FF)));
        hasAudioFallback = true;
      } else if (path.contains('aac')) {
        badges.add(qualityBadge('AAC', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      } else if (path.contains('ac3') ||
          path.contains('dd5.1') ||
          path.contains('ddp') ||
          path.contains('dolby')) {
        badges
            .add(qualityBadge('Dolby Digital', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      }

      if (path.contains('5.1') ||
          path.contains('6ch') ||
          path.contains('5-1')) {
        badges.add(qualityBadge('5.1 Audio', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      } else if (path.contains('7.1') ||
          path.contains('8ch') ||
          path.contains('7-1')) {
        badges.add(qualityBadge('7.1 Audio', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      } else if (path.contains('stereo') ||
          path.contains('2.0') ||
          path.contains('2ch')) {
        badges.add(qualityBadge('Stereo', color: const Color(0xFFB593FF)));
        hasAudioFallback = true;
      }

      // Premium defaults if all scans returned nothing
      if (!hasAudioFallback) {
        badges.add(qualityBadge('5.1 Audio', color: const Color(0xFFB593FF)));
        badges
            .add(qualityBadge('Dolby Digital', color: const Color(0xFFB593FF)));
      }
    }

    if (subtitleTracks.isNotEmpty) {
      final langs = subtitleTracks
          .map((t) => t['language']?.toString().toUpperCase() ?? '')
          .toSet()
          .toList();
      badges.add(qualityBadge('TEXT: ${langs.join(", ")}',
          color: const Color(0xFF00FFCC)));
    } else {
      // Filename subtitle fallback scanning
      final List<String> textLangs = [];
      if (path.contains('swe') ||
          path.contains('swedish') ||
          path.contains('.se.')) textLangs.add('SWE');
      if (path.contains('eng') || path.contains('english'))
        textLangs.add('ENG');
      if (textLangs.isNotEmpty) {
        badges.add(qualityBadge('TEXT: ${textLangs.join(", ")}',
            color: const Color(0xFF00FFCC)));
      }
    }

    if (path.contains('hdr') || path.contains('hdr10')) {
      badges.add(qualityBadge('HDR', color: const Color(0xFFFF9800)));
    }

    if (badges.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(children: badges),
    );
  }

Widget _buildAwardsRow(String? awardsString) {
    if (awardsString == null ||
        awardsString.trim().isEmpty ||
        awardsString.toLowerCase().contains('inga prisuppgifter') ||
        awardsString.toLowerCase() == 'n/a') {
      return const SizedBox();
    }

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
    final oscarWinPattern =
        RegExp(r'Won\s+(\d+)\s+Oscars?', caseSensitive: false);
    final oscarNomPattern =
        RegExp(r'Nominated\s+for\s+(\d+)\s+Oscars?', caseSensitive: false);
    final globeWinPattern =
        RegExp(r'Won\s+(\d+)\s+Golden\s+Globes?', caseSensitive: false);
    final globeNomPattern = RegExp(
        r'Nominated\s+for\s+(\d+)\s+Golden\s+Globes?',
        caseSensitive: false);
    final baftaWinPattern =
        RegExp(r'Won\s+(\d+)\s+BAFTAs?', caseSensitive: false);
    final baftaNomPattern =
        RegExp(r'Nominated\s+for\s+(\d+)\s+BAFTAs?', caseSensitive: false);
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

    final rawAwardsText = awardsString.trim();

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
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
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
        label: rawAwardsText,
        tooltip: rawAwardsText,
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

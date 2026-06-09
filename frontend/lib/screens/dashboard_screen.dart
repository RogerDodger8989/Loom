import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'dart:async';
import 'dart:ui' as ui;
import 'package:window_manager/window_manager.dart';
import '../utils/platform_view_registry.dart' as ui_web;
import '../services/api.dart';
import 'episode_details_screen.dart';
import 'fix_match_dialog.dart';
import 'media_details_screen.dart';
import 'media_info_dialog.dart';
import 'person_details_screen.dart';
import 'resume_playback_modal.dart';
import 'trash_screen.dart';
import 'video_player_screen.dart';
import 'settings_screen.dart';
import 'user_picker_overlay.dart';
import 'calendar_screen.dart';

class DashboardScreen extends StatefulWidget {
  final ApiService apiService;

  const DashboardScreen({super.key, required this.apiService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  String? _selectedMediaId;
  String? _selectedPersonId;
  Map<String, dynamic>? _selectedEpisode;
  Map<String, dynamic>? _selectedEpisodeShowData;
  int? _autoPlaySecondsInNextOpen;
  int? _mediaInitialSeason;
  DateTime? _calendarSelectedDay;
  bool _isSidebarExpanded = true;
  bool _isFullscreen = false;
  int _posterSizeStep = 1;
  String _serverName = '';
  bool _showClock = false;
  String? _avatarUrl;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  static const List<double> _posterScaleSteps = [
    0.75, 0.87, 0.97, 1.08, 1.20, 1.32, 1.44, 1.56, 1.68, 1.80,
  ];

  final List<Map<String, String>> _navHistory = [];
  final List<Map<String, String>> _forwardHistory = [];

  double get _posterScale => _posterScaleSteps[_posterSizeStep.clamp(0, _posterScaleSteps.length - 1)];

  String _currentUsername() {
    final token = widget.apiService.token;
    if (token == null || token.isEmpty) return 'User';

    try {
      final parts = token.split('.');
      if (parts.length < 2) return 'User';
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (payload is Map && payload['username'] != null) {
        return payload['username'].toString();
      }
    } catch (_) {
      // Fall back to a neutral label when the JWT cannot be decoded.
    }

    return 'User';
  }

  String _currentUserInitials() {
    final username = _currentUsername().trim();
    if (username.isEmpty) return 'U';
    final parts = username.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.isNotEmpty ? parts.first[0].toUpperCase() : 'U';
    }
    return parts.take(2).map((part) => part.isNotEmpty ? part[0].toUpperCase() : '').join();
  }

  void _saveScrollOffsets() {
    if (_tabController.index == 1 && _moviesScrollController.hasClients) {
      _savedMoviesOffset = _moviesScrollController.offset;
      _savedScrollTab = 1;
    } else if (_tabController.index == 2 && _showsScrollController.hasClients) {
      _savedShowsOffset = _showsScrollController.offset;
      _savedScrollTab = 2;
    }
  }

  void _restoreScrollOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_savedScrollTab == 1 && _moviesScrollController.hasClients) {
        final max = _moviesScrollController.position.maxScrollExtent;
        _moviesScrollController.jumpTo(_savedMoviesOffset.clamp(0.0, max));
      } else if (_savedScrollTab == 2 && _showsScrollController.hasClients) {
        final max = _showsScrollController.position.maxScrollExtent;
        _showsScrollController.jumpTo(_savedShowsOffset.clamp(0.0, max));
      }
    });
  }

  void _navigateTo(String type, String id, {int? autoPlaySeconds}) {
    _saveScrollOffsets();
    setState(() {
      _autoPlaySecondsInNextOpen = autoPlaySeconds;
      String? currentType;
      String? currentId;
      if (_selectedPersonId != null) {
        currentType = 'person';
        currentId = _selectedPersonId;
      } else if (_selectedEpisode != null) {
        // Clear episode state when navigating elsewhere
        _selectedEpisode = null;
        _selectedEpisodeShowData = null;
      } else if (_selectedMediaId != null) {
        currentType = 'media';
        currentId = _selectedMediaId;
      }

      if (currentType != null && currentId != null) {
        _navHistory.add({'type': currentType, 'id': currentId});
      }

      if (type == 'media') {
        _selectedMediaId = id;
        _selectedPersonId = null;
        _selectedEpisode = null;
        _selectedEpisodeShowData = null;
      } else if (type == 'person') {
        _selectedPersonId = id;
        _selectedMediaId = null;
        _selectedEpisode = null;
        _selectedEpisodeShowData = null;
      }

      _forwardHistory.clear();
    });
    // Clear the pending autoplay flag after the navigation frame so child receives it once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoPlaySecondsInNextOpen != null) {
        setState(() {
          _autoPlaySecondsInNextOpen = null;
        });
      }
    });
  }

  void _navigateHome() {
    setState(() {
      // Push current detail page into navHistory so the Back button can return to it
      if (_selectedMediaId != null) {
        _navHistory.add({'type': 'media', 'id': _selectedMediaId!});
        _selectedMediaId = null;
      } else if (_selectedPersonId != null) {
        _navHistory.add({'type': 'person', 'id': _selectedPersonId!});
        _selectedPersonId = null;
      }
      _tabController.animateTo(0);
    });
  }

  void _goBack() {
    // Episod-vy: backa till serie-sidan utan att röra navHistory
    if (_selectedEpisode != null) {
      setState(() {
        _selectedEpisode = null;
        _selectedEpisodeShowData = null;
      });
      return;
    }

    if (_navHistory.isEmpty) {
      setState(() {
        if (_selectedPersonId != null) {
          _forwardHistory.add({'type': 'person', 'id': _selectedPersonId!});
          _selectedPersonId = null;
        } else if (_selectedMediaId != null) {
          _forwardHistory.add({'type': 'media', 'id': _selectedMediaId!});
          _selectedMediaId = null;
        }
      });
      _restoreScrollOffset();
      return;
    }

    final prev = _navHistory.last;

    if (prev['type'] == 'settings_statistics') {
      _navHistory.removeLast();
      setState(() {
        if (_selectedMediaId != null) {
          _forwardHistory.add({'type': 'media', 'id': _selectedMediaId!});
          _selectedMediaId = null;
        } else if (_selectedPersonId != null) {
          _forwardHistory.add({'type': 'person', 'id': _selectedPersonId!});
          _selectedPersonId = null;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        openSettings(context, widget.apiService,
          initialCategory: 7,
          initialStatsTab: int.tryParse(prev['statsTab'] ?? '0') ?? 0,
          onNavigateHome: _navigateHome,
          onLibraryChanged: () { setState(() {}); _loadAllMedia(); },
          onNavigateToMedia: _onNavigateToMediaFromStats)
        .then((_) => _loadSettings());
      });
      return;
    }

    setState(() {
      String? currentType;
      String? currentId;
      if (_selectedPersonId != null) {
        currentType = 'person';
        currentId = _selectedPersonId;
      } else if (_selectedMediaId != null) {
        currentType = 'media';
        currentId = _selectedMediaId;
      }

      if (currentType != null && currentId != null) {
        _forwardHistory.add({'type': currentType, 'id': currentId});
      }

      final p = _navHistory.removeLast();
      if (p['type'] == 'media') {
        _selectedMediaId = p['id'];
        _selectedPersonId = null;
      } else if (p['type'] == 'person') {
        _selectedPersonId = p['id'];
        _selectedMediaId = null;
      }
    });
  }

  void _onNavigateToMediaFromStats(String id, int statsTab) {
    _navHistory.add({'type': 'settings_statistics', 'statsTab': statsTab.toString()});
    Navigator.of(context).pop();
    _navigateTo('media', id);
  }

  void _goForward() {
    if (_forwardHistory.isEmpty) return;

    setState(() {
      String? currentType;
      String? currentId;
      if (_selectedPersonId != null) {
        currentType = 'person';
        currentId = _selectedPersonId;
      } else if (_selectedMediaId != null) {
        currentType = 'media';
        currentId = _selectedMediaId;
      }

      if (currentType != null && currentId != null) {
        _navHistory.add({'type': currentType, 'id': currentId});
      }

      final next = _forwardHistory.removeLast();
      if (next['type'] == 'media') {
        _selectedMediaId = next['id'];
        _selectedPersonId = null;
      } else if (next['type'] == 'person') {
        _selectedPersonId = next['id'];
        _selectedMediaId = null;
      }
    });
  }

  Future<void> _toggleFullscreen() async {
    if (kIsWeb) return;
    try {
      final isFs = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFs);
      if (mounted) setState(() => _isFullscreen = !isFs);
    } catch (e) {
      debugPrint('toggleFullscreen failed: $e');
    }
  }

  Widget _buildNavIcon({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final activeColor = const Color(0xFFB593FF);
    final inactiveColor = Colors.white24;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: enabled ? Colors.white.withValues(alpha: 0.04) : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: enabled ? activeColor.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
                width: 1.5,
              ),
              boxShadow: enabled ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.12),
                  blurRadius: 8,
                ),
              ] : [],
            ),
            child: Icon(
              icon,
              color: enabled ? Colors.white : inactiveColor,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClockWidget() {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return Text(
      '$h:$m',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.45),
        fontSize: 13,
        fontWeight: FontWeight.w600,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    final hasBack = _navHistory.isNotEmpty || _selectedMediaId != null || _selectedPersonId != null;
    final hasForward = _forwardHistory.isNotEmpty;

    if (!_isSidebarExpanded) {
      // Collapsed: vertical column — back, home, forward, then expand button
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNavIcon(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Gå bakåt',
            enabled: hasBack,
            onPressed: _goBack,
          ),
          const SizedBox(height: 8),
          _buildNavIcon(
            icon: Icons.home_rounded,
            tooltip: 'Hem',
            enabled: true,
            onPressed: _navigateHome,
          ),
          const SizedBox(height: 8),
          _buildNavIcon(
            icon: Icons.arrow_forward_ios_rounded,
            tooltip: 'Gå framåt',
            enabled: hasForward,
            onPressed: _goForward,
          ),
          const SizedBox(height: 16),
          // Expand button
          Tooltip(
            message: 'Fäll ut menyn',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(
                onTap: () => setState(() => _isSidebarExpanded = true),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.view_sidebar_outlined, color: Color(0xFF8A5BFF), size: 22),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Expanded: horizontal row — back, home, forward, [clock]
    return Row(
      children: [
        _buildNavIcon(
          icon: Icons.arrow_back_ios_new_rounded,
          tooltip: 'Gå bakåt',
          enabled: hasBack,
          onPressed: _goBack,
        ),
        const SizedBox(width: 10),
        _buildNavIcon(
          icon: Icons.home_rounded,
          tooltip: 'Hem',
          enabled: true,
          onPressed: _navigateHome,
        ),
        const SizedBox(width: 10),
        _buildNavIcon(
          icon: Icons.arrow_forward_ios_rounded,
          tooltip: 'Gå framåt',
          enabled: hasForward,
          onPressed: _goForward,
        ),
        if (_showClock) ...[
          const Spacer(),
          _buildClockWidget(),
        ],
      ],
    );
  }

  Widget _buildPersistentTopBar() {
    final isHome = _tabController.index == 0 &&
        _selectedMediaId == null &&
        _selectedPersonId == null;
    return Row(
      children: [
        if (isHome) ...[
          Tooltip(
            message: 'Redigera hemsektioner',
            child: InkWell(
              onTap: _openHomeLayoutEditor,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: const Icon(Icons.tune, color: Colors.white60, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: _buildHomeSearchBox()),
        const SizedBox(width: 12),
        _buildCompactPosterSizeSlider(),
        const SizedBox(width: 12),
        if (!kIsWeb) ...[
          Tooltip(
            message: _isFullscreen ? 'Avsluta helskärm (F11)' : 'Helskärm (F11)',
            child: InkWell(
              onTap: _toggleFullscreen,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: Icon(
                  _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        _buildUserSwitcher(),
      ],
    );
  }

  Widget _buildCompactPosterSizeSlider() {
    return SizedBox(
      width: 80,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: const Color(0xFF8A5BFF),
          inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
          thumbColor: const Color(0xFFB593FF),
          overlayColor: const Color(0xFF8A5BFF).withValues(alpha: 0.14),
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
        ),
        child: Slider(
          value: _posterSizeStep.toDouble(),
          min: 0,
          max: 9,
          divisions: 9,
          onChanged: (value) {
            setState(() {
              _posterSizeStep = value.round();
            });
          },
          onChangeEnd: (_) => _savePosterSize(),
        ),
      ),
    );
  }

  void _savePosterSize() {
    widget.apiService.updateSettings({'POSTER_SIZE_STEP': _posterSizeStep.toString()}).catchError((_) {});
  }

  Future<void> _confirmRestartServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text('Starta om servern?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Servern stängs av och startas om. Pågående uppspelningar avbryts.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Avbryt'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent.withValues(alpha: 0.85),
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Starta om', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.apiService.restartServer();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Servern startas om...'),
        backgroundColor: Colors.orangeAccent,
        duration: Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _buildUserSwitcher() {
    final username = _currentUsername();
    final initials = _currentUserInitials();
    final isAdmin = widget.apiService.currentUserPayload?['role'] == 'Admin';

    return PopupMenuButton<String>(
      tooltip: 'Byt användare / Inställningar',
      color: const Color(0xFF11151D),
      offset: const Offset(0, 56),
      onSelected: (value) {
        if (value == 'account') {
          openSettings(context, widget.apiService,
              initialCategory: 0,
              initialStatsTab: widget.apiService.lastStatsTabIndex,
              onNavigateHome: _navigateHome,
              onLibraryChanged: () { setState(() {}); _loadAllMedia(); },
              onNavigateToMedia: _onNavigateToMediaFromStats)
            .then((_) => _loadSettings());
        } else if (value == 'settings') {
          openSettings(context, widget.apiService,
              initialStatsTab: widget.apiService.lastStatsTabIndex,
              onNavigateHome: _navigateHome,
              onLibraryChanged: () {
                setState(() {});
                _loadAllMedia();
              },
              onNavigateToMedia: _onNavigateToMediaFromStats)
            .then((_) => _loadSettings());
        } else if (value == 'switch') {
          _openUserPicker();
        } else if (value == 'restart') {
          _confirmRestartServer();
        } else if (value == 'logout') {
          _handleLogout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'account',
          child: Row(children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.2),
              backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
              child: _avatarUrl == null ? Text(
                initials,
                style: const TextStyle(color: Color(0xFFB593FF), fontSize: 11, fontWeight: FontWeight.bold),
              ) : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(username, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text('Mitt konto', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
              ],
            ),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'settings',
          child: Row(children: [
            Icon(Icons.settings_outlined, size: 16, color: Colors.white70),
            SizedBox(width: 10),
            Text('Inställningar'),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'switch',
          child: Row(children: [
            Icon(Icons.people_outline, size: 16, color: Colors.white70),
            SizedBox(width: 10),
            Text('Byt användare'),
          ]),
        ),
        if (isAdmin) ...[
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'restart',
            child: Row(children: [
              Icon(Icons.restart_alt_rounded, size: 16, color: Colors.orangeAccent),
              SizedBox(width: 10),
              Text('Starta om servern', style: TextStyle(color: Colors.orangeAccent)),
            ]),
          ),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Row(children: [
            Icon(Icons.logout, size: 16, color: Colors.white38),
            SizedBox(width: 10),
            Text('Logga ut', style: TextStyle(color: Colors.white54)),
          ]),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              const Color(0xFF8A5BFF).withValues(alpha: 0.95),
              const Color(0xFFB593FF).withValues(alpha: 0.55),
            ],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0F131A)),
          child: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF151A24),
            backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
            child: _avatarUrl == null ? Text(
              initials,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
            ) : null,
          ),
        ),
      ),
    );
  }

  void _openUserPicker() {
    showUserPicker(
      context,
      widget.apiService,
      onSuccess: () {
        // Reload settings + media with the new user's token/avatar/preferences
        _loadSettings();
        _loadAllMedia();
      },
    );
  }

  Widget _buildPosterSizeSlider() {
    final currentLabel = '${_posterSizeStep + 1}/15';
    return Row(
      children: [
        const Icon(Icons.photo_size_select_large_outlined, color: Colors.white54, size: 18),
        const SizedBox(width: 12),
        const Text(
          'Posterstorlek',
          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF8A5BFF),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.10),
              thumbColor: const Color(0xFFB593FF),
              overlayColor: const Color(0xFF8A5BFF).withValues(alpha: 0.14),
              trackHeight: 4,
            ),
            child: Slider(
              value: _posterSizeStep.toDouble(),
              min: 0,
              max: 14,
              divisions: 14,
              label: currentLabel,
              onChanged: (value) {
                setState(() {
                  _posterSizeStep = value.round();
                });
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          currentLabel,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
        ),
      ],
    );
  }


  List<dynamic> _movies = [];
  List<dynamic> _shows = [];
  bool _loadingMedia = false;
  String? _mediaError;

  // Scanner form state
  final TextEditingController _pathController = TextEditingController();
  final String _selectedScanType = 'Movie';
  bool _isScanning = false;
  String? _currentlyScanningPath;
  bool _preferLocalNfo = true;
  bool _isBrowsingDirectory = false;
  String _scanStatusText = 'Idle';
  Map<String, dynamic>? _lastScanResult;

  List<dynamic> _libraryPaths = [];

  // Settings
  final TextEditingController _tmdbKeyController = TextEditingController();
  final TextEditingController _omdbKeyController = TextEditingController();
  final TextEditingController _simklKeyController = TextEditingController();
  final TextEditingController _simklSecretController = TextEditingController();
  final TextEditingController _simklTokenController = TextEditingController();
  final TextEditingController _traktKeyController = TextEditingController();
  final TextEditingController _traktSecretController = TextEditingController();
  final TextEditingController _traktTokenController = TextEditingController();
  final TextEditingController _tmdbAuthController = TextEditingController();
  final TextEditingController _defaultSubLangController = TextEditingController(text: 'sv');
  bool _isLoadingSettings = false;
  
  String _metadataLanguage = 'sv-SE';
  String _fallbackLanguage = 'en-US';
  String _defaultAudioLanguage = 'sv';
  String _watchProviderRegion = 'SE';
  String _titleDisplayStyle = 'Translated';
  bool _alwaysOnTop = false;

  // Granular Sync Platform Options
  bool _syncTraktRatings = true;
  bool _syncTraktWatched = true;
  bool _syncSimklRatings = true;
  bool _syncSimklWatched = true;

  // Manual Sync progress tracking
  bool _isManualSyncing = false;
  double _manualSyncProgress = 0.0;
  String _manualSyncStep = '';
  Timer? _manualSyncTimer;

  String? _genreFilter;
  String? _showsGenreFilter;
  String? _keywordFilter;
  String _moviesSearchQuery = '';
  List<Map<String, dynamic>> _homeSections = [];

  final TextEditingController _homeSearchController = TextEditingController();
  Timer? _homeSearchDebounce;
  int _homeSearchRequestNonce = 0;
  bool _homeSearchLoadingTmdb = false;
  bool _homeSearchIsOpen = false;
  bool _homeSearchIgnoreChange = false;
  List<dynamic> _homeSearchLocalResults = [];
  List<dynamic> _homeSearchTmdbResults = [];
  String _homeSearchLastQuery = '';
  List<dynamic> _homeSearchLastLocalResults = [];
  List<dynamic> _homeSearchLastTmdbResults = [];
  int _homeSearchSelectedIndex = -1;
  final OverlayPortalController _searchOverlayController = OverlayPortalController();
  final LayerLink _searchLayerLink = LayerLink();
  final GlobalKey _searchBoxKey = GlobalKey();
  String? _hoveredPosterKey;
  final Set<String> _selectedMediaIds = {};
  int? _lastSelectedMediaIndex;

  final ScrollController _moviesScrollController = ScrollController();
  final ScrollController _showsScrollController = ScrollController();
  double _savedMoviesOffset = 0.0;
  double _savedShowsOffset = 0.0;
  int _savedScrollTab = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _homeSections = _defaultHomeSections();
    _loadAllMedia();
    _checkScannerStatus();
    _loadLibraryPaths();
    _loadSettings();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    if (!kIsWeb) HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchOverlayController.show();
    });
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
      return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _defaultHomeSections() {
    return [
      {'id': 'continue_watching', 'title': 'Fortsätt titta', 'visible': true, 'comingSoon': false, 'days': 365},
      {'id': 'recent_movies', 'title': 'Nyligen tillagda Filmer', 'visible': true, 'comingSoon': false},
      {'id': 'recent_shows', 'title': 'Nyligen tillagda Serier', 'visible': true, 'comingSoon': false},
      {'id': 'recent_watched_movies', 'title': 'Nyligen sedda Filmer', 'visible': true, 'comingSoon': false},
      {'id': 'recent_watched_shows', 'title': 'Nyligen sedda Serier', 'visible': true, 'comingSoon': false},
      {'id': 'recent_images', 'title': 'Nyligen tillagda Bilder', 'visible': false, 'comingSoon': true},
      {'id': 'recent_music', 'title': 'Nyligen tillagda Musik', 'visible': false, 'comingSoon': true},
      {'id': 'tmdb_trending', 'title': 'Trender från TMDB', 'visible': false, 'comingSoon': true},
      {'id': 'tmdb_top', 'title': 'Topplistor från TMDB', 'visible': false, 'comingSoon': true},
      {'id': 'trailers_trending', 'title': 'Trendande trailers', 'visible': false, 'comingSoon': true},
      {'id': 'trailers_new', 'title': 'Nya Trailers', 'visible': false, 'comingSoon': true},
      {'id': 'custom_lists', 'title': '<Listor>', 'visible': false, 'comingSoon': true},
    ];
  }

  List<Map<String, dynamic>> _cloneHomeSections(List<Map<String, dynamic>> sections) {
    return sections.map((section) => Map<String, dynamic>.from(section)).toList();
  }

  void _loadHomeSectionsFromSettings(String? rawLayout) {
    if (rawLayout == null || rawLayout.trim().isEmpty) {
      _homeSections = _defaultHomeSections();
      return;
    }

    try {
      final decoded = jsonDecode(rawLayout);
      if (decoded is List) {
        final parsed = <Map<String, dynamic>>[];
        for (final entry in decoded) {
          if (entry is Map) {
            parsed.add({
              'id': entry['id']?.toString() ?? '',
              'title': entry['title']?.toString() ?? '',
              'visible': entry['visible'] != false,
              'comingSoon': entry['comingSoon'] == true,
              if (entry['days'] != null) 'days': int.tryParse(entry['days'].toString()) ?? 365,
            });
          }
        }

        if (parsed.isNotEmpty) {
          final validParsed = parsed.where((s) => (s['id'] ?? '').toString().isNotEmpty).toList();
          // Merge: keep saved order/visibility, append any default sections that are missing
          final savedIds = validParsed.map((s) => s['id'].toString()).toSet();
          final defaults = _defaultHomeSections();
          for (final def in defaults) {
            final id = def['id'].toString();
            if (!savedIds.contains(id)) {
              validParsed.add(def);
            }
          }
          _homeSections = validParsed;
          return;
        }
      }
    } catch (_) {
      // Fall back to defaults if the saved layout cannot be parsed.
    }

    _homeSections = _defaultHomeSections();
  }

  String _serializeHomeSections() {
    return jsonEncode(_homeSections.map((section) {
      return {
        'id': section['id'],
        'title': section['title'],
        'visible': section['visible'] != false,
        'comingSoon': section['comingSoon'] == true,
        if (section['days'] != null) 'days': section['days'],
      };
    }).toList());
  }

  void _openHomeLayoutEditor() {
    final editableSections = _cloneHomeSections(_homeSections.isEmpty ? _defaultHomeSections() : _homeSections);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF11151D),
              title: const Text('Redigera hemsektioner', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 760,
                height: 580,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dra rubrikerna för att ändra ordning och slå av/på synlighet per rubrik.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: editableSections.length,
                        onReorder: (oldIndex, newIndex) {
                          dialogSetState(() {
                            if (newIndex > oldIndex) newIndex -= 1;
                            final item = editableSections.removeAt(oldIndex);
                            editableSections.insert(newIndex, item);
                          });
                        },
                        itemBuilder: (context, index) {
                          final section = editableSections[index];
                          final isContinueWatching = section['id'] == 'continue_watching';
                          final isComingSoon = section['comingSoon'] == true;
                          final daysValue = section['days'] as int?;

                          return Container(
                            key: ValueKey(section['id']),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF171C26),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.only(right: 10),
                                    child: Icon(Icons.drag_indicator, color: Colors.white38),
                                  ),
                                ),
                                Checkbox(
                                  value: section['visible'] != false,
                                  activeColor: const Color(0xFF8A5BFF),
                                  onChanged: (value) {
                                    dialogSetState(() {
                                      section['visible'] = value == true;
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        section['title']?.toString() ?? '',
                                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                      ),
                                      if (isComingSoon)
                                        Text(
                                          'Kommer senare',
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isContinueWatching) ...[
                                  const SizedBox(width: 12),
                                  DropdownButton<int?>(
                                    value: daysValue,
                                    dropdownColor: const Color(0xFF11151D),
                                    underline: const SizedBox.shrink(),
                                    iconEnabledColor: Colors.white54,
                                    items: const [
                                      DropdownMenuItem<int?>(value: 30, child: Text('30 dagar')),
                                      DropdownMenuItem<int?>(value: 60, child: Text('60 dagar')),
                                      DropdownMenuItem<int?>(value: 180, child: Text('180 dagar')),
                                      DropdownMenuItem<int?>(value: 365, child: Text('365 dagar')),
                                      DropdownMenuItem<int?>(value: null, child: Text('Ingen begränsning')),
                                    ],
                                    onChanged: (value) {
                                      dialogSetState(() {
                                        section['days'] = value;
                                      });
                                    },
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Avbryt'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A5BFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    setState(() {
                      _homeSections = editableSections;
                    });
                    await _saveSettings();
                    if (mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: const Text('Spara'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    if (!kIsWeb) HardwareKeyboard.instance.removeHandler(_onKey);
    _clockTimer?.cancel();
    _manualSyncTimer?.cancel();
    _homeSearchDebounce?.cancel();
    _tabController.dispose();
    _pathController.dispose();
    _homeSearchController.dispose();
    _tmdbKeyController.dispose();
    _omdbKeyController.dispose();
    _simklKeyController.dispose();
    _simklSecretController.dispose();
    _simklTokenController.dispose();
    _traktKeyController.dispose();
    _traktSecretController.dispose();
    _traktTokenController.dispose();
    _tmdbAuthController.dispose();
    _defaultSubLangController.dispose();
    _moviesScrollController.dispose();
    _showsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAllMedia() async {
    setState(() {
      _loadingMedia = true;
      _mediaError = null;
    });

    try {
      final movies = await widget.apiService.fetchMovies(mergeVersions: true);
      final shows = await widget.apiService.fetchShows();

      setState(() {
        _movies = movies;
        _shows = shows;
        _loadingMedia = false;
      });
    } catch (e) {
      setState(() {
        _mediaError = e.toString();
        _loadingMedia = false;
      });
    }
  }

  Future<void> _loadLibraryPaths() async {
    try {
      final paths = await widget.apiService.fetchLibraryPaths();
      setState(() {
        _libraryPaths = paths;
      });
    } catch (e) {
      debugPrint('Error loading library paths: $e');
    }
  }

  Future<void> _addNewPath(String folderPath, String type) async {
    try {
      await widget.apiService.addLibraryPath(folderPath, type);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lade till sökväg: "$folderPath" i ${type == 'Show' ? 'TV-Serier' : type == 'Movie' ? 'Filmer' : 'Musik'}'),
          backgroundColor: const Color(0xFF8A5BFF),
        ),
      );
      _loadLibraryPaths();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte lägga till sökväg: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _deletePath(String id) async {
    try {
      await widget.apiService.deleteLibraryPath(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sökväg borttagen'),
          backgroundColor: Color(0xFF8A5BFF),
        ),
      );
      _loadLibraryPaths();
      _loadAllMedia();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte ta bort sökväg: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _updatePath(String id, String newPath) async {
    try {
      final res = await widget.apiService.updateLibraryPath(id, newPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sökväg uppdaterad! Ändrade ${res['updatedCount'] ?? 0} filsökvägar i databasen.'),
          backgroundColor: const Color(0xFF8A5BFF),
        ),
      );
      _loadLibraryPaths();
      _loadAllMedia();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte uppdatera sökväg: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _showEditPathDialog(dynamic pathItem) async {
    final id = pathItem['id'];
    final oldPath = pathItem['path'];
    final type = pathItem['type'];
    
    final editController = TextEditingController(text: oldPath);
    bool isDialogBrowsing = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF15102A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
              title: Text('Redigera ${type == 'Show' ? 'TV-seriemapp' : type == 'Movie' ? 'Filmmapp' : 'Musikmapp'}'),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Att redigera denna sökväg uppdaterar alla matchande filer i databasen till det nya sökvägsprefixet.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: editController,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.black.withValues(alpha: 0.3),
                              hintText: 'Ange ny sökväg eller klicka Bläddra...',
                              hintStyle: const TextStyle(color: Colors.white24),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF8A5BFF), width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.04),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                              ),
                            ),
                            onPressed: isDialogBrowsing ? null : () async {
                              setDialogState(() {
                                isDialogBrowsing = true;
                              });
                              try {
                                final result = await widget.apiService.browseNativeDirectory();
                                if (result['path'] != null) {
                                  editController.text = result['path'];
                                }
                              } catch (e) {
                                debugPrint(e.toString());
                              } finally {
                                setDialogState(() {
                                  isDialogBrowsing = false;
                                });
                              }
                            },
                            icon: isDialogBrowsing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.folder_open_outlined, color: Color(0xFFB593FF)),
                            label: const Text('Bläddra...'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Avbryt'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A5BFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final newPath = editController.text.trim();
                    if (newPath.isNotEmpty) {
                      Navigator.of(context).pop();
                      await _updatePath(id, newPath);
                    }
                  },
                  child: const Text('Spara ändringar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _checkScannerStatus() async {
    try {
      final status = await widget.apiService.getLibraryStatus();
      setState(() {
        _isScanning = status['isScanning'] ?? false;
        _lastScanResult = status['lastScanResult'];
        _scanStatusText = _isScanning ? 'Skannar...' : 'Vilande';
        if (!_isScanning) {
          _currentlyScanningPath = null;
        }
      });
    } catch (e) {
      debugPrint('Error checking scanner status: $e');
    }
  }

  Future<void> _selectFolderNatively() async {
    setState(() {
      _isBrowsingDirectory = true;
    });

    try {
      final result = await widget.apiService.browseNativeDirectory();
      setState(() {
        _isBrowsingDirectory = false;
      });

      if (result['path'] != null) {
        setState(() {
          _pathController.text = result['path'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vald mapp: ${result['path']}'),
            backgroundColor: const Color(0xFF8A5BFF),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isBrowsingDirectory = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kunde inte öppna mappbläddraren: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _triggerScan() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ange en giltig sökväg att skanna')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _scanStatusText = 'Startar skanning...';
    });

    try {
      final response = await widget.apiService.triggerLibraryScan(
        path, 
        _selectedScanType,
        preferLocalNfo: _preferLocalNfo,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'Skanning startad!'),
          backgroundColor: const Color(0xFF8A5BFF),
        ),
      );
      
      // Periodically poll scanner status
      _pollScannerUntilFinished();
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte starta skanning: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _pollScannerUntilFinished() async {
    int attempts = 0;
    while (_isScanning && attempts < 30) {
      await Future.delayed(const Duration(seconds: 2));
      await _checkScannerStatus();
      attempts++;
      if (!_isScanning) {
        // Reload library if scan finished
        _loadAllMedia();
        break;
      }
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
              Color(0xFF0A0714), // Darkest space purple
              Color(0xFF120C28), // Deep royal navy
              Color(0xFF05030A), // Blackout edge
            ],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left sidebar navigation
            _buildSidebar(),

            // Main Content Area
            Expanded(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPersistentTopBar(),
                      const SizedBox(height: 18),
                      if (_selectedMediaId == null && _selectedPersonId == null) ...[
                        _buildHeader(),
                        // Kalendern har egna chips direkt under — minimal gap
                        SizedBox(height: _tabController.index == 3 ? 6 : 22),
                      ],
                      Expanded(
                        child: _selectedPersonId != null
                            ? PersonDetailsScreen(
                                personId: _selectedPersonId!,
                                apiService: widget.apiService,
                                onBack: _goBack,
                                onMediaSelected: (mediaId) {
                                  _navigateTo('media', mediaId);
                                },
                              )
                            : _selectedEpisode != null && _selectedEpisodeShowData != null
                                ? EpisodeDetailsScreen(
                                    key: ValueKey('ep_${_selectedEpisode!['id']}'),
                                    episode: _selectedEpisode!,
                                    showData: _selectedEpisodeShowData!,
                                    apiService: widget.apiService,
                                    onStatusChanged: _loadAllMedia,
                                    onPersonSelected: (personId) {
                                      setState(() {
                                        _selectedEpisode = null;
                                        _selectedEpisodeShowData = null;
                                      });
                                      _navigateTo('person', personId);
                                    },
                                    onNavigateToShow: () {
                                      final showId = _selectedEpisodeShowData!['id']?.toString();
                                      setState(() {
                                        _selectedEpisode = null;
                                        _selectedEpisodeShowData = null;
                                        _mediaInitialSeason = null;
                                      });
                                      if (showId != null) _navigateTo('media', showId);
                                    },
                                    onNavigateToSeason: (seasonNum) {
                                      final showId = _selectedEpisodeShowData!['id']?.toString();
                                      setState(() {
                                        _selectedEpisode = null;
                                        _selectedEpisodeShowData = null;
                                        _mediaInitialSeason = seasonNum;
                                      });
                                      if (showId != null) _navigateTo('media', showId);
                                    },
                                    onNavigateToEpisode: (ep) {
                                      setState(() {
                                        _selectedEpisode = ep;
                                      });
                                    },
                                  )
                                : _selectedMediaId != null
                                ? MediaDetailsScreen(
                                    key: ValueKey('${_selectedMediaId}_${_mediaInitialSeason ?? -1}'),
                                    mediaId: _selectedMediaId!,
                                    apiService: widget.apiService,
                                    onBack: _goBack,
                                    autoPlaySeconds: _autoPlaySecondsInNextOpen,
                                    onVideoPlayerClosed: _loadAllMedia,
                                    initialSeasonNumber: _mediaInitialSeason,
                                    onGenreSelected: (g) {
                                      setState(() {
                                        if (_selectedMediaId != null) _navHistory.add({'type': 'media', 'id': _selectedMediaId!});
                                        _selectedMediaId = null;
                                        _genreFilter = g;
                                        _showsGenreFilter = null;
                                        _keywordFilter = null;
                                      });
                                      try {
                                        _tabController.animateTo(1);
                                      } catch (_) {}
                                    },
                                    onShowGenreSelected: (g) {
                                      setState(() {
                                        if (_selectedMediaId != null) _navHistory.add({'type': 'media', 'id': _selectedMediaId!});
                                        _selectedMediaId = null;
                                        _showsGenreFilter = g;
                                        _genreFilter = null;
                                        _keywordFilter = null;
                                      });
                                      try {
                                        _tabController.animateTo(2);
                                      } catch (_) {}
                                    },
                                    onKeywordSelected: (k) {
                                      setState(() {
                                        _selectedMediaId = null;
                                        _keywordFilter = k;
                                        _genreFilter = null;
                                      });
                                      try {
                                        _tabController.animateTo(1);
                                      } catch (_) {}
                                    },
                                    onMediaSelected: (mediaId) {
                                      _navigateTo('media', mediaId);
                                    },
                                    onPersonSelected: (personId) {
                                      _navigateTo('person', personId);
                                    },
                                    onEdit: () => _openMediaEditor({'id': _selectedMediaId}),
                                    onContextMenu: (id, pos) => _openPosterActionsMenu({'id': id}, isHomeCard: false, globalPos: pos),
                                    onEpisodeSelected: (episode, showData) {
                                      setState(() {
                                        _navHistory.add({'type': 'media', 'id': _selectedMediaId!});
                                        _selectedEpisode = episode;
                                        _selectedEpisodeShowData = showData;
                                        _forwardHistory.clear();
                                      });
                                    },
                                    onEditEpisode: (epId, ep) => _openEpisodeEditor(epId, ep),
                                  )
                                : AnimatedBuilder(
                                    animation: _tabController,
                                    builder: (context, _) => IndexedStack(
                                      index: _tabController.index,
                                      children: [
                                        _buildHomeView(),
                                        _buildMoviesView(),
                                        _buildShowsView(),
                                        CalendarScreen(
                                          apiService: widget.apiService,
                                          initialSelectedDay: _calendarSelectedDay,
                                          onDayChanged: (d) { _calendarSelectedDay = d; },
                                          onShowTap: (showId) => _navigateTo('media', showId),
                                          onContextMenu: (localId, pos) => _openPosterActionsMenu(
                                            {'id': localId},
                                            isHomeCard: false,
                                            globalPos: pos,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      width: _isSidebarExpanded ? 280 : 80,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0B21).withValues(alpha: 0.6),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 35),

          if (_isSidebarExpanded) ...[
            // ── Expanded header ─────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo row + collapse button
                  Row(
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: InkWell(
                          onTap: _navigateHome,
                          borderRadius: BorderRadius.circular(10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.play_circle_fill, color: Color(0xFF8A5BFF), size: 26),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'LOOM',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  if (_serverName.isNotEmpty)
                                    Text(
                                      _serverName,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.38),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  Text(
                                    _currentUsername(),
                                    style: TextStyle(
                                      color: const Color(0xFFB593FF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: 'Fäll ihop menyn',
                        child: IconButton(
                          icon: const Icon(Icons.menu_open, color: Colors.white38),
                          onPressed: () => setState(() => _isSidebarExpanded = false),
                        ),
                      ),
                    ],
                  ),
                  // Separator under server name (or under LOOM if no server name)
                  const SizedBox(height: 12),
                  Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                  const SizedBox(height: 14),
                  // Navigation buttons (horizontal with optional clock)
                  _buildNavigationButtons(),
                ],
              ),
            ),
          ] else ...[
            // ── Collapsed header ────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Center(
                child: _buildNavigationButtons(), // renders vertical column + expand btn
              ),
            ),
          ],

          SizedBox(height: _isSidebarExpanded ? 8 : 16),

          // Navigation Items (Tab-based)
          _buildSidebarItem(0, Icons.home_outlined, Icons.home, 'Hem'),
          _buildSidebarItem(1, Icons.movie_outlined, Icons.movie, 'Filmer'),
          _buildSidebarItem(2, Icons.tv_outlined, Icons.tv, 'TV-Serier'),
          _buildSidebarItem(3, Icons.calendar_month_outlined, Icons.calendar_month, 'Kalender'),

          const Spacer(),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, IconData outlineIcon, IconData filledIcon, String title) {
    final isSelected = _tabController.index == index;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _isSidebarExpanded ? 20 : 12, vertical: 6),
      child: InkWell(
        onTap: () {
          if (index == 0) {
            _navigateHome();
          } else {
            setState(() {
              _tabController.animateTo(index);
              _selectedMediaId = null;
              _selectedPersonId = null;
              _selectedEpisode = null;
              _selectedEpisodeShowData = null;
            });
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: _isSidebarExpanded ? 20 : 0, vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF8A5BFF).withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF8A5BFF).withValues(alpha: 0.2) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? filledIcon : outlineIcon,
                color: isSelected ? const Color(0xFFB593FF) : Colors.white54,
                size: 22,
              ),
              if (_isSidebarExpanded) ...[
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 16,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfileCard() {
    final username = _currentUsername();
    final initials = _currentUserInitials();
    final role = widget.apiService.currentUserPayload?['role'] as String? ?? '';

    return Container(
      margin: EdgeInsets.symmetric(horizontal: _isSidebarExpanded ? 20 : 6),
      padding: EdgeInsets.all(_isSidebarExpanded ? 16 : 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          InkWell(
            onTap: _isSidebarExpanded ? null : _openUserPicker,
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.2),
              backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
              child: _avatarUrl == null
                  ? Text(
                      initials,
                      style: const TextStyle(
                          color: Color(0xFFB593FF), fontWeight: FontWeight.bold, fontSize: 14),
                    )
                  : null,
            ),
          ),
          if (_isSidebarExpanded) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    role,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.people_outline, color: Colors.white30, size: 20),
              onPressed: _openUserPicker,
              tooltip: 'Byt användare',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwitchUserButton() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _isSidebarExpanded ? 20 : 6),
      child: InkWell(
        onTap: _openUserPicker,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _isSidebarExpanded ? 16 : 0,
            vertical: 12,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              const Icon(Icons.people_outline, color: Colors.white38, size: 20),
              if (_isSidebarExpanded) ...[
                const SizedBox(width: 12),
                const Text(
                  'Byt användare',
                  style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    await widget.apiService.clearToken();
    if (!mounted) return;
    // Show profile picker — user must log in as someone
    _openUserPicker();
  }

  Widget _buildHeader() {
    final isHome = _tabController.index == 0;
    final title = isHome
        ? 'Hem'
        : _tabController.index == 1
            ? 'Filmer'
            : _tabController.index == 2
                ? 'TV-Serier'
                : _tabController.index == 3
                    ? 'Kalender'
                    : 'Inställningar';
    final subtitle = isHome
        ? 'Din personliga mediadashboard'
        : _tabController.index == 3
            ? 'Din TV- och film-guide'
            : _tabController.index == 4
                ? 'Hantera betrodda enheter och serverinställningar'
                : 'Hantera och strömma din mediesamling';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15),
                  ),
                ],
              ),
            ],
          ),
        ),
        Row(
          children: [
            if (_selectedMediaIds.isNotEmpty) ...[
              // Radera-knapp (admin only) till vänster om räknaren
              if (widget.apiService.currentUserPayload?['role'] == 'Admin')
                Tooltip(
                  message: 'Radera markerade',
                  child: GestureDetector(
                    onTap: _deleteSelectedItems,
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, color: Colors.redAccent, size: 16),
                          SizedBox(width: 5),
                          Text('Radera', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              // Räknare
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8A5BFF).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.checklist, color: Color(0xFFB593FF), size: 16),
                    const SizedBox(width: 8),
                    Text('${_selectedMediaIds.length} valda', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _clearMediaSelection,
                      child: const Icon(Icons.close, color: Colors.white54, size: 16),
                    ),
                  ],
                ),
              ),
            ],
            if (_isScanning)
              Container(
                margin: const EdgeInsets.only(right: 15),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFF59E0B))),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Skannar bibliotek',
                      style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  bool _isWithinDays(String? timestamp, int? days) {
    if (days == null || days <= 0) return true;
    if (timestamp == null || timestamp.isEmpty) return true;
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) return true;
    return DateTime.now().difference(parsed).inDays <= days;
  }

  List<dynamic> _getContinueWatchingMovies(List<dynamic> movies, int? days) {
    final filtered = movies.where((movie) {
      final metadata = movie['metadata'];
      if (metadata is! Map) return false;
      final progress = int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;
      if (progress <= 0) return false;
      return _isWithinDays(movie['last_watched_at']?.toString(), days);
    }).toList();

    filtered.sort((a, b) {
      final aTime = DateTime.tryParse(a['last_watched_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(b['last_watched_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return filtered;
  }

  // Returns shows with in-progress episodes, sorted by most recently watched.
  List<dynamic> _getContinueWatchingShows(List<dynamic> shows, int? days) {
    final filtered = shows.where((show) {
      final metadata = show['metadata'];
      // Check show-level metadata first
      if (metadata is Map) {
        final progress = int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;
        final hasLastEpisode = (metadata['last_watched_episode_id']?.toString() ?? '').isNotEmpty;
        if (progress > 0 || hasLastEpisode) {
          final lastAt = metadata['last_watched_at']?.toString() ?? show['last_watched_at']?.toString();
          return _isWithinDays(lastAt, days);
        }
      }
      // Fallback: check episodes list for any in-progress episode
      final episodes = show['episodes'];
      if (episodes is List) {
        return episodes.any((e) {
          final prog = int.tryParse(e['playback_progress']?.toString() ?? '0') ?? 0;
          final watched = e['is_watched'] == 1 || e['is_watched'] == true;
          return prog > 60 && !watched;
        });
      }
      return false;
    }).toList();

    filtered.sort((a, b) {
      final metaA = a['metadata'] is Map ? a['metadata'] as Map : <String, dynamic>{};
      final metaB = b['metadata'] is Map ? b['metadata'] as Map : <String, dynamic>{};
      final aTime = DateTime.tryParse(metaA['last_watched_at']?.toString() ?? '') ??
          DateTime.tryParse(a['last_watched_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(metaB['last_watched_at']?.toString() ?? '') ??
          DateTime.tryParse(b['last_watched_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return filtered;
  }

  // Returns a label like "S01E03 · Avsnitt titel" for the current in-progress episode of a show.
  String? _continueWatchingEpisodeLabel(dynamic show) {
    final metadata = show['metadata'];
    if (metadata is! Map) return null;
    final episodeId = metadata['last_watched_episode_id']?.toString();
    if (episodeId == null || episodeId.isEmpty) return null;
    final episodes = show['episodes'];
    if (episodes is! List) return null;
    for (final ep in episodes) {
      if (ep['id']?.toString() == episodeId) {
        final s = int.tryParse(ep['season_number']?.toString() ?? '0') ?? 0;
        final e = int.tryParse(ep['episode_number']?.toString() ?? '0') ?? 0;
        final epTitle = ep['title']?.toString() ?? '';
        final label = 'S${s.toString().padLeft(2, '0')}E${e.toString().padLeft(2, '0')}';
        return epTitle.isNotEmpty ? '$label · $epTitle' : label;
      }
    }
    return null;
  }

  List<dynamic> _getRecentlyWatchedShows(List<dynamic> shows) {
    final watched = shows.where((show) {
      final metadata = show['metadata'];
      // Check show-level last_watched_at
      if (metadata is Map) {
        final lastWatched = metadata['last_watched_at']?.toString() ?? show['last_watched_at']?.toString() ?? '';
        if (lastWatched.isNotEmpty) return true;
      }
      // Fallback: any episode is watched
      final episodes = show['episodes'];
      if (episodes is List) {
        return episodes.any((e) => e['is_watched'] == 1 || e['is_watched'] == true);
      }
      return false;
    }).toList();

    watched.sort((a, b) {
      final metaA = a['metadata'] is Map ? a['metadata'] as Map : <String, dynamic>{};
      final metaB = b['metadata'] is Map ? b['metadata'] as Map : <String, dynamic>{};
      final aTime = DateTime.tryParse(metaA['last_watched_at']?.toString() ?? '')
          ?? DateTime.tryParse(a['last_watched_at']?.toString() ?? '')
          ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(metaB['last_watched_at']?.toString() ?? '')
          ?? DateTime.tryParse(b['last_watched_at']?.toString() ?? '')
          ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return watched;
  }

  List<dynamic> _getRecentlyWatchedMovies(List<dynamic> movies) {
    final watched = movies.where((movie) {
      final metadata = movie['metadata'];
      return metadata is Map && metadata['watch_status'] == 'watched';
    }).toList();

    // Sort by when the film was COMPLETED (watch_completed_at), not just last touched
    watched.sort((a, b) {
      final metaA = a['metadata'] is Map ? a['metadata'] as Map : <String, dynamic>{};
      final metaB = b['metadata'] is Map ? b['metadata'] as Map : <String, dynamic>{};
      final aTime = DateTime.tryParse(metaA['watch_completed_at']?.toString() ?? '')
          ?? DateTime.tryParse(a['last_watched_at']?.toString() ?? '')
          ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(metaB['watch_completed_at']?.toString() ?? '')
          ?? DateTime.tryParse(b['last_watched_at']?.toString() ?? '')
          ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return watched;
  }

  Widget _buildHomeSectionHeader(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _buildHomePosterStrip(List<dynamic> items) {
    final stripHeight = 115.0 * _posterScale * 1.5 + 48;
    return SizedBox(
      height: stripHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) => _buildHomeCard(items[index]),
      ),
    );
  }

  // Continue-watching strip — shows an episode label below show titles.
  Widget _buildHomeContinueStrip(List<dynamic> items) {
    // Extra height for the episode label line
    final stripHeight = 115.0 * _posterScale * 1.5 + 62;
    return SizedBox(
      height: stripHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final isShow = (item['type']?.toString() ?? '') == 'Show';
          final epLabel = isShow ? _continueWatchingEpisodeLabel(item) : null;
          return _buildContinueWatchingCard(item, episodeLabel: epLabel);
        },
      ),
    );
  }

  Widget _buildContinueWatchingCard(dynamic item, {String? episodeLabel}) {
    final cardWidth = 115 * _posterScale;
    return SizedBox(
      width: cardWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: _buildUnifiedPosterCard(item, isHomeCard: true, posterPrefix: 'home', continueEpisodeLabel: episodeLabel),
      ),
    );
  }

  Widget _buildHomeComingSoonPlaceholder(String title) {
    return Container(
      height: 150,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$title kommer senare',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  void _handleHomeSearchChanged(String rawValue) {
    if (_homeSearchIgnoreChange) return;

    final query = rawValue.trim();

    _homeSearchDebounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _homeSearchIsOpen = false;
        _homeSearchLocalResults = [];
        _homeSearchTmdbResults = [];
        _homeSearchLoadingTmdb = false;
        _homeSearchSelectedIndex = -1;
      });
      return;
    }

    final localMatches = _findLocalHomeMatches(query);
    final localTop = localMatches.take(10).toList();
    _snapshotHomeSearch(query: query, localResults: localTop, tmdbResults: []);
    setState(() {
      _homeSearchIsOpen = true;
      _homeSearchLocalResults = localTop;
      _homeSearchTmdbResults = [];
      _homeSearchLoadingTmdb = query.length >= 3;
      _homeSearchSelectedIndex = localTop.isNotEmpty ? 0 : -1;
    });

    if (query.length < 3) {
      return;
    }

    _homeSearchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final currentNonce = ++_homeSearchRequestNonce;
      try {
        final tmdbResults = await widget.apiService.searchTmdbMovies(query);
        if (!mounted || currentNonce != _homeSearchRequestNonce) return;

        final localTmdbIds = _homeSearchLocalResults
            .map((m) => m['tmdb_id']?.toString())
            .whereType<String>()
            .toSet();

        final filteredTmdb = tmdbResults.where((result) {
          final tmdbId = result['id']?.toString();
          if (tmdbId == null) return false;
          return !localTmdbIds.contains(tmdbId);
        }).take(10).toList();

        _snapshotHomeSearch(query: query, localResults: _homeSearchLocalResults, tmdbResults: filteredTmdb);
        setState(() {
          _homeSearchTmdbResults = filteredTmdb;
          _homeSearchLoadingTmdb = false;
          final total = _homeSearchLocalResults.length + filteredTmdb.length;
          if (total == 0) {
            _homeSearchSelectedIndex = -1;
          } else if (_homeSearchSelectedIndex < 0 || _homeSearchSelectedIndex >= total) {
            _homeSearchSelectedIndex = 0;
          }
        });
      } catch (_) {
        if (!mounted || currentNonce != _homeSearchRequestNonce) return;
        _snapshotHomeSearch(query: query, localResults: _homeSearchLocalResults, tmdbResults: []);
        setState(() {
          _homeSearchTmdbResults = [];
          _homeSearchLoadingTmdb = false;
          _homeSearchSelectedIndex = _homeSearchLocalResults.isNotEmpty ? 0 : -1;
        });
      }
    });
  }

  void _snapshotHomeSearch({
    required String query,
    List<dynamic>? localResults,
    List<dynamic>? tmdbResults,
  }) {
    if (query.isEmpty) return;
    _homeSearchLastQuery = query;
    _homeSearchLastLocalResults = List<dynamic>.from(localResults ?? _homeSearchLocalResults);
    _homeSearchLastTmdbResults = List<dynamic>.from(tmdbResults ?? _homeSearchTmdbResults);
  }

  void _resetHomeSearchBox({bool preserveSnapshot = true}) {
    _homeSearchDebounce?.cancel();
    _homeSearchRequestNonce++;

    final currentQuery = _homeSearchController.text.trim();
    if (preserveSnapshot && currentQuery.isNotEmpty) {
      _snapshotHomeSearch(query: currentQuery);
    }

    _homeSearchIgnoreChange = true;
    _homeSearchController.clear();
    _homeSearchIgnoreChange = false;

    setState(() {
      _homeSearchIsOpen = false;
      _homeSearchLoadingTmdb = false;
      _homeSearchLocalResults = [];
      _homeSearchTmdbResults = [];
      _homeSearchSelectedIndex = -1;
    });
  }

  void _restoreHomeSearchBoxFromSnapshot() {
    if (_homeSearchLastQuery.isEmpty) return;

    _homeSearchIgnoreChange = true;
    _homeSearchController.value = TextEditingValue(
      text: _homeSearchLastQuery,
      selection: TextSelection(baseOffset: 0, extentOffset: _homeSearchLastQuery.length),
    );
    _homeSearchIgnoreChange = false;

    setState(() {
      _homeSearchIsOpen = true;
      _homeSearchLoadingTmdb = false;
      _homeSearchLocalResults = List<dynamic>.from(_homeSearchLastLocalResults);
      _homeSearchTmdbResults = List<dynamic>.from(_homeSearchLastTmdbResults);
      final total = _homeSearchLocalResults.length + _homeSearchTmdbResults.length;
      _homeSearchSelectedIndex = total > 0 ? 0 : -1;
    });
  }

  List<Map<String, dynamic>> _homeSearchSelectableItems() {
    final items = <Map<String, dynamic>>[];
    for (final movie in _homeSearchLocalResults) {
      items.add({'type': 'local', 'item': movie});
    }
    for (final movie in _homeSearchTmdbResults) {
      items.add({'type': 'tmdb', 'item': movie});
    }
    return items;
  }

  void _moveHomeSearchSelection(int delta) {
    final items = _homeSearchSelectableItems();
    if (items.isEmpty) return;

    setState(() {
      if (_homeSearchSelectedIndex == -1) {
        _homeSearchSelectedIndex = delta > 0 ? 0 : items.length - 1;
        return;
      }

      final nextIndex = (_homeSearchSelectedIndex + delta) % items.length;
      _homeSearchSelectedIndex = nextIndex < 0 ? items.length - 1 : nextIndex;
    });
  }

  void _openHomeSearchLocal(dynamic movie) {
    final id = movie['id']?.toString();
    if (id == null) return;
    _navigateTo('media', id);
    _resetHomeSearchBox();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _openHomeSearchTmdb(dynamic movie) {
    final tmdbId = movie['id']?.toString();
    if (tmdbId == null) return;
    _navigateTo('media', 'external_movie_$tmdbId');
    _resetHomeSearchBox();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool _hasModifier(LogicalKeyboardKey key) {
    return HardwareKeyboard.instance.logicalKeysPressed.contains(key);
  }

  void _toggleMediaSelection(dynamic item, int index) {
    final itemId = item['id']?.toString();
    if (itemId == null) return;

    final hasShift = _hasModifier(LogicalKeyboardKey.shiftLeft) || _hasModifier(LogicalKeyboardKey.shiftRight);
    final hasCtrl = _hasModifier(LogicalKeyboardKey.controlLeft) || _hasModifier(LogicalKeyboardKey.controlRight) || _hasModifier(LogicalKeyboardKey.metaLeft) || _hasModifier(LogicalKeyboardKey.metaRight);

    setState(() {
      if (hasShift && _lastSelectedMediaIndex != null) {
        final start = _lastSelectedMediaIndex! < index ? _lastSelectedMediaIndex! : index;
        final end = _lastSelectedMediaIndex! < index ? index : _lastSelectedMediaIndex!;
        final gridItems = _currentMediaGridItemsSnapshot;
        for (var i = start; i <= end; i++) {
          final id = gridItems[i]['id']?.toString();
          if (id != null) _selectedMediaIds.add(id);
        }
      } else if (hasCtrl) {
        if (_selectedMediaIds.contains(itemId)) {
          _selectedMediaIds.remove(itemId);
        } else {
          _selectedMediaIds.add(itemId);
        }
        _lastSelectedMediaIndex = index;
      } else {
        _selectedMediaIds
          ..clear()
          ..add(itemId);
        _lastSelectedMediaIndex = index;
      }
    });
  }

  List<dynamic> _currentMediaGridItemsSnapshot = [];

  Future<void> _deleteSelectedItems() async {
    if (_selectedMediaIds.isEmpty) return;
    final count = _selectedMediaIds.length;
    final confirmed = await _confirmAction(
      'Radera $count markerade?',
      'Titlarna flyttas till papperskorgen.',
    );
    if (!confirmed) return;
    final ids = List<String>.from(_selectedMediaIds);
    _clearMediaSelection();
    int failed = 0;
    for (final id in ids) {
      try {
        await widget.apiService.deleteMediaItem(id);
      } catch (_) {
        failed++;
      }
    }
    await _loadAllMedia();
    if (mounted && failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$failed titlar kunde inte raderas.')),
      );
    }
  }

  void _clearMediaSelection() {
    setState(() {
      _selectedMediaIds.clear();
      _lastSelectedMediaIndex = null;
    });
  }

  String _posterKeyFor(dynamic item, String prefix) {
    return '$prefix:${item['id']?.toString() ?? item['tmdb_id']?.toString() ?? item.hashCode.toString()}';
  }

  Future<void> _showInfoMessage(String message) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmAction(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF11151D),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: Text(message, style: const TextStyle(color: Colors.white70)),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Avbryt'),
            ),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Ja')),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<String?> _promptText(String title, String hint) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF11151D),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Avbryt'),
            ),
            ElevatedButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('OK')),
          ],
        );
      },
    );
    controller.dispose();
    return value;
  }

  Future<void> _openPosterActionsMenu(dynamic item, {required bool isHomeCard, Offset? globalPos, RelativeRect? position}) async {
    final itemId = item['id']?.toString();
    if (itemId == null) return;

    final metadata = (item['metadata'] is Map ? Map<String, dynamic>.from(item['metadata'] as Map) : <String, dynamic>{});
    final progress = int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;
    final watched = metadata['watch_status']?.toString() == 'watched';
    final isShow = (item['type']?.toString() ?? '') == 'Show';
    final isFavorite = item['is_favorite'] == true || item['is_favorite'] == 1;

    RelativeRect effectivePosition = position ?? RelativeRect.fromLTRB(MediaQuery.of(context).size.width / 2 - 10, MediaQuery.of(context).size.height / 2 - 10, 0, 0);
    if (globalPos != null) {
      final overlay = Overlay.of(context)?.context.findRenderObject() as RenderBox?;
      if (overlay != null) {
        effectivePosition = RelativeRect.fromRect(Rect.fromPoints(globalPos, globalPos), Offset.zero & overlay.size);
      }
    }

    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF11151D),
      position: effectivePosition,
      items: [
        if (progress > 0)
          const PopupMenuItem(value: 'clear_continue', child: Text('Ta bort från fortsätt titta')),
        PopupMenuItem(
          value: isFavorite ? 'unfavorite' : 'favorite',
          child: Row(children: [
            Icon(isFavorite ? Icons.star : Icons.star_border, size: 16, color: const Color(0xFFFFD700)),
            const SizedBox(width: 8),
            Text(isFavorite ? 'Ta bort från favoriter' : 'Lägg till i favoriter'),
          ]),
        ),
        const PopupMenuItem(value: 'playlist', child: Text('Lägg till på spellista')),
        PopupMenuItem(value: watched ? 'mark_unwatched' : 'mark_watched', child: Text(watched ? 'Markera som osedd' : 'Markera som sedd')),
        if (isShow) ...[
          const PopupMenuItem(value: 'mark_all_seasons_watched', child: Text('Markera alla säsonger som sedda')),
          const PopupMenuItem(value: 'mark_all_seasons_unwatched', child: Text('Markera alla säsonger som osedda')),
        ],
        const PopupMenuItem(value: 'refresh', child: Text('Uppdatera metadata')),
        if (!isShow) const PopupMenuItem(value: 'analyze', child: Text('Analysera')),
        const PopupMenuItem(value: 'edit', child: Text('Redigera')),
        const PopupMenuItem(value: 'fix_match', child: Text('Fixa matchning')),
        const PopupMenuItem(value: 'unmatch', child: Text('Ta bort matchning')),
        if (widget.apiService.currentUserPayload?['role'] == 'Admin')
          const PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              SizedBox(width: 8),
              Text('Ta bort', style: TextStyle(color: Colors.redAccent)),
            ]),
          ),
        const PopupMenuItem(value: 'info', child: Text('Info')),
        const PopupMenuItem(value: 'stats', child: Text('Visa statistik')),
      ],
    );

    if (selected == null) return;

    // Info is read-only — show dialog and return, skip _loadAllMedia.
    if (selected == 'info') {
      _showMediaInfoDialog(item);
      return;
    }

    if (selected == 'edit') {
      _openMediaEditor(item);
      return;
    }

    if (selected == 'stats') {
      _showMediaStatsDialog(item);
      return;
    }

    try {
      switch (selected) {
        case 'clear_continue':
          await widget.apiService.saveMediaMetadata(itemId, 'playback_progress', '0');
          break;
        case 'favorite':
          await widget.apiService.toggleFavorite(itemId, isFavorite: true);
          break;
        case 'unfavorite':
          await widget.apiService.toggleFavorite(itemId, isFavorite: false);
          break;
        case 'playlist':
          final playlistName = await _promptText('Lägg till på spellista', 'Spellistnamn');
          if (playlistName != null && playlistName.trim().isNotEmpty) {
            await widget.apiService.createPlaylistAndAddItem(playlistName.trim(), itemId);
          }
          break;
        case 'mark_watched':
          await widget.apiService.toggleSeenStatus(itemId, true);
          break;
        case 'mark_unwatched':
          await widget.apiService.toggleSeenStatus(itemId, false);
          break;
        case 'mark_all_seasons_watched':
          final episodes = (item['episodes'] as List? ?? []);
          final seasons = <int>{};
          for (final ep in episodes) {
            final s = int.tryParse(ep['season_number']?.toString() ?? '');
            if (s != null) seasons.add(s);
          }
          for (final s in seasons) {
            await widget.apiService.markSeasonSeen(itemId, s, true);
          }
          break;
        case 'mark_all_seasons_unwatched':
          final episodes = (item['episodes'] as List? ?? []);
          final seasons = <int>{};
          for (final ep in episodes) {
            final s = int.tryParse(ep['season_number']?.toString() ?? '');
            if (s != null) seasons.add(s);
          }
          for (final s in seasons) {
            await widget.apiService.markSeasonSeen(itemId, s, false);
          }
          break;
        case 'refresh':
          await widget.apiService.refreshMediaMetadata(itemId);
          break;
        case 'analyze':
          await widget.apiService.analyzeMediaItem(itemId);
          break;
        case 'fix_match':
          if (!context.mounted) break;
          await showDialog(
            context: context,
            barrierDismissible: true,
            builder: (_) => FixMatchDialog(
              mediaId: itemId,
              apiService: widget.apiService,
              currentTitle: item['title']?.toString() ?? '',
              currentYear: item['year']?.toString() ?? '',
              isShow: isShow,
              onMatchSuccess: () {},
            ),
          );
          break;
        case 'unmatch':
          await widget.apiService.unmatchMediaItem(itemId);
          break;
        case 'delete':
          if (await _confirmAction('Flytta till papperskorgen?', 'Ska detta media flyttas till papperskorgen?')) {
            await widget.apiService.deleteMediaItem(itemId);
          }
          break;
      }

      await _loadAllMedia();
    } catch (e) {
      await _showInfoMessage('Kunde inte utföra åtgärden: $e');
    }
  }

  void _showMediaInfoDialog(dynamic item) {
    final itemId = item['id']?.toString();
    if (itemId == null) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => MediaInfoDialog(
        mediaId: itemId,
        title: item['title']?.toString() ?? 'Media',
        apiService: widget.apiService,
      ),
    );
  }

  void _showMediaStatsDialog(dynamic item) {
    final itemId = item['id']?.toString();
    if (itemId == null) return;
    final mediaTitle = item['title']?.toString() ?? 'Statistik';
    final future = widget.apiService.fetchMediaPlays(itemId);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        backgroundColor: const Color(0xFF11151D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 540),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── rubrik ───────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                child: Row(children: [
                  const Icon(Icons.bar_chart_outlined, color: Color(0xFF8A5BFF), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Statistik — $mediaTitle',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ]),
              ),
              const Divider(color: Colors.white10, height: 1),
              // ── innehåll ─────────────────────────
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: future,
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))),
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Kunde inte hämta statistik:\n${snap.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                        ),
                      );
                    }
                    final data  = snap.data!;
                    final plays = (data['plays'] as List<dynamic>?) ?? [];
                    final mi    = data['mediaItem'] as Map<String, dynamic>? ?? {};
                    final isMovie = mi['type'] == 'Movie';

                    if (plays.isEmpty) {
                      return const Center(
                        child: Text('Ingen spelningshistorik för detta media',
                            style: TextStyle(color: Colors.white38, fontSize: 14)),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: plays.length,
                      itemBuilder: (ctx, i) {
                        final p        = plays[i] as Map<String, dynamic>;
                        final username = (p['username'] as String?) ?? '—';
                        final initials = username.isNotEmpty ? username[0].toUpperCase() : '?';

                        Widget trailing;
                        String? line1;
                        String line2;

                        if (isMovie) {
                          final isWatched = (p['is_watched'] as num?)?.toInt() == 1;
                          final durSec    = (p['total_duration_seconds'] as num?)?.toInt() ?? 0;
                          final posSec    = (p['last_position_seconds']  as num?)?.toInt() ?? 0;
                          final pct       = durSec > 0 ? (posSec / durSec * 100).round() : 0;
                          final updAt     = (p['updated_at']        as String?) ?? '';
                          final startAt   = (p['started_at_approx'] as String?) ?? '';
                          line1 = startAt.length >= 16
                              ? 'Start: ${startAt.substring(0, 16)}'
                              : startAt.isNotEmpty ? 'Start: $startAt' : null;
                          line2 = updAt.length >= 16
                              ? 'Slut: ${updAt.substring(0, 16)}'
                              : 'Slut: $updAt';
                          trailing = isWatched
                              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.check_circle, size: 14, color: Colors.greenAccent),
                                  SizedBox(width: 4),
                                  Text('Slutförd', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                                ])
                              : Text('$pct% sedd',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12));
                        } else {
                          final epCount   = (p['episode_count']       as num?)?.toInt() ?? 0;
                          final compCount = (p['completed_count']     as num?)?.toInt() ?? 0;
                          final totSec    = (p['totalSeconds']        as num?)?.toInt() ?? 0;
                          final lastAt    = (p['updated_at']          as String?) ?? '';
                          final firstAt   = (p['first_watched_approx'] as String?) ?? '';
                          line1 = firstAt.length >= 10 ? 'Startade: ${firstAt.substring(0, 10)}' : null;
                          line2 = '${lastAt.length >= 10 ? lastAt.substring(0, 10) : lastAt}'
                              '  •  $epCount avsnitt ($compCount klara)';
                          final hh = totSec ~/ 3600;
                          final mm = (totSec % 3600) ~/ 60;
                          trailing = Text('${hh}h ${mm}m',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600));
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                              child: Text(initials,
                                  style: const TextStyle(
                                      color: Color(0xFFB593FF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(username,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                                if (line1 != null)
                                  Text(line1,
                                      style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.38), fontSize: 11)),
                                Text(line2,
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.38), fontSize: 11)),
                              ]),
                            ),
                            const SizedBox(width: 8),
                            trailing,
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openEpisodeEditor(String epId, Map<String, dynamic> ep) async {
    final titleCtrl = TextEditingController(text: ep['title']?.toString() ?? '');
    final overviewCtrl = TextEditingController(text: ep['overview']?.toString() ?? ep['plot']?.toString() ?? '');
    final stillCtrl = TextEditingController(text: ep['still_path']?.toString() ?? '');
    final airDateCtrl = TextEditingController(text: ep['air_date']?.toString() ?? '');
    String activeTab = 'allmant';

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget buildField(String label, TextEditingController ctrl, {int maxLines = 1}) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      maxLines: maxLines,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF8A5BFF)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final tabs = [
            {'key': 'allmant', 'label': 'Allmänt'},
            {'key': 'affisch', 'label': 'Stillbild'},
          ];

          Widget content;
          if (activeTab == 'allmant') {
            content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildField('Titel', titleCtrl),
                buildField('Luftdatum', airDateCtrl),
                buildField('Beskrivning', overviewCtrl, maxLines: 5),
              ],
            );
          } else {
            content = buildField('Stillbild URL', stillCtrl);
          }

          return Dialog(
            backgroundColor: const Color(0xFF0D1117),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 760,
              height: 520,
              child: Row(
                children: [
                  Container(
                    width: 180,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                          child: Text('Redigera avsnitt', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        ...tabs.map((t) {
                          final isSelected = activeTab == t['key'];
                          return InkWell(
                            onTap: () => setDialogState(() => activeTab = t['key']!),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF8A5BFF).withValues(alpha: 0.15) : Colors.transparent,
                                border: Border(
                                  left: BorderSide(
                                    color: isSelected ? const Color(0xFF8A5BFF) : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Text(t['label']!, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 14)),
                            ),
                          );
                        }),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Lås ikon hindrar scanner från att skriva över fältet.',
                              style: TextStyle(color: Colors.white24, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: content,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white24),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Avbryt'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8A5BFF),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Spara'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (saved == true && mounted) {
      try {
        await widget.apiService.updateEpisodeFields(epId, {
          'title': titleCtrl.text.trim(),
          'overview': overviewCtrl.text.trim(),
          'still_path': stillCtrl.text.trim(),
          'air_date': airDateCtrl.text.trim(),
        });
        setState(() {});
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunde inte spara: $e')));
      }
    }
    titleCtrl.dispose();
    overviewCtrl.dispose();
    stillCtrl.dispose();
    airDateCtrl.dispose();
  }

  Future<void> _openMediaEditor(dynamic item) async {
    final itemId = item['id']?.toString();
    if (itemId == null) return;

    Map<String, dynamic> details = item is Map<String, dynamic> ? Map<String, dynamic>.from(item) : <String, dynamic>{};
    Map<String, dynamic> metadataState = {};

    try {
      details = Map<String, dynamic>.from(await widget.apiService.fetchMediaDetails(itemId));
      final state = await widget.apiService.fetchMediaMetadataState(itemId);
      final raw = state['metadata'];
      if (raw is Map) {
        metadataState = Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      if (details['metadata'] is Map) {
        metadataState = Map<String, dynamic>.from(details['metadata'] as Map);
      }
    }

    final titleController = TextEditingController(text: details['title']?.toString() ?? '');
    final sortTitleController = TextEditingController(text: metadataState['sort_title']?['value']?.toString() ?? '');
    final originalTitleController = TextEditingController(text: details['original_title']?.toString() ?? '');
    final editionController = TextEditingController(text: metadataState['edition']?['value']?.toString() ?? '');
    final releaseController = TextEditingController(text: details['year']?.toString() ?? '');
    final contentRatingController = TextEditingController(text: metadataState['content_rating']?['value']?.toString() ?? '');
    final ratingController = TextEditingController(text: metadataState['my_rating']?['value']?.toString() ?? '');
    final sloganController = TextEditingController(text: metadataState['tagline']?['value']?.toString() ?? '');
    final summaryController = TextEditingController(text: details['plot']?.toString() ?? metadataState['summary']?['value']?.toString() ?? '');
    final directorController = TextEditingController(text: details['director']?.toString() ?? '');
    final writersController = TextEditingController(text: metadataState['writers']?['value']?.toString() ?? '');
    final producersController = TextEditingController(text: metadataState['producers']?['value']?.toString() ?? '');
    final collectionsController = TextEditingController(text: details['collection_name']?.toString() ?? '');
    final labelsController = TextEditingController(text: metadataState['labels']?['value']?.toString() ?? '');
    final posterController = TextEditingController(text: details['poster_path']?.toString() ?? '');
    final fanartController = TextEditingController(text: details['fanart_path']?.toString() ?? '');
    final logoController = TextEditingController(text: metadataState['logo_path']?['value']?.toString() ?? '');
    final squareArtController = TextEditingController(text: metadataState['square_art']?['value']?.toString() ?? '');

    final lockState = <String, bool>{};
    for (final entry in metadataState.entries) {
      final value = entry.value;
      if (value is Map && value['is_locked'] != null) {
        lockState[entry.key] = value['is_locked'] == true;
      }
    }

    String activeTab = 'allmant';

    Future<void> saveEditor() async {
      await widget.apiService.updateMediaItemFields(itemId, {
        'title': titleController.text.trim(),
        'original_title': originalTitleController.text.trim(),
        'plot': summaryController.text.trim(),
        'year': int.tryParse(releaseController.text.trim()),
        'poster_path': posterController.text.trim(),
        'fanart_path': fanartController.text.trim(),
        'director': directorController.text.trim(),
        'collection_name': collectionsController.text.trim(),
      });

      final metadataUpdates = <String, dynamic>{
        'sort_title': sortTitleController.text.trim(),
        'edition': editionController.text.trim(),
        'content_rating': contentRatingController.text.trim(),
        'my_rating': ratingController.text.trim(),
        'tagline': sloganController.text.trim(),
        'summary': summaryController.text.trim(),
        'writers': writersController.text.trim(),
        'producers': producersController.text.trim(),
        'collections': collectionsController.text.trim(),
        'labels': labelsController.text.trim(),
        'logo_path': logoController.text.trim(),
        'square_art': squareArtController.text.trim(),
      };

      for (final entry in metadataUpdates.entries) {
        await widget.apiService.saveMediaMetadata(itemId, entry.key, entry.value);
      }

      for (final entry in lockState.entries) {
        await widget.apiService.setMediaMetadataLock(itemId, entry.key, entry.value);
      }
    }

    StreamSubscription<html.ClipboardEvent>? clipboardPasteSubscription;
    TextEditingController? activeImageController;
    String? activeImageKey;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final dialogId = DateTime.now().microsecondsSinceEpoch;
          final dropZoneViewTypes = <String, String>{};

          return StatefulBuilder(
            builder: (context, dialogSetState) {
              if (clipboardPasteSubscription == null) {
                clipboardPasteSubscription = html.document.onPaste.listen((event) async {
                  final files = event.clipboardData?.files;
                  final imageFile = (files == null || files.isEmpty) ? null : files.firstWhere(
                    (file) => file.type.startsWith('image/'),
                    orElse: () => files.first,
                  );

                  if (imageFile == null || !imageFile.type.startsWith('image/')) return;

                  final controller = activeImageController;
                  final key = activeImageKey;
                  if (controller == null || key == null || lockState[key] == true) return;

                  event.preventDefault();
                  final reader = html.FileReader();
                  reader.readAsDataUrl(imageFile);
                  await reader.onLoadEnd.first;
                  final dataUrl = reader.result as String?;
                  if (dataUrl != null && dataUrl.isNotEmpty) {
                    dialogSetState(() {
                      controller.text = dataUrl;
                    });
                  }
                });
              }

              Widget imageActionButton(IconData icon, String tooltip, VoidCallback? onPressed) {
                return IconButton(
                  tooltip: tooltip,
                  icon: Icon(icon, color: Colors.white54),
                  onPressed: onPressed,
                );
              }

              void pickImageFromDisk(TextEditingController controller) {
                final input = html.FileUploadInputElement()..accept = 'image/*';
                input.onChange.listen((_) async {
                  final file = input.files?.firstOrNull;
                  if (file == null) return;

                  final reader = html.FileReader();
                  reader.readAsDataUrl(file);
                  await reader.onLoadEnd.first;
                  final dataUrl = reader.result as String?;
                  if (dataUrl != null && dataUrl.isNotEmpty) {
                    dialogSetState(() {
                      controller.text = dataUrl;
                    });
                  }
                });
                input.click();
              }

              String imageDropZoneViewType(String key, TextEditingController controller) {
                return dropZoneViewTypes.putIfAbsent(key, () {
                  final viewType = 'loom-image-drop-$dialogId-$key';
                  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
                    final dropZone = html.DivElement()
                      ..style.display = 'flex'
                      ..style.alignItems = 'center'
                      ..style.justifyContent = 'center'
                      ..style.minHeight = '104px'
                      ..style.padding = '16px'
                      ..style.borderRadius = '12px'
                      ..style.border = '1px dashed rgba(255, 255, 255, 0.20)'
                      ..style.backgroundColor = '#171C26'
                      ..style.color = 'rgba(255, 255, 255, 0.70)'
                      ..style.fontFamily = 'inherit'
                      ..style.fontSize = '13px'
                      ..style.textAlign = 'center'
                      ..style.cursor = 'copy'
                      ..text = 'Dra en bildfil hit eller välj fil knappen nedan';

                    dropZone.onDragOver.listen((event) {
                      event.preventDefault();
                      event.stopPropagation();
                    });

                    dropZone.onDrop.listen((event) async {
                      event.preventDefault();
                      event.stopPropagation();
                      if (lockState[key] == true) return;
                      
                      final files = event.dataTransfer.files;
                      final file = files == null || files.isEmpty ? null : files.first;
                      if (file == null || !file.type.startsWith('image/')) return;
                      
                      final reader = html.FileReader();
                      reader.readAsDataUrl(file);
                      await reader.onLoadEnd.first;
                      final dataUrl = reader.result as String?;
                      if (dataUrl != null && dataUrl.isNotEmpty) {
                        dialogSetState(() {
                          controller.text = dataUrl;
                        });
                      }
                    });
                    return dropZone;
                  });
                  return viewType;
                });
              }
            Widget field(String key, TextEditingController controller, {int maxLines = 1, String? hint}) {
              final isLocked = lockState[key] == true;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: Icon(isLocked ? Icons.lock : Icons.lock_open, color: isLocked ? const Color(0xFF8A5BFF) : Colors.white54),
                    onPressed: () => dialogSetState(() => lockState[key] = !isLocked),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      maxLines: maxLines,
                      onChanged: (_) => dialogSetState(() {}),
                      onTap: () {
                        activeImageController = controller;
                        activeImageKey = key;
                      },
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: hint,
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF171C26),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  imageActionButton(
                    Icons.content_paste,
                    'Klistra in från urklipp',
                    isLocked ? null : () async {
                      final clipboardData = await html.window.navigator.clipboard?.readText();
                      final pastedText = clipboardData?.trim();
                      if (pastedText == null || pastedText.isEmpty) return;
                      dialogSetState(() {
                        controller.text = pastedText;
                      });
                    },
                  ),
                  imageActionButton(
                    Icons.clear,
                    'Rensa fält',
                    isLocked || controller.text.isEmpty ? null : () {
                      dialogSetState(() {
                        controller.clear();
                      });
                    },
                  ),
                ],
              );
            }

            Widget imageField(String key, TextEditingController controller, String hint, {String? previewLabel}) {
              final isLocked = lockState[key] == true;
              final value = controller.text.trim();
              final hasPreview = value.isNotEmpty && (value.startsWith('http') || value.startsWith('data:image/'));
              final dropZoneViewType = imageDropZoneViewType(key, controller);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  field(key, controller, hint: hint),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 104,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AbsorbPointer(
                        absorbing: isLocked,
                        child: HtmlElementView(viewType: dropZoneViewType),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: isLocked ? null : () => pickImageFromDisk(controller),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Välj bildfil'),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Lokal fil sparas som data-URL i metadata.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                      ),
                    ],
                  ),
                  if (hasPreview) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171C26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(previewLabel ?? 'Förhandsvisning', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  value,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => launchUrl(Uri.parse(value), mode: LaunchMode.externalApplication),
                                child: const Text('Öppna'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: value.startsWith('data:image/')
                                  ? Builder(
                                      builder: (context) {
                                        try {
                                          final uriData = UriData.parse(value);
                                          return Image.memory(
                                            uriData.contentAsBytes(),
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Container(
                                                color: const Color(0xFF10151E),
                                                alignment: Alignment.center,
                                                padding: const EdgeInsets.all(16),
                                                child: const Text('Förhandsvisning kunde inte laddas', style: TextStyle(color: Colors.white54)),
                                              );
                                            },
                                          );
                                        } catch (_) {
                                          return Container(
                                            color: const Color(0xFF10151E),
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.all(16),
                                            child: const Text('Förhandsvisning kunde inte laddas', style: TextStyle(color: Colors.white54)),
                                          );
                                        }
                                      },
                                    )
                                  : Image.network(
                                      value,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: const Color(0xFF10151E),
                                          alignment: Alignment.center,
                                          padding: const EdgeInsets.all(16),
                                          child: const Text('Förhandsvisning kunde inte laddas', style: TextStyle(color: Colors.white54)),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            }

            return Dialog(
              backgroundColor: const Color(0xFF0F131A),
              insetPadding: const EdgeInsets.all(20),
              child: SizedBox(
                width: 1100,
                height: 760,
                child: Row(
                  children: [
                    Container(
                      width: 220,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF11151D),
                        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Redigera metadata', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          for (final tab in const [
                            ('allmant', 'Allmänt'),
                            ('etiketter', 'Etiketter'),
                            ('affisch', 'Affisch'),
                            ('bakgrund', 'Bakgrund'),
                            ('logo', 'Logo'),
                            ('square', 'Square Art'),
                            ('info', 'Info'),
                          ])
                            Material(
                              type: MaterialType.transparency,
                              child: ListTile(
                                dense: true,
                                selected: activeTab == tab.$1,
                                selectedTileColor: const Color(0xFF8A5BFF).withValues(alpha: 0.16),
                                title: Text(tab.$2, style: const TextStyle(color: Colors.white)),
                                onTap: () => dialogSetState(() => activeTab = tab.$1),
                              ),
                            ),
                          const Spacer(),
                          Text('Lås ikon hindrar scanner från att skriva över fältet.', style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Builder(
                                  builder: (context) {
                                    if (activeTab == 'allmant') {
                                      return Column(
                                        children: [
                                          field('title', titleController, hint: 'Titel'),
                                          const SizedBox(height: 12),
                                          field('sort_title', sortTitleController, hint: 'Sortera titel'),
                                          const SizedBox(height: 12),
                                          field('original_title', originalTitleController, hint: 'Originaltitel'),
                                          const SizedBox(height: 12),
                                          field('edition', editionController, hint: 'Edition'),
                                          const SizedBox(height: 12),
                                          field('originally_available', releaseController, hint: 'Ursprungligen tillgänglig / år'),
                                          const SizedBox(height: 12),
                                          field('content_rating', contentRatingController, hint: 'Innehållsklassificering'),
                                          const SizedBox(height: 12),
                                          field('my_rating', ratingController, hint: 'Mitt betyg'),
                                          const SizedBox(height: 12),
                                          field('tagline', sloganController, hint: 'Slogan'),
                                          const SizedBox(height: 12),
                                          field('summary', summaryController, maxLines: 5, hint: 'Sammanfattning'),
                                        ],
                                      );
                                    }

                                    if (activeTab == 'etiketter') {
                                      return Column(
                                        children: [
                                          field('director', directorController, hint: 'Regissörer ; separerade'),
                                          const SizedBox(height: 12),
                                          field('writers', writersController, hint: 'Författare ; separerade'),
                                          const SizedBox(height: 12),
                                          field('producers', producersController, hint: 'Producent ; separerade'),
                                          const SizedBox(height: 12),
                                          field('collections', collectionsController, hint: 'Samlingar ; separerade'),
                                          const SizedBox(height: 12),
                                          field('labels', labelsController, hint: 'Etiketter ; separerade'),
                                        ],
                                      );
                                    }

                                    if (activeTab == 'affisch') {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          imageField('poster_path', posterController, 'Affisch URL', previewLabel: 'Affischförhandsvisning'),
                                          const SizedBox(height: 12),
                                          const Text('Drag & drop / clipboard upload kommer i nästa steg.', style: TextStyle(color: Colors.white54)),
                                        ],
                                      );
                                    }

                                    if (activeTab == 'bakgrund') {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          imageField('fanart_path', fanartController, 'Bakgrund URL', previewLabel: 'Bakgrundförhandsvisning'),
                                          const SizedBox(height: 12),
                                          const Text('Drag & drop / clipboard upload kommer i nästa steg.', style: TextStyle(color: Colors.white54)),
                                        ],
                                      );
                                    }

                                    if (activeTab == 'logo') {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          imageField('logo_path', logoController, 'Logo URL', previewLabel: 'Logoförhandsvisning'),
                                          const SizedBox(height: 12),
                                          const Text('Drag & drop / clipboard upload kommer i nästa steg.', style: TextStyle(color: Colors.white54)),
                                        ],
                                      );
                                    }

                                    if (activeTab == 'square') {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          imageField('square_art', squareArtController, 'Square Art URL', previewLabel: 'Square Art-förhandsvisning'),
                                          const SizedBox(height: 12),
                                          const Text('Drag & drop / clipboard upload kommer i nästa steg.', style: TextStyle(color: Colors.white54)),
                                        ],
                                      );
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Sökväg: ${details['file_path'] ?? '-'}', style: const TextStyle(color: Colors.white70)),
                                        const SizedBox(height: 8),
                                        Text('Filnamn: ${details['title'] ?? '-'}', style: const TextStyle(color: Colors.white70)),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('Avbryt', style: TextStyle(color: Colors.white70)),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8A5BFF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  ),
                                  onPressed: () async {
                                    try {
                                      await saveEditor();
                                      if (context.mounted) {
                                        Navigator.pop(dialogContext);
                                        await _loadAllMedia();
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunde inte spara: $e')));
                                      }
                                    }
                                  },
                                  child: const Text('Spara', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
            );
          },
        );
      },
    );
    } finally {
      await clipboardPasteSubscription?.cancel();
    }

    titleController.dispose();
    sortTitleController.dispose();
    originalTitleController.dispose();
    editionController.dispose();
    releaseController.dispose();
    contentRatingController.dispose();
    ratingController.dispose();
    sloganController.dispose();
    summaryController.dispose();
    directorController.dispose();
    writersController.dispose();
    producersController.dispose();
    collectionsController.dispose();
    labelsController.dispose();
    posterController.dispose();
    fanartController.dispose();
    logoController.dispose();
    squareArtController.dispose();
  }

  Widget _buildPosterActionButton({required IconData icon, VoidCallback? onPressed, GestureTapDownCallback? onTapDown}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        onTapDown: onTapDown,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Future<void> _handlePosterTap(dynamic item, {required bool isHomeCard}) async {
    final itemId = item['id']?.toString();
    if (itemId == null) return;
    // Always open media details — play/resume is triggered via the hover play button.
    _navigateTo('media', itemId);
  }

  // Called by the hover play icon on any card. Shows resume dialog if progress exists,
  // then pushes VideoPlayerScreen directly so the user returns to Home when done.
  void _handlePlayTap(dynamic item) {
    final itemId = item['id']?.toString();
    if (itemId == null) return;

    final metadata = item['metadata'] is Map ? item['metadata'] as Map : <String, dynamic>{};
    final progress = int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;

    void pushPlayer(int fromSeconds) {
      final mediaData = item is Map<String, dynamic> ? Map<String, dynamic>.from(item) : null;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            mediaId: itemId,
            apiService: widget.apiService,
            mediaData: mediaData,
            startFromSeconds: fromSeconds,
          ),
        ),
      ).then((_) {
        // Reload so "Fortsätt titta" reflects the updated position and order.
        _loadAllMedia();
      });
    }

    if (progress > 0) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => ResumePlaybackModal(
          savedPositionSeconds: progress,
          onResume: () {
            Navigator.pop(dialogContext);
            pushPlayer(progress);
          },
          onStartOver: () {
            Navigator.pop(dialogContext);
            pushPlayer(0);
          },
        ),
      );
    } else {
      pushPlayer(0);
    }
  }

  void _activateHomeSearchSelectionOrSubmit() {
    final items = _homeSearchSelectableItems();

    if (_homeSearchSelectedIndex >= 0 && _homeSearchSelectedIndex < items.length) {
      final selected = items[_homeSearchSelectedIndex];
      if (selected['type'] == 'local') {
        _openHomeSearchLocal(selected['item']);
      } else {
        _openHomeSearchTmdb(selected['item']);
      }
      return;
    }

    _submitHomeSearchToMoviesTab();
  }

  List<dynamic> _findLocalHomeMatches(String query) {
    final q = query.toLowerCase();
    final allMedia = [..._movies, ..._shows];
    final candidates = allMedia.where((m) {
      final title = (m['title'] ?? '').toString().toLowerCase();
      final originalTitle = (m['original_title'] ?? '').toString().toLowerCase();
      final year = (m['year'] ?? '').toString().toLowerCase();
      return title.contains(q) || originalTitle.contains(q) || year.contains(q);
    }).toList();

    int score(dynamic m) {
      final title = (m['title'] ?? '').toString().toLowerCase();
      final originalTitle = (m['original_title'] ?? '').toString().toLowerCase();
      final year = (m['year'] ?? '').toString().toLowerCase();
      if (title == q || originalTitle == q) return 0;
      if (title.startsWith(q) || originalTitle.startsWith(q)) return 1;
      if (year == q) return 2;
      return 3;
    }

    candidates.sort((a, b) {
      final scoreCmp = score(a).compareTo(score(b));
      if (scoreCmp != 0) return scoreCmp;
      final ay = int.tryParse((a['year'] ?? '0').toString()) ?? 0;
      final by = int.tryParse((b['year'] ?? '0').toString()) ?? 0;
      return by.compareTo(ay);
    });

    return candidates;
  }

  void _submitHomeSearchToMoviesTab() {
    final query = _homeSearchController.text.trim();
    if (query.isEmpty) return;
    _snapshotHomeSearch(query: query);
    setState(() {
      _moviesSearchQuery = query;
      _genreFilter = null;
      _keywordFilter = null;
    });
    _tabController.animateTo(1);
    _resetHomeSearchBox(preserveSnapshot: false);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Widget _buildHomeSearchBox() {
    final hasQuery = _homeSearchController.text.trim().isNotEmpty;
    final hasResults = _homeSearchLocalResults.isNotEmpty || _homeSearchTmdbResults.isNotEmpty || _homeSearchLoadingTmdb;

    return TextFieldTapRegion(
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;

          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _resetHomeSearchBox();
            FocusManager.instance.primaryFocus?.unfocus();
            return KeyEventResult.handled;
          }

          if (!hasQuery || !_homeSearchIsOpen) return KeyEventResult.ignored;

          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _moveHomeSearchSelection(1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _moveHomeSearchSelection(-1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _activateHomeSearchSelectionOrSubmit();
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: OverlayPortal(
          controller: _searchOverlayController,
          overlayChildBuilder: (ctx) {
            if (!_homeSearchIsOpen || !hasQuery) return const SizedBox.shrink();
            final RenderBox? box = _searchBoxKey.currentContext?.findRenderObject() as RenderBox?;
            final width = box?.size.width ?? 700.0;
            return CompositedTransformFollower(
              link: _searchLayerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: const Offset(0, 8),
              child: Align(
                alignment: Alignment.topLeft,
                child: TextFieldTapRegion(
                  child: SizedBox(
                    width: width,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 340),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141820),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: hasResults
                          ? ListView(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shrinkWrap: true,
                              children: [
                                ...List.generate(_homeSearchLocalResults.length, (index) {
                                  final movie = _homeSearchLocalResults[index];
                                  return _buildHomeSearchLocalRow(movie, isSelected: _homeSearchSelectedIndex == index);
                                }),
                                if (_homeSearchLocalResults.isNotEmpty && (_homeSearchTmdbResults.isNotEmpty || _homeSearchLoadingTmdb))
                                  _buildHomeSearchSeparator('Från TMDB'),
                                ...List.generate(_homeSearchTmdbResults.length, (index) {
                                  final movie = _homeSearchTmdbResults[index];
                                  final selectedIndex = _homeSearchLocalResults.length + index;
                                  return _buildHomeSearchTmdbRow(movie, isSelected: _homeSearchSelectedIndex == selectedIndex);
                                }),
                                if (_homeSearchLoadingTmdb)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8A5BFF)),
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                              child: Text('Inga träffar', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: CompositedTransformTarget(
            link: _searchLayerLink,
            child: Container(
              key: _searchBoxKey,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: TextField(
                controller: _homeSearchController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                onChanged: _handleHomeSearchChanged,
                onSubmitted: (_) => _activateHomeSearchSelectionOrSubmit(),
                onTap: () {
                  if (_homeSearchController.text.trim().isEmpty && _homeSearchLastQuery.isNotEmpty) {
                    _restoreHomeSearchBoxFromSnapshot();
                    return;
                  }

                  final current = _homeSearchController.text;
                  if (current.isNotEmpty) {
                    _homeSearchController.selection = TextSelection(baseOffset: 0, extentOffset: current.length);
                  }

                  setState(() {
                    _homeSearchIsOpen = current.trim().isNotEmpty;
                    if (_homeSearchIsOpen && _homeSearchLocalResults.isEmpty && _homeSearchTmdbResults.isEmpty && _homeSearchLastQuery == current.trim()) {
                      _homeSearchLocalResults = List<dynamic>.from(_homeSearchLastLocalResults);
                      _homeSearchTmdbResults = List<dynamic>.from(_homeSearchLastTmdbResults);
                    }
                  });
                },
                onTapOutside: (_) {
                  _resetHomeSearchBox();
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                decoration: InputDecoration(
                  hintText: 'Sök filmer lokalt och i TMDB...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white60, size: 20),
                  suffixIcon: hasQuery
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                          onPressed: () {
                            _resetHomeSearchBox(preserveSnapshot: false);
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeSearchSeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.10))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.10))),
        ],
      ),
    );
  }

  Widget _buildHomeSearchLocalRow(dynamic movie, {bool isSelected = false}) {
    final title = (movie['title'] ?? 'Okänd titel').toString();
    final yearRaw = movie['year']?.toString();
    final year = (yearRaw != null && yearRaw.isNotEmpty) ? ' ($yearRaw)' : '';
    final poster = movie['poster_path']?.toString();
    final metadata = movie['metadata'];
    String resolutionText = '';
    if (metadata is Map) {
      final resolutionValue = metadata['resolution'] ?? metadata['video_resolution'] ?? metadata['quality'];
      if (resolutionValue != null) {
        resolutionText = resolutionValue.toString().trim();
      }
    }

    return InkWell(
      onTap: () => _openHomeSearchLocal(movie),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8A5BFF).withValues(alpha: 0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            _buildHomeSearchPoster(poster),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$title$year',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            if (resolutionText.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                resolutionText,
                style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHomeSearchTmdbRow(dynamic movie, {bool isSelected = false}) {
    final title = (movie['title'] ?? 'Okänd titel').toString();
    final yearRaw = movie['year']?.toString();
    final year = (yearRaw != null && yearRaw.isNotEmpty && yearRaw != 'null') ? ' ($yearRaw)' : '';
    final poster = movie['poster_path']?.toString();

    return InkWell(
      onTap: () => _openHomeSearchTmdb(movie),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8A5BFF).withValues(alpha: 0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            _buildHomeSearchPoster(poster),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$title$year',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeSearchPoster(String? url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 36,
        height: 52,
        color: Colors.white12,
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.movie, color: Colors.white30, size: 16),
              )
            : const Icon(Icons.movie, color: Colors.white30, size: 16),
      ),
    );
  }

  Widget _buildGenreFilterBadge() {
    final activeFilter = _keywordFilter != null
        ? 'Nyckelord: $_keywordFilter'
        : (_showsGenreFilter != null ? 'Genre: $_showsGenreFilter' : 'Genre: $_genreFilter');
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Chip(
        backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
        side: const BorderSide(color: Color(0xFF8A5BFF)),
        label: Text(activeFilter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        deleteIcon: const Icon(Icons.close, color: Colors.white, size: 18),
        onDeleted: () {
          setState(() {
            _genreFilter = null;
            _showsGenreFilter = null;
            _keywordFilter = null;
          });
        },
      ),
    );
  }


  Widget _buildHomeView() {
    final recentMovies = (List<dynamic>.from(_movies)
          ..sort((a, b) {
            final aTime = DateTime.tryParse(a['added_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = DateTime.tryParse(b['added_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          }))
        .take(12)
        .toList();
    final recentShows = (List<dynamic>.from(_shows)
          ..sort((a, b) {
            final aTime = DateTime.tryParse(a['added_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = DateTime.tryParse(b['added_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          }))
        .take(12)
        .toList();
    final watchedMovies = _getRecentlyWatchedMovies(_movies).take(12).toList();
    final watchedShows = _getRecentlyWatchedShows(_shows).take(12).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final section in _homeSections) ...[
            if (section['visible'] != false)
              Builder(
                builder: (context) {
                  final sectionId = section['id']?.toString() ?? '';
                  final title = section['title']?.toString() ?? '';
                  final comingSoon = section['comingSoon'] == true;
                  final days = section['days'] as int?;

                  if (sectionId == 'continue_watching') {
                    final continueMovies = _getContinueWatchingMovies(_movies, days).take(8).toList();
                    final continueShows = _getContinueWatchingShows(_shows, days).take(8).toList();
                    // Merge and re-sort by last watched
                    final allContinue = [...continueMovies, ...continueShows];
                    allContinue.sort((a, b) {
                      final metaA = a['metadata'] is Map ? a['metadata'] as Map : <String, dynamic>{};
                      final metaB = b['metadata'] is Map ? b['metadata'] as Map : <String, dynamic>{};
                      final aTime = DateTime.tryParse(metaA['last_watched_at']?.toString() ?? '') ?? DateTime.tryParse(a['last_watched_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
                      final bTime = DateTime.tryParse(metaB['last_watched_at']?.toString() ?? '') ?? DateTime.tryParse(b['last_watched_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
                      return bTime.compareTo(aTime);
                    });
                    final continueWatching = allContinue.take(12).toList();
                    if (continueWatching.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHomeSectionHeader(title, subtitle: days == null ? 'Ingen begränsning' : 'Senaste $days dagar'),
                          _buildHomeContinueStrip(continueWatching),
                        ],
                      ),
                    );
                  }

                  if (sectionId == 'recent_movies') {
                    if (recentMovies.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHomeSectionHeader(title),
                          _buildHomePosterStrip(recentMovies),
                        ],
                      ),
                    );
                  }

                  if (sectionId == 'recent_shows') {
                    if (recentShows.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHomeSectionHeader(title),
                          _buildHomePosterStrip(recentShows),
                        ],
                      ),
                    );
                  }

                  if (sectionId == 'recent_watched_movies') {
                    if (watchedMovies.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHomeSectionHeader(title),
                          _buildHomePosterStrip(watchedMovies),
                        ],
                      ),
                    );
                  }

                  if (sectionId == 'recent_watched_shows') {
                    if (watchedShows.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHomeSectionHeader(title),
                          _buildHomePosterStrip(watchedShows),
                        ],
                      ),
                    );
                  }

                  if (comingSoon) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHomeSectionHeader(title),
                          _buildHomeComingSoonPlaceholder(title),
                        ],
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
          ],

          if (_loadingMedia)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(60),
                child: CircularProgressIndicator(color: Color(0xFF8A5BFF)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHomeCard(dynamic movie) {
    final cardWidth = 115 * _posterScale;
    return SizedBox(
      width: cardWidth,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: _buildUnifiedPosterCard(movie, isHomeCard: true, posterPrefix: 'home'),
      ),
    );
  }

  /// Normalise any resolution string to a human-friendly label.
  /// Handles height-only ("1080p"), dimension pairs ("1920x800"), and keywords ("4K").
  /// For dimension pairs, both width AND height are checked so Scope-format films
  /// like 1920×800 are correctly reported as 1080P (not 720P).
  static String? _normaliseResolution(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final u = s.toUpperCase();

    // Try to parse as WxH (e.g. "1920X800" or "1920x1080")
    final dimMatch = RegExp(r'^(\d+)[Xx](\d+)$').firstMatch(s);
    if (dimMatch != null) {
      final w = int.parse(dimMatch.group(1)!);
      final h = int.parse(dimMatch.group(2)!);
      if (w >= 3200 || h >= 2000) return '4K';
      if (w >= 1900 || h >= 1000) return '1080P';
      if (w >= 1100 || h >= 650)  return '720P';
      if (w >= 700  || h >= 420)  return '480P';
      return '${h}P';
    }

    if (u.contains('4K') || u.contains('2160') || u.contains('3840')) return '4K';
    if (u.contains('1080')) return '1080P';
    if (u.contains('720'))  return '720P';
    if (u.contains('480'))  return '480P';
    if (u.contains('360'))  return '360P';
    return u;
  }

  /// Shared card widget used for both the home-strip and the movies/shows grid.
  Widget _buildUnifiedPosterCard(
    dynamic item, {
    required bool isHomeCard,
    int index = 0,
    required String posterPrefix,
    String? continueEpisodeLabel,
  }) {
    final title = (_titleDisplayStyle == 'Original' &&
            item['original_title'] != null &&
            (item['original_title'] as String).isNotEmpty)
        ? item['original_title'] as String
        : (item['title'] ?? 'Okänd').toString();

    final type = (item['type'] ?? 'Movie').toString();

    // Collect unique non-null resolutions from all versions; fall back to metadata keys
    final versions = item['versions'] as List? ?? [];
    final resolutionSet = <String>{};
    for (final v in versions) {
      final r = _normaliseResolution(v['resolution']?.toString());
      if (r != null) resolutionSet.add(r);
    }
    if (resolutionSet.isEmpty) {
      final meta = item['metadata'];
      final raw = meta is Map
          ? (meta['resolution'] ??
                  meta['video_resolution'] ??
                  meta['quality'] ??
                  meta['video_quality'])
              ?.toString()
          : null;
      final r = raw ?? item['resolution']?.toString();
      final n = _normaliseResolution(r);
      if (n != null) resolutionSet.add(n);
      // Last resort: derive from stored video dimensions
      if (resolutionSet.isEmpty && meta is Map) {
        final h = int.tryParse(meta['video_height']?.toString() ?? '');
        if (h != null && h > 0) {
          final derived = _normaliseResolution('${h}p');
          if (derived != null) resolutionSet.add(derived);
        }
      }
    }
    final resolutionLabel = resolutionSet.isEmpty ? null : resolutionSet.join(' · ');

    final versionsCount = versions.isNotEmpty ? versions.length : 1;
    final metadata = item['metadata'] ?? {};
    final posterPath = item['poster_path'];
    final posterKey = _posterKeyFor(item, posterPrefix);
    final isHovered = _hoveredPosterKey == posterKey;
    final itemId = item['id']?.toString();
    final isSelected = itemId != null && _selectedMediaIds.contains(itemId);
    final posterTextScale = _posterScale.clamp(0.85, 1.25).toDouble();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredPosterKey = posterKey),
      onExit: (_) {
        if (_hoveredPosterKey == posterKey) setState(() => _hoveredPosterKey = null);
      },
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            _openPosterActionsMenu(item, isHomeCard: isHomeCard, globalPos: event.position);
          }
        },
        child: GestureDetector(
        onTap: () => _handlePosterTap(item, isHomeCard: isHomeCard),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Poster area (fills remaining cell height after text section) ──
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF8A5BFF).withValues(alpha: 0.05),
                        const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                      ],
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Poster image
                      if (posterPath != null && (posterPath as String).isNotEmpty)
                        Image.network(
                          posterPath,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                              type == 'Movie' ? Icons.movie_outlined : Icons.tv_outlined,
                              color: Colors.white24,
                              size: 36,
                            ),
                          ),
                        )
                      else
                        Center(
                          child: Icon(
                            type == 'Movie' ? Icons.movie_outlined : Icons.tv_outlined,
                            color: Colors.white24,
                            size: 36,
                          ),
                        ),

                      // Hover light overlay
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: isHovered ? 1 : 0,
                            child: Container(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                        ),
                      ),

                      // Play button (hover only)
                      Positioned.fill(
                        child: Center(
                          child: IgnorePointer(
                            ignoring: !isHovered,
                            child: GestureDetector(
                              onTap: () => _handlePlayTap(item),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                opacity: isHovered ? 1 : 0,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withValues(alpha: 0.3),
                                  ),
                                  child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Selection checkbox (all views)
                      Positioned(
                        top: 10,
                        right: 10,
                          child: GestureDetector(
                            onTap: () => _toggleMediaSelection(item, index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF8A5BFF) : Colors.black.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                                border: Border.all(color: isSelected ? Colors.white : Colors.white24, width: 1),
                              ),
                              child: Icon(isSelected ? Icons.check : Icons.circle_outlined, color: Colors.white, size: 16),
                            ),
                          ),
                        ),

                      // "..." button (bottom-left)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: isHovered ? 1 : 0.65,
                          child: _buildPosterActionButton(
                            icon: Icons.more_horiz,
                            onTapDown: (details) =>
                                _openPosterActionsMenu(item, isHomeCard: isHomeCard, globalPos: details.globalPosition),
                          ),
                        ),
                      ),

                      // Edit button (bottom-right)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: isHovered ? 1 : 0.65,
                          child: _buildPosterActionButton(
                            icon: Icons.edit,
                            onPressed: () => _openMediaEditor(item),
                          ),
                        ),
                      ),

                      // "Premiär" banner for new season premieres
                      if (type == 'Show' && metadata['has_season_premiere'] == '1')
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFFFF6B35).withValues(alpha: 0.95),
                                  const Color(0xFFFFAB40).withValues(alpha: 0.95),
                                ],
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.star, size: 10, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'PREMIÄR',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.star, size: 10, color: Colors.white),
                              ],
                            ),
                          ),
                        ),

                      // Watched checkmark (top-left)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Builder(builder: (context) {
                          if (metadata['watch_status'] == 'watched') {
                            return Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                                boxShadow: [
                                  BoxShadow(color: const Color(0xFF00E676).withValues(alpha: 0.3), blurRadius: 6),
                                ],
                              ),
                              child: const Icon(Icons.check, color: Color(0xFF00E676), size: 14),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ),

                      // Favorite star (below watched icon, top-left area)
                      if (!isHomeCard)
                        Positioned(
                          top: metadata['watch_status'] == 'watched' ? 38 : 10,
                          left: 10,
                          child: Builder(builder: (context) {
                            final isFav = item['is_favorite'] as bool? ?? false;
                            if (!isFav) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.star, color: Color(0xFFFFD65C), size: 14),
                            );
                          }),
                        ),

                      // Selection checkbox restored to top-right (no resolution badge here)

                      // Progress bar (bottom)
                      Builder(builder: (context) {
                        final progress = int.tryParse((metadata['playback_progress']?.toString() ?? '0')) ?? 0;
                        if (progress <= 0) return const SizedBox.shrink();
                        int duration = int.tryParse((metadata['duration']?.toString() ?? '0')) ?? 0;
                        if (duration == 0) {
                          final runtimeMinutes = int.tryParse((metadata['runtime']?.toString() ?? '0')) ?? 0;
                          duration = runtimeMinutes * 60;
                        }
                        if (duration == 0) duration = 7200;
                        final ratio = (progress / duration).clamp(0.0, 1.0);
                        return Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 6,
                            color: Colors.white12,
                            child: LinearProgressIndicator(
                              value: ratio,
                              color: const Color(0xFF8A5BFF),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // ── Text section below poster ─────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.0 * posterTextScale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (continueEpisodeLabel != null) ...[
                      Text(
                        continueEpisodeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFB593FF),
                          fontSize: 10.0 * posterTextScale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ] else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            (item['year'] != null && item['year'].toString().isNotEmpty && item['year'].toString() != 'null')
                                ? item['year'].toString()
                                : '',
                            style: TextStyle(color: Colors.white38, fontSize: 11.0 * posterTextScale),
                          ),
                          if (resolutionLabel != null)
                            Text(
                              resolutionLabel,
                              style: TextStyle(
                                color: const Color(0xFFB593FF),
                                fontSize: 10.0 * posterTextScale,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (!isHomeCard && versionsCount > 1)
                            Text(
                              '$versionsCount ver.',
                              style: TextStyle(
                                color: const Color(0xFFB593FF).withValues(alpha: 0.8),
                                fontSize: 11.0 * posterTextScale,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildMoviesView() {

    if (_loadingMedia) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))));
    }

    if (_mediaError != null) {
      return _buildErrorState(_mediaError!);
    }

    if (_movies.isEmpty) {
      return _buildEmptyState('Inga filmer hittades', 'Gå till Biblioteks scanner-fliken för att importera dina mediafiler.');
    }

    List<dynamic> filteredMovies = _movies;
    if (_genreFilter != null) {
      filteredMovies = _movies.where((m) => (m['genre'] as String? ?? '').toString().toLowerCase().contains(_genreFilter!.toLowerCase())).toList();
    } else if (_keywordFilter != null) {
      filteredMovies = _movies.where((m) {
        final meta = m['metadata'] ?? {};
        dynamic kwData = meta['keywords'];
        List<dynamic> klist = [];
        if (kwData is List) {
          klist = kwData;
        } else if (kwData is String && kwData.isNotEmpty) {
          try {
            klist = (kwData.startsWith('[') || kwData.startsWith('{')) ? (jsonDecode(kwData) as List<dynamic>) : [kwData];
          } catch (e) {
            klist = [kwData];
          }
        }
        return klist.any((kw) => kw.toString().toLowerCase() == _keywordFilter!.toLowerCase());
      }).toList();
    }

    if (_moviesSearchQuery.trim().isNotEmpty) {
      final q = _moviesSearchQuery.toLowerCase();
      filteredMovies = filteredMovies.where((m) {
        final title = (m['title'] ?? '').toString().toLowerCase();
        final originalTitle = (m['original_title'] ?? '').toString().toLowerCase();
        final year = (m['year'] ?? '').toString().toLowerCase();
        return title.contains(q) || originalTitle.contains(q) || year.contains(q);
      }).toList();
    }

    if (filteredMovies.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_genreFilter != null || _keywordFilter != null) _buildGenreFilterBadge(),
          if (_moviesSearchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sökresultat för "$_moviesSearchQuery"',
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _moviesSearchQuery = '';
                      });
                    },
                    child: const Text('Rensa', style: TextStyle(color: Color(0xFFB593FF))),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildEmptyState(
            _moviesSearchQuery.isNotEmpty
                ? 'Inga filmer matchar "$_moviesSearchQuery"'
                : (_keywordFilter != null ? 'Inga filmer matchar nyckelord "$_keywordFilter"' : 'Inga filmer matchar genren "$_genreFilter"'),
            'Ta bort filtret för att se alla filmer.'
          )),
        ],
      );
    }

      _currentMediaGridItemsSnapshot = filteredMovies;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_genreFilter != null) _buildGenreFilterBadge(),
        if (_keywordFilter != null) _buildGenreFilterBadge(),
        if (_moviesSearchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sökresultat för "$_moviesSearchQuery"',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _moviesSearchQuery = '';
                    });
                  },
                  child: const Text('Rensa', style: TextStyle(color: Color(0xFFB593FF))),
                ),
              ],
            ),
          ),
        Expanded(
          child: GridView.builder(
            // Keep the current filtered list available for shift-range selection.
            key: ValueKey(filteredMovies.length),
            controller: _moviesScrollController,
            padding: const EdgeInsets.only(top: 10, bottom: 30),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150 * _posterScale,
              mainAxisSpacing: 30,
              crossAxisSpacing: 24,
              childAspectRatio: (150 * _posterScale) / (225 * _posterScale + 48),
            ),
            itemCount: filteredMovies.length,
            itemBuilder: (context, index) {
              final movie = filteredMovies[index];
              return _buildMediaCard(movie, index: index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShowsView() {
    Widget gridContent;

    if (_loadingMedia) {
      gridContent = const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))));
    } else if (_mediaError != null) {
      gridContent = _buildErrorState(_mediaError!);
    } else if (_shows.isEmpty) {
      gridContent = _buildEmptyState('Inga TV-serier hittades', 'Gå till Biblioteks scanner-fliken för att importera dina mediafiler.');
    } else {
      List<dynamic> filteredShows = _shows;
      if (_showsGenreFilter != null) {
        filteredShows = _shows.where((s) => (s['genre'] as String? ?? '').toString().toLowerCase().contains(_showsGenreFilter!.toLowerCase())).toList();
      } else if (_genreFilter != null) {
        filteredShows = _shows.where((s) => (s['genre'] as String? ?? '').toString().toLowerCase().contains(_genreFilter!.toLowerCase())).toList();
      } else if (_keywordFilter != null) {
        filteredShows = _shows.where((s) {
          final meta = s['metadata'] ?? {};
          dynamic kwData = meta['keywords'];
          List<dynamic> klist = [];
          if (kwData is List) {
            klist = kwData;
          } else if (kwData is String && kwData.isNotEmpty) {
            try {
              klist = (kwData.startsWith('[') || kwData.startsWith('{')) ? (jsonDecode(kwData) as List<dynamic>) : [kwData];
            } catch (e) {
              klist = [kwData];
            }
          }
          return klist.any((kw) => kw.toString().toLowerCase() == _keywordFilter!.toLowerCase());
        }).toList();
      }

      _currentMediaGridItemsSnapshot = filteredShows;

      if (filteredShows.isEmpty) {
        gridContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGenreFilterBadge(),
            Expanded(child: _buildEmptyState(
              _keywordFilter != null ? 'Inga serier matchar nyckelord "$_keywordFilter"' : 'Inga serier matchar genren "${_showsGenreFilter ?? _genreFilter}"',
              'Ta bort filtret för att se alla serier.'
            )),
          ],
        );
      } else {
        gridContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showsGenreFilter != null || _genreFilter != null) _buildGenreFilterBadge(),
            Expanded(
              child: GridView.builder(
                key: ValueKey(filteredShows.length),
                controller: _showsScrollController,
                padding: const EdgeInsets.only(top: 10, bottom: 30),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150 * _posterScale,
                  mainAxisSpacing: 30,
                  crossAxisSpacing: 24,
                  childAspectRatio: (150 * _posterScale) / (225 * _posterScale + 48),
                ),
                itemCount: filteredShows.length,
                itemBuilder: (context, index) {
                  final show = filteredShows[index];
                  return _buildMediaCard(show, index: index);
                },
              ),
            ),
          ],
        );
      }
    }

    return gridContent;
  }

  Widget _buildMediaCard(dynamic item, {required int index}) {
    return _buildUnifiedPosterCard(item, isHomeCard: false, index: index, posterPrefix: 'media');
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: const Icon(
              Icons.inbox_outlined,
              color: Colors.white24,
              size: 64,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white30,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A5BFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              setState(() {
                _tabController.animateTo(3);
              });
            },
            icon: const Icon(Icons.scanner_outlined),
            label: const Text('Gå till Biblioteks scanner'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Kunde inte ladda biblioteksdata',
            style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(color: Colors.white30, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadAllMedia,
            child: const Text('Försök igen'),
          )
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-navigation TabBar
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: TabBar(
              indicatorColor: const Color(0xFF8A5BFF),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.movie_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Filmer', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tv_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('TV-Serier', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_note_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Musik', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 25),

          // Tab views
          Expanded(
            child: TabBarView(
              children: [
                _buildScannerSubTab('Movie'),
                _buildScannerSubTab('Show'),
                _buildScannerSubTab('Music'),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildScannerSubTab(String type) {
    final pathsOfType = _libraryPaths.where((p) => p['type'] == type).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section: Configured Folders
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Konfigurerade ${type == 'Show' ? 'TV-seriemappar' : type == 'Movie' ? 'filmmappar' : 'musikmappar'}',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (pathsOfType.isNotEmpty && _isScanning)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))),
              ),
          ],
        ),
        const SizedBox(height: 15),
        
        if (pathsOfType.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.01),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
            ),
            child: Center(
              child: Text(
                'Inga mappar tillagda än för ${type == 'Show' ? 'TV-Serier' : type == 'Movie' ? 'Filmer' : 'Musik'}.',
                style: const TextStyle(color: Colors.white24, fontSize: 14),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: pathsOfType.length,
              itemBuilder: (context, index) {
                final pathItem = pathsOfType[index];
                return _buildFolderListItem(pathItem);
              },
            ),
          ),
          
        const SizedBox(height: 25),
        const Divider(color: Colors.white10),
        const SizedBox(height: 20),
        
        // Section: Add Folder Form
        Text(
          'Lägg till ${type == 'Show' ? 'TV-seriemapp' : type == 'Movie' ? 'filmmapp' : 'musikmapp'}',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        
        _buildAddFolderForm(type),
        
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildFolderListItem(dynamic pathItem) {
    final id = pathItem['id'];
    final folderPath = pathItem['path'];
    final type = pathItem['type'];
    final isThisPathScanning = _isScanning && (_currentlyScanningPath == folderPath || _currentlyScanningPath == null);

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, color: const Color(0xFFB593FF).withValues(alpha: 0.8), size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  folderPath,
                  style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
              
              // Action: Edit path
              IconButton(
                onPressed: () => _showEditPathDialog(pathItem),
                icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                tooltip: 'Redigera mappsökväg',
              ),
              
              // Action: Scan folder
              IconButton(
                onPressed: _isScanning 
                  ? null 
                  : () => _triggerScanOfSpecificPath(folderPath, type),
                icon: const Icon(Icons.sync_outlined, color: Colors.greenAccent),
                tooltip: 'Skanna mapp nu',
              ),
              
              // Action: Remove path
              IconButton(
                onPressed: () => _deletePath(id),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Ta bort mapp',
              ),
            ],
          ),
        ),
        if (isThisPathScanning) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8A5BFF)),
                minHeight: 3,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<void> _triggerScanOfSpecificPath(String folderPath, String type) async {
    setState(() {
      _isScanning = true;
      _currentlyScanningPath = folderPath;
      _scanStatusText = 'Skannar...';
    });

    try {
      final response = await widget.apiService.triggerLibraryScan(
        folderPath, 
        type,
        preferLocalNfo: _preferLocalNfo,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'Skanning startad!'),
          backgroundColor: const Color(0xFF8A5BFF),
        ),
      );
      
      _pollScannerUntilFinished();
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte starta skanning: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _buildAddFolderForm(String type) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathController,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.3),
                    hintText: 'Ange sökväg eller klicka Bläddra...',
                    hintStyle: const TextStyle(color: Colors.white24),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF8A5BFF), width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                  ),
                  onPressed: _isBrowsingDirectory ? null : _selectFolderNatively,
                  icon: _isBrowsingDirectory
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                        )
                      : const Icon(Icons.folder_open_outlined, color: Color(0xFFB593FF)),
                  label: const Text('Bläddra...'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // Switch Row for Local NFO
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text(
                'Föredra lokal NFO-metadata',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Importera titlar och detaljer från lokala .nfo-filer istället för att hämta online.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11.5),
              ),
              value: _preferLocalNfo,
              activeThumbColor: const Color(0xFF8A5BFF),
              activeTrackColor: const Color(0xFF8A5BFF).withValues(alpha: 0.25),
              onChanged: _setPreferLocalNfo,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Add button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final folder = _pathController.text.trim();
                if (folder.isNotEmpty) {
                  _addNewPath(folder, type);
                  _pathController.clear();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Välj eller ange en mappsökväg')),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: Text(
                'Lägg till mapp i ${type == 'Show' ? 'TV-Serier' : type == 'Movie' ? 'Filmer' : 'Musik'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    if (_isLoadingSettings) return;
    setState(() {
      _isLoadingSettings = true;
    });
    try {
      final settings = await widget.apiService.getSettings();
      await widget.apiService.saveSettingsCache(settings);
      setState(() {
        _tmdbKeyController.text = settings['TMDB_API_KEY'] ?? '';
        _omdbKeyController.text = settings['OMDB_API_KEY'] ?? '';
        _simklKeyController.text = settings['SIMKL_CLIENT_ID'] ?? '';
        _simklSecretController.text = settings['SIMKL_CLIENT_SECRET'] ?? '';
        _simklTokenController.text = settings['SIMKL_ACCESS_TOKEN'] ?? '';
        _traktKeyController.text = settings['TRAKT_API_KEY'] ?? '';
        _traktSecretController.text = settings['TRAKT_CLIENT_SECRET'] ?? '';
        _traktTokenController.text = settings['TRAKT_ACCESS_TOKEN'] ?? '';
        _tmdbAuthController.text = settings['TMDB_USER_AUTH'] ?? '';
        _defaultSubLangController.text = settings['DEFAULT_SUBTITLE_LANG'] ?? 'sv';
        _metadataLanguage = settings['METADATA_LANGUAGE'] ?? 'sv-SE';
        _fallbackLanguage = settings['METADATA_FALLBACK_LANGUAGE'] ?? 'en-US';
        _defaultAudioLanguage = settings['DEFAULT_AUDIO_LANG'] ?? 'sv';
        _watchProviderRegion = settings['WATCH_PROVIDER_REGION'] ?? 'SE';
        _titleDisplayStyle = settings['TITLE_DISPLAY_STYLE'] ?? 'Translated';
        _preferLocalNfo = settings['PREFER_LOCAL_NFO'] != 'false';
        _loadHomeSectionsFromSettings(settings['HOME_LAYOUT']);
        _syncTraktRatings = settings['sync_trakt_ratings'] != 'false';
        _syncTraktWatched = settings['sync_trakt_watched'] != 'false';
        _syncSimklRatings = settings['sync_simkl_ratings'] != 'false';
        _syncSimklWatched = settings['sync_simkl_watched'] != 'false';
        _posterSizeStep = int.tryParse(settings['POSTER_SIZE_STEP'] ?? '') ?? 1;
        _serverName = settings['SERVER_NAME'] ?? '';
        _showClock = settings['SHOW_CLOCK'] == 'true';
        _isLoadingSettings = false;
      });
      // Load avatar URL in parallel; append timestamp so any recently uploaded
      // avatar is not served from Flutter's stale NetworkImage cache.
      widget.apiService.fetchCurrentUserProfile().then((profile) {
        final path = profile['avatar_path'] as String?;
        if (path != null && path.isNotEmpty && mounted) {
          final newUrl = '${widget.apiService.baseUrl}$path?t=${DateTime.now().millisecondsSinceEpoch}';
          if (_avatarUrl != null) {
            PaintingBinding.instance.imageCache.evict(NetworkImage(_avatarUrl!));
          }
          setState(() => _avatarUrl = newUrl);
        } else if (mounted) {
          setState(() => _avatarUrl = null);
        }
      }).catchError((_) {});
    } catch (e) {
      final cachedSettings = widget.apiService.loadSettingsCache();
      if (cachedSettings != null) {
        setState(() {
          _tmdbKeyController.text = cachedSettings['TMDB_API_KEY'] ?? '';
          _omdbKeyController.text = cachedSettings['OMDB_API_KEY'] ?? '';
          _simklKeyController.text = cachedSettings['SIMKL_CLIENT_ID'] ?? '';
          _simklSecretController.text = cachedSettings['SIMKL_CLIENT_SECRET'] ?? '';
          _simklTokenController.text = cachedSettings['SIMKL_ACCESS_TOKEN'] ?? '';
          _traktKeyController.text = cachedSettings['TRAKT_API_KEY'] ?? '';
          _traktSecretController.text = cachedSettings['TRAKT_CLIENT_SECRET'] ?? '';
          _traktTokenController.text = cachedSettings['TRAKT_ACCESS_TOKEN'] ?? '';
          _tmdbAuthController.text = cachedSettings['TMDB_USER_AUTH'] ?? '';
          _defaultSubLangController.text = cachedSettings['DEFAULT_SUBTITLE_LANG'] ?? 'sv';
          _metadataLanguage = cachedSettings['METADATA_LANGUAGE'] ?? 'sv-SE';
          _fallbackLanguage = cachedSettings['METADATA_FALLBACK_LANGUAGE'] ?? 'en-US';
          _defaultAudioLanguage = cachedSettings['DEFAULT_AUDIO_LANG'] ?? 'sv';
          _watchProviderRegion = cachedSettings['WATCH_PROVIDER_REGION'] ?? 'SE';
          _titleDisplayStyle = cachedSettings['TITLE_DISPLAY_STYLE'] ?? 'Translated';
          _preferLocalNfo = cachedSettings['PREFER_LOCAL_NFO'] != 'false';
          _loadHomeSectionsFromSettings(cachedSettings['HOME_LAYOUT']);
          _syncTraktRatings = cachedSettings['sync_trakt_ratings'] != 'false';
          _syncTraktWatched = cachedSettings['sync_trakt_watched'] != 'false';
          _syncSimklRatings = cachedSettings['sync_simkl_ratings'] != 'false';
          _syncSimklWatched = cachedSettings['sync_simkl_watched'] != 'false';
          _posterSizeStep = int.tryParse(cachedSettings['POSTER_SIZE_STEP'] ?? '') ?? 1;
          _serverName = cachedSettings['SERVER_NAME'] ?? '';
          _showClock = cachedSettings['SHOW_CLOCK'] == 'true';
          _isLoadingSettings = false;
        });
        debugPrint('Loaded cached settings after live fetch failed: $e');
        return;
      }
      setState(() {
        _isLoadingSettings = false;
      });
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      await widget.apiService.updateSettings({
        'TMDB_API_KEY': _tmdbKeyController.text.trim(),
        'OMDB_API_KEY': _omdbKeyController.text.trim(),
        'SIMKL_CLIENT_ID': _simklKeyController.text.trim(),
        'SIMKL_CLIENT_SECRET': _simklSecretController.text.trim(),
        'SIMKL_ACCESS_TOKEN': _simklTokenController.text.trim(),
        'TRAKT_API_KEY': _traktKeyController.text.trim(),
        'TRAKT_CLIENT_SECRET': _traktSecretController.text.trim(),
        'TRAKT_ACCESS_TOKEN': _traktTokenController.text.trim(),
        'TMDB_USER_AUTH': _tmdbAuthController.text.trim(),
        'DEFAULT_SUBTITLE_LANG': _defaultSubLangController.text.trim(),
        'METADATA_LANGUAGE': _metadataLanguage,
        'METADATA_FALLBACK_LANGUAGE': _fallbackLanguage,
        'DEFAULT_AUDIO_LANG': _defaultAudioLanguage,
        'WATCH_PROVIDER_REGION': _watchProviderRegion,
        'TITLE_DISPLAY_STYLE': _titleDisplayStyle,
        'PREFER_LOCAL_NFO': _preferLocalNfo ? 'true' : 'false',
        'HOME_LAYOUT': _serializeHomeSections(),
        'sync_trakt_ratings': _syncTraktRatings ? 'true' : 'false',
        'sync_trakt_watched': _syncTraktWatched ? 'true' : 'false',
        'sync_simkl_ratings': _syncSimklRatings ? 'true' : 'false',
        'sync_simkl_watched': _syncSimklWatched ? 'true' : 'false',
        'POSTER_SIZE_STEP': _posterSizeStep.toString(),
      });
      await widget.apiService.saveSettingsCache({
        'TMDB_API_KEY': _tmdbKeyController.text.trim(),
        'OMDB_API_KEY': _omdbKeyController.text.trim(),
        'SIMKL_CLIENT_ID': _simklKeyController.text.trim(),
        'SIMKL_CLIENT_SECRET': _simklSecretController.text.trim(),
        'SIMKL_ACCESS_TOKEN': _simklTokenController.text.trim(),
        'TRAKT_API_KEY': _traktKeyController.text.trim(),
        'TRAKT_CLIENT_SECRET': _traktSecretController.text.trim(),
        'TRAKT_ACCESS_TOKEN': _traktTokenController.text.trim(),
        'TMDB_USER_AUTH': _tmdbAuthController.text.trim(),
        'DEFAULT_SUBTITLE_LANG': _defaultSubLangController.text.trim(),
        'METADATA_LANGUAGE': _metadataLanguage,
        'METADATA_FALLBACK_LANGUAGE': _fallbackLanguage,
        'DEFAULT_AUDIO_LANG': _defaultAudioLanguage,
        'WATCH_PROVIDER_REGION': _watchProviderRegion,
        'TITLE_DISPLAY_STYLE': _titleDisplayStyle,
        'PREFER_LOCAL_NFO': _preferLocalNfo ? 'true' : 'false',
        'HOME_LAYOUT': _serializeHomeSections(),
        'sync_trakt_ratings': _syncTraktRatings ? 'true' : 'false',
        'sync_trakt_watched': _syncTraktWatched ? 'true' : 'false',
        'sync_simkl_ratings': _syncSimklRatings ? 'true' : 'false',
        'sync_simkl_watched': _syncSimklWatched ? 'true' : 'false',
        'POSTER_SIZE_STEP': _posterSizeStep.toString(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inställningar sparade!'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte spara inställningar: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _setPreferLocalNfo(bool value) async {
    setState(() {
      _preferLocalNfo = value;
    });

    try {
      await widget.apiService.updateSettings({
        'PREFER_LOCAL_NFO': value ? 'true' : 'false',
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save local NFO preference: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _startManualSync() async {
    if (_isManualSyncing) return;

    setState(() {
      _isManualSyncing = true;
      _manualSyncProgress = 0.0;
      _manualSyncStep = 'Initierar synkronisering...';
    });

    try {
      await widget.apiService.triggerSync();
      _pollManualSyncStatus();
    } catch (e) {
      setState(() {
        _isManualSyncing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte starta synkronisering: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _pollManualSyncStatus() {
    _manualSyncTimer?.cancel();
    _manualSyncTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      try {
        final status = await widget.apiService.getSyncStatus();
        final bool syncing = status['isSyncing'] == true;
        final int progressVal = status['progress'] ?? 0;
        final String stepText = status['currentStep'] ?? '';
        final lastResult = status['lastSyncResult'];

        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _manualSyncProgress = progressVal / 100.0;
          _manualSyncStep = stepText;
        });

        if (!syncing) {
          timer.cancel();
          setState(() {
            _isManualSyncing = false;
          });

          // Show Toast notification!
          if (lastResult != null && lastResult['success'] == true) {
            final traktRatings = lastResult['trakt']?['ratings'] ?? 0;
            final traktWatched = lastResult['trakt']?['watched'] ?? 0;
            final simklRatings = lastResult['simkl']?['ratings'] ?? 0;
            final simklWatched = lastResult['simkl']?['watched'] ?? 0;

            _showPremiumToast(
              'Synkronisering slutförd!',
              'Trakt: $traktRatings betyg & $traktWatched sedda. Simkl: $simklRatings betyg & $simklWatched sedda.',
              isSuccess: true,
            );
            _loadAllMedia(); // Refresh list to reflect watch markers!
          } else {
            final errorText = lastResult?['error'] ?? 'Okänt fel';
            _showPremiumToast(
              'Synkronisering misslyckades',
              errorText,
              isSuccess: false,
            );
          }
        }
      } catch (e) {
        debugPrint('Error polling sync status: $e');
      }
    });
  }

  void _showPremiumToast(String title, String message, {required bool isSuccess}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _PremiumToastWidget(
        title: title,
        message: message,
        isSuccess: isSuccess,
        onDismiss: () {
          entry.remove();
        },
      ),
    );

    overlay.insert(entry);
  }

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Save Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Inställningar', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  if (_isManualSyncing) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E676)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${(_manualSyncProgress * 100).toInt()}% - $_manualSyncStep',
                            style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 15),
                  ] else ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.04),
                        foregroundColor: const Color(0xFF00E676),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                          side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.4), width: 1.5),
                        ),
                      ),
                      onPressed: _startManualSync,
                      icon: const Icon(Icons.sync, color: Color(0xFF00E676)),
                      label: const Text(
                        'Synkronisera Nu',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 15),
                  ],
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8A5BFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: _saveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('Spara Inställningar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 30),

          // Metadata & Library Scanner Preferences
          _buildSettingsSection(
            'Bibliotek & Metadata',
            Icons.library_books_outlined,
            [
              _buildSettingField('TMDB API Nyckel', _tmdbKeyController, obscure: true),
              const SizedBox(height: 20),
              _buildSettingField('OMDb API Nyckel', _omdbKeyController, obscure: true),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: InkWell(
                  onTap: () => launchUrl(Uri.parse('https://www.omdbapi.com/apikey.aspx'), mode: LaunchMode.externalApplication),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new, size: 12, color: Colors.white38),
                      SizedBox(width: 4),
                      Text(
                        'Skaffa en gratis OMDb API-nyckel här (Välj Free)',
                        style: TextStyle(color: Colors.white38, fontSize: 11, decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Simkl Integration', style: TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse('https://simkl.com/settings/developer/'), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new, size: 12, color: Colors.green),
                    label: const Text('Skapa Simkl App', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSettingField('Simkl Client ID', _simklKeyController, obscure: true),
              const SizedBox(height: 20),
              _buildSettingField('Simkl Client Secret', _simklSecretController, obscure: true),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'Registrera din Simkl-app med Redirect URI:\nhttp://localhost:8080/api/oauth/simkl/callback',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              _buildOAuthConnectorRow(
                label: 'Simkl',
                isConnected: _simklTokenController.text.isNotEmpty,
                color: Colors.green,
                onTap: () async {
                  if (_simklTokenController.text.isNotEmpty) {
                    setState(() {
                      _simklTokenController.clear();
                    });
                    await _saveSettings();
                  } else {
                    await _saveSettings();
                    launchUrl(Uri.parse('${widget.apiService.baseUrl}/api/oauth/simkl/authorize'), mode: LaunchMode.externalApplication);
                    Timer.periodic(const Duration(seconds: 2), (timer) async {
                      if (timer.tick > 30) {
                        timer.cancel();
                      }
                      final settings = await widget.apiService.getSettings();
                      if (settings['SIMKL_ACCESS_TOKEN'] != null && settings['SIMKL_ACCESS_TOKEN'].toString().isNotEmpty) {
                        setState(() {
                          _simklTokenController.text = settings['SIMKL_ACCESS_TOKEN'];
                        });
                        timer.cancel();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Simkl framgångsrikt ansluten! ✅'), backgroundColor: Colors.green),
                        );
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 20),
              _buildSettingField('Simkl Access Token', _simklTokenController, obscure: true),
              if (_simklTokenController.text.isNotEmpty) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Simkl Synkroniseringsval:',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Synkronisera Betyg (Ratings)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        value: _syncSimklRatings,
                        activeColor: Colors.green,
                        onChanged: (val) {
                          setState(() => _syncSimklRatings = val);
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Synkronisera Sedda (Watched Status)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        value: _syncSimklWatched,
                        activeColor: Colors.green,
                        onChanged: (val) {
                          setState(() => _syncSimklWatched = val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 30),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Trakt.tv Integration', style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse('https://trakt.tv/oauth/applications'), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new, size: 12, color: Colors.redAccent),
                    label: const Text('Skapa Trakt App', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSettingField('Trakt API Key (Client ID)', _traktKeyController, obscure: true),
              const SizedBox(height: 20),
              _buildSettingField('Trakt Client Secret', _traktSecretController, obscure: true),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  'Registrera din Trakt-app med Redirect URI:\nhttp://localhost:8080/api/oauth/trakt/callback',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              _buildOAuthConnectorRow(
                label: 'Trakt.tv',
                isConnected: _traktTokenController.text.isNotEmpty,
                color: Colors.redAccent,
                onTap: () async {
                  if (_traktTokenController.text.isNotEmpty) {
                    setState(() {
                      _traktTokenController.clear();
                    });
                    await _saveSettings();
                  } else {
                    await _saveSettings();
                    launchUrl(Uri.parse('${widget.apiService.baseUrl}/api/oauth/trakt/authorize'), mode: LaunchMode.externalApplication);
                    Timer.periodic(const Duration(seconds: 2), (timer) async {
                      if (timer.tick > 30) {
                        timer.cancel();
                      }
                      final settings = await widget.apiService.getSettings();
                      if (settings['TRAKT_ACCESS_TOKEN'] != null && settings['TRAKT_ACCESS_TOKEN'].toString().isNotEmpty) {
                        setState(() {
                          _traktTokenController.text = settings['TRAKT_ACCESS_TOKEN'];
                        });
                        timer.cancel();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Trakt.tv framgångsrikt ansluten! ✅'), backgroundColor: Colors.green),
                        );
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 20),
              _buildSettingField('Trakt Access Token', _traktTokenController, obscure: true),
              if (_traktTokenController.text.isNotEmpty) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trakt.tv Synkroniseringsval:',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Synkronisera Betyg (Ratings)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        value: _syncTraktRatings,
                        activeColor: Colors.redAccent,
                        onChanged: (val) {
                          setState(() => _syncTraktRatings = val);
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Synkronisera Sedda (Watched Status)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        value: _syncTraktWatched,
                        activeColor: Colors.redAccent,
                        onChanged: (val) {
                          setState(() => _syncTraktWatched = val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 25),
              _buildSettingField('TMDB User Auth', _tmdbAuthController, obscure: true),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildSettingsDropdown(
                      'Metadataspråk',
                      _metadataLanguage,
                      ['sv-SE', 'en-US', 'no-NO'],
                      (val) {
                        if (val != null) setState(() => _metadataLanguage = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildSettingsDropdown(
                      'Fallback Metadataspråk',
                      _fallbackLanguage,
                      ['sv-SE', 'en-US', 'no-NO'],
                      (val) {
                        if (val != null) setState(() => _fallbackLanguage = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildSettingsDropdown(
                      'Streamingregion (JustWatch)',
                      _watchProviderRegion,
                      ['SE', 'US', 'NO', 'GB'],
                      (val) {
                        if (val != null) setState(() => _watchProviderRegion = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildSettingsDropdown(
                      'Standard titelvisning',
                      _titleDisplayStyle,
                      ['Translated', 'Original'],
                      (val) {
                        if (val != null) setState(() => _titleDisplayStyle = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Prefer Local NFO Switch in Settings
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text(
                    'Föredra lokal NFO-metadata',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Importera titlar och detaljer från lokala .nfo-filer istället för att hämta online.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11.5),
                  ),
                  value: _preferLocalNfo,
                  activeThumbColor: const Color(0xFF8A5BFF),
                  activeTrackColor: const Color(0xFF8A5BFF).withValues(alpha: 0.25),
                  onChanged: _setPreferLocalNfo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),

          // Playback Preferences
          _buildSettingsSection(
            'Uppspelning standardinställningar',
            Icons.play_circle_outline,
            [
              Row(
                children: [
                  Expanded(
                    child: _buildSettingsDropdown(
                      'Standardljudspråk',
                      _defaultAudioLanguage,
                      ['sv', 'en', 'no'],
                      (val) {
                        if (val != null) setState(() => _defaultAudioLanguage = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildSettingsDropdown(
                      'Standardundertextspråk',
                      _defaultSubLangController.text,
                      ['sv', 'en', 'no', 'None'],
                      (val) {
                        if (val != null) {
                          setState(() {
                            _defaultSubLangController.text = val;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Fönsterinställningar ───────────────────────────────────────
          _buildSettingsSection(
            'Fönsterinställningar',
            Icons.window,
            [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Alltid överst',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('Håller Loom-fönstret ovanpå alla andra fönster.',
                            style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _alwaysOnTop,
                    activeColor: const Color(0xFF8A5BFF),
                    onChanged: kIsWeb
                        ? null
                        : (val) async {
                            try {
                              await windowManager.setAlwaysOnTop(val);
                              setState(() => _alwaysOnTop = val);
                            } catch (e) {
                              debugPrint('setAlwaysOnTop failed: $e');
                            }
                          },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Papperskorg
          _buildSettingsSection(
            'Papperskorg',
            Icons.delete_outline,
            [
              SizedBox(
                height: 600,
                child: TrashScreen(
                  apiService: widget.apiService,
                  onRestored: _loadAllMedia,
                ),
              ),
            ],
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF8A5BFF), size: 24),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(color: Colors.white10, height: 32),
          ...children
        ],
      ),
    );
  }

  Widget _buildSettingsDropdown(String label, String value, List<String> options, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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

  Widget _buildOAuthConnectorRow({
    required String label,
    required bool isConnected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(isConnected ? Icons.check_circle : Icons.link, color: isConnected ? Colors.green : color, size: 20),
              const SizedBox(width: 10),
              Text(
                isConnected ? '$label är kopplad' : 'Koppla till $label',
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isConnected ? Colors.white12 : color,
              foregroundColor: isConnected ? Colors.white70 : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: isConnected ? 0 : 2,
            ),
            onPressed: onTap,
            icon: Icon(isConnected ? Icons.link_off : Icons.login, size: 14),
            label: Text(
              isConnected ? 'Koppla från' : 'Anslut nu',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingField(String label, TextEditingController controller, {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.3),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF8A5BFF), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _PremiumToastWidget extends StatefulWidget {
  final String title;
  final String message;
  final bool isSuccess;
  final VoidCallback onDismiss;

  const _PremiumToastWidget({
    required this.title,
    required this.message,
    required this.isSuccess,
    required this.onDismiss,
  });

  @override
  State<_PremiumToastWidget> createState() => _PremiumToastWidgetState();
}

class _PremiumToastWidgetState extends State<_PremiumToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<double>(begin: -80, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );

    _animController.forward();

    _dismissTimer = Timer(const Duration(seconds: 4), () {
      _dismiss();
    });
  }

  void _dismiss() {
    _animController.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 40,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeAnim.value,
              child: Transform.translate(
                offset: Offset(0, _slideAnim.value),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 480,
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF130E26).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.isSuccess 
                            ? const Color(0xFF00E676).withValues(alpha: 0.4) 
                            : Colors.redAccent.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (widget.isSuccess ? const Color(0xFF00E676) : Colors.redAccent).withValues(alpha: 0.15),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (widget.isSuccess ? const Color(0xFF00E676) : Colors.redAccent).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  widget.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                                  color: widget.isSuccess ? const Color(0xFF00E676) : Colors.redAccent,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.message,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 12.5,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                                onPressed: _dismiss,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


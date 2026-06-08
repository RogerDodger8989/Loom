// ═══════════════════════════════════════════════════════════════════
//  settings_screen.dart — Loom inställningsdialog
//
//  Entry-point: openSettings(context, apiService, {onLibraryChanged})
//  Öppnas via PopupMenuButton i dashboard_screen.dart → _buildUserSwitcher()
//
//  Kategorier (index → _buildContent() switch → metod):
//    0  Konto              → _buildKonto()          ✅ klar
//    1  Användare          → _buildAnvandare()     ✅ klar (Admin-only)
//    2  Bibliotek          → _buildBibliotek()     ✅ klar
//    3  Papperskorg        → _buildPapperskorg()   ✅ klar
//    4  Uppspelning        → _buildUppspelning()   ✅ klar
//    5  Källor & Integr.   → _buildKallor()        ✅ klar
//    6  Notifieringar      → _buildNotifieringar() ✅ klar
//    7  Statistik          → _buildStatistik()      ✅ klar (polling 5s)
//    8  Loggning           → _buildLoggning()      ✅ klar (polling 3s, sinceId)
//    9  Server             → _buildServer()        ✅ klar
//   10  Diskutrymme        → _buildDiskutrymme()  ✅ klar
//
//  State-grupper i _SettingsScreenState:
//    "Settings state"      — TMDB/OMDb/Simkl/Trakt-nycklar, språk, NFO-preferens
//    "Notifications state" — Discord webhook + SMTP-fält
//    "Server state"        — servernamn, _serverInfo cache, optimize/restore-flaggor
//    "Logging state"       — _logEntries, _lastLogId, poll-timer, scroll-controller
//    "Users state"         — _users, _newUserRole, skapa-form controllers
//    "Konto state"         — _currentPassCtrl, _newPassCtrl, _confirmPassCtrl
//    "Scanner/library"     — _libraryPaths, _isScanning, path-controller
//
//  _saveSettings() / _applySettings() hanterar ALL nyckel/värde-persistens via
//  GET+PUT /api/settings (platt SQLite-tabell). Lägg till nya nycklar i båda.
//
//  Mönster för ny kategori: se SETTINGS_PLAN.md → "Mönster för ny kategori"
// ═══════════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:io';
import 'dart:io' show Process;
import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import '../services/api.dart';
import 'trash_screen.dart';

Future<void> _openUrl(String url) async {
  if (kIsWeb) {
    html.window.open(url, '_blank');
  } else {
    try {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } catch (_) {
      final uri = Uri.parse(url);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        try {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        } catch (_) {}
      }
    }
  }
}

// ─────────────────────────────────────────────
//  Public entry-point: full-page navigation
// ─────────────────────────────────────────────
Future<void> openSettings(
  BuildContext context,
  ApiService apiService, {
  VoidCallback? onLibraryChanged,
  VoidCallback? onNavigateHome,
  int initialCategory = 0,
  int initialStatsTab = 0,
  void Function(String mediaId, int statsTabIndex)? onNavigateToMedia,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SettingsScreen(
        apiService: apiService,
        onLibraryChanged: onLibraryChanged,
        onNavigateHome: onNavigateHome,
        initialCategory: initialCategory,
        initialStatsTab: initialStatsTab,
        onNavigateToMedia: onNavigateToMedia,
      ),
    ),
  );
}

// ─────────────────────────────────────────────
//  SettingsScreen
// ─────────────────────────────────────────────
class SettingsScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onLibraryChanged;
  final VoidCallback? onNavigateHome;
  final int initialCategory;
  final int initialStatsTab;
  final void Function(String mediaId, int statsTabIndex)? onNavigateToMedia;

  const SettingsScreen({
    super.key,
    required this.apiService,
    this.onLibraryChanged,
    this.onNavigateHome,
    this.initialCategory = 0,
    this.initialStatsTab = 0,
    this.onNavigateToMedia,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _selectedCategory;

  // ── Settings state ──────────────────────────
  final _tmdbKeyCtrl = TextEditingController();
  final _omdbKeyCtrl = TextEditingController();
  final _simklKeyCtrl = TextEditingController();
  final _simklSecretCtrl = TextEditingController();
  final _simklTokenCtrl = TextEditingController();
  final _traktKeyCtrl = TextEditingController();
  final _traktSecretCtrl = TextEditingController();
  final _traktTokenCtrl = TextEditingController();
  final _imdbUserIdCtrl = TextEditingController();
  final _tmdbAuthCtrl = TextEditingController();
  final _defaultSubLangCtrl = TextEditingController(text: 'sv');

  String _versionPriority = '1080p,720p,4K';
  String _metadataLanguage = 'sv-SE';
  String _fallbackLanguage = 'en-US';
  String _defaultAudioLanguage = 'sv';
  String _watchProviderRegion = 'SE';
  String _titleDisplayStyle = 'Translated';
  bool _preferLocalNfo = true;
  bool _alwaysOnTop = false;
  bool _syncTraktRatings = true;
  bool _syncTraktWatched = true;
  bool _syncSimklRatings = true;
  bool _syncSimklWatched = true;
  bool _isLoadingSettings = false;

  // auto-save
  Timer? _autoSaveTimer;
  String _autoSaveStatus = ''; // '' | 'saving' | 'saved'

  bool _isManualSyncing = false;
  double _manualSyncProgress = 0.0;
  String _manualSyncStep = '';
  Timer? _manualSyncTimer;

  // ── RSS state ────────────────────────────────
  List<dynamic> _rssFeeds = [];
  List<dynamic> _rssItems = [];
  bool _isLoadingRss = false;
  bool _isRefreshingRss = false;
  final _rssFeedUrlCtrl = TextEditingController();

  // ── Notifications state ──────────────────────
  final _discordWebhookCtrl = TextEditingController();
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '587');
  final _smtpUserCtrl = TextEditingController();
  final _smtpPassCtrl = TextEditingController();
  final _smtpFromCtrl = TextEditingController();
  final _smtpToCtrl = TextEditingController();
  bool _isTestingDiscord = false;
  bool _isTestingEmail = false;
  bool? _discordTestResult;
  bool? _emailTestResult;

  // ── Server state ─────────────────────────────
  final _serverNameCtrl = TextEditingController();
  Map<String, dynamic>? _serverInfo;
  bool _isOptimizing = false;
  bool? _optimizeResult;
  bool _isRestoring = false;
  bool _isRestarting = false;
  bool _showClock = false;
  bool _showUpcomingEpisodes = true;

  // ── Export/Import state ───────────────────────
  bool _expSettings = true;
  bool _expLibraryPaths = true;
  bool _expUsers = false;
  bool _expWatchHistory = false;
  bool _expWatchlist = false;
  bool _expMarkers = false;
  bool _isExporting = false;
  bool _isImporting = false;
  Map<String, dynamic>? _importResult;

  // ── Logging state ────────────────────────────
  final List<Map<String, dynamic>> _logEntries = [];
  int _lastLogId = 0;
  String _logLevelFilter = 'Alla';
  bool _logAutoScroll = true;
  bool _logPaused = false;
  Timer? _logPollTimer;
  final ScrollController _logScrollCtrl = ScrollController();

  // ── Stats state ───────────────────────────────
  Map<String, dynamic>? _statsRealtime;
  Map<String, dynamic>? _statsHistory;
  Map<String, dynamic>? _statsTops;
  List<dynamic> _statsUsers = [];
  Timer? _statsPollTimer;
  String? _statsError;
  String? _statsSelectedUserId;   // null = alla användare
  int _statsDaysFilter = 0;       // 0 = alla tider
  DateTime? _statsDateFrom;
  DateTime? _statsDateTo;
  bool _statsHistoryLoading = false;
  int _statsTabIndex = 0;         // 0=Överblick 1=Historik 2=Toppar
  final Map<String, bool> _expandedTopItems = {};
  final Map<String, List<dynamic>> _topItemPlays = {};
  final Map<String, bool> _topItemPlaysLoading = {};

  // ── Users state (steg 7) ────────────────────
  List<Map<String, dynamic>> _users = [];
  bool _isLoadingUsers = false;
  final _newUsernameCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  String _newUserRole = 'User';
  bool _isCreatingUser = false;

  // ── Konto state ───────────────────────────────
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _isChangingPassword = false;
  final _fullNameCtrl = TextEditingController();
  final _newUsernameEditCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _isSavingProfile = false;
  bool _hasPinSet = false;
  Timer? _profileSaveTimer;
  String _profileSaveStatus = ''; // '' | 'saving' | 'saved'
  Uint8List? _avatarImageBytes;
  double _avatarScale = 1.0;
  Offset _avatarOffset = Offset.zero;
  String? _avatarUrl; // URL från servern när inga lokala bytes finns

  // ── Disk Manager state ────────────────────────
  bool _diskRuleWatchedEnabled = false;
  bool _diskRuleUnseenEnabled = false;
  bool _diskRuleInactiveEnabled = false;
  bool _diskRuleSizeEnabled = false;
  bool _diskRuleSizeRequireWatched = false;
  bool _diskRuleRatingEnabled = false;
  bool _diskProtectFavorites = true;
  String _diskSeriesMode = 'episode';
  final _diskWatchedDaysCtrl   = TextEditingController(text: '7');
  final _diskUnseenDaysCtrl    = TextEditingController(text: '60');
  final _diskInactiveDaysCtrl  = TextEditingController(text: '365');
  final _diskSizeGbCtrl        = TextEditingController(text: '50');
  final _diskRatingMaxCtrl     = TextEditingController(text: '3');
  // Dry-run / cleanup state
  bool _isDiskStatsLoading = false;
  bool _isDiskScanning = false;
  bool _isDiskCleaning = false;
  Map<String, dynamic>? _diskStats;
  List<Map<String, dynamic>> _diskCandidates = [];
  int _diskTotalCandidates = 0;
  double _diskTotalFreeableGb = 0;
  String? _diskScanError;
  String? _diskCleanResult;

  // ── Scanner / library state ─────────────────
  final _pathCtrl = TextEditingController();
  final _scanSkipWordsCtrl = TextEditingController();
  final _scanMinSizeCtrl = TextEditingController(text: '0');
  bool _isScanning = false;
  String? _currentlyScanningPath;
  bool _isBrowsingDirectory = false;
  List<dynamic> _libraryPaths = [];
  // Real-time scan log
  List<Map<String, dynamic>> _scanLog = [];
  int _lastScanEventId = 0;
  Timer? _scanEventTimer;

  // ─────────────────────────────────────────────
  //  Category definitions
  // ─────────────────────────────────────────────
  static const _cats = [
    (Icons.person_outline, Icons.person, 'Konto'),
    (Icons.group_outlined, Icons.group, 'Användare'),
    (Icons.library_books_outlined, Icons.library_books, 'Bibliotek'),
    (Icons.delete_outline, Icons.delete, 'Papperskorg'),
    (Icons.play_circle_outline, Icons.play_circle, 'Uppspelning'),
    (Icons.link_outlined, Icons.link, 'Källor & Integrationer'),
    (Icons.notifications_none, Icons.notifications, 'Notifieringar'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Statistik'),
    (Icons.terminal_outlined, Icons.terminal, 'Loggning'),
    (Icons.dns_outlined, Icons.dns, 'Server'),
    (Icons.storage_outlined, Icons.storage, 'Diskutrymme'),
  ];

  // ─────────────────────────────────────────────
  //  Lifecycle
  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _statsTabIndex = widget.initialStatsTab;
    // Keep ApiService in sync so the next settings open remembers this tab.
    widget.apiService.lastStatsTabIndex = widget.initialStatsTab;
    _loadSettings();
    _loadLibraryPaths();
    _checkScannerStatus();
  }

  @override
  void dispose() {
    // Flush pending debounced saves immediately before closing
    if (_autoSaveTimer?.isActive == true) {
      _autoSaveTimer?.cancel();
      _saveSettings().catchError((_) {});
    } else {
      _autoSaveTimer?.cancel();
    }
    _profileSaveTimer?.cancel();
    _logPollTimer?.cancel();
    _statsPollTimer?.cancel();
    _scanEventTimer?.cancel();
    _logScrollCtrl.dispose();
    _manualSyncTimer?.cancel();
    for (final c in [
      _tmdbKeyCtrl, _omdbKeyCtrl, _simklKeyCtrl, _simklSecretCtrl,
      _simklTokenCtrl, _traktKeyCtrl, _traktSecretCtrl, _traktTokenCtrl,
      _tmdbAuthCtrl, _defaultSubLangCtrl, _pathCtrl, _scanSkipWordsCtrl, _scanMinSizeCtrl,
      _discordWebhookCtrl, _smtpHostCtrl, _smtpPortCtrl, _smtpUserCtrl,
      _smtpPassCtrl, _smtpFromCtrl, _smtpToCtrl, _serverNameCtrl,
      _newUsernameCtrl, _newPasswordCtrl,
      _currentPassCtrl, _newPassCtrl, _confirmPassCtrl,
      _fullNameCtrl, _newUsernameEditCtrl, _pinCtrl,
      _rssFeedUrlCtrl,
      _imdbUserIdCtrl,
      _diskWatchedDaysCtrl, _diskUnseenDaysCtrl, _diskInactiveDaysCtrl,
      _diskSizeGbCtrl, _diskRatingMaxCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────
  //  Settings load / save
  // ─────────────────────────────────────────────
  Future<void> _loadSettings() async {
    if (_isLoadingSettings) return;
    setState(() => _isLoadingSettings = true);
    try {
      final results = await Future.wait([
        widget.apiService.getSettings(),
        widget.apiService.fetchCurrentUserProfile().catchError((_) => <String, dynamic>{}),
      ]);
      final s = results[0] as Map<String, dynamic>;
      final profile = results[1] as Map<String, dynamic>;
      await widget.apiService.saveSettingsCache(s);
      _applySettings(s);
      if (profile.isNotEmpty && mounted) {
        final avatarPath = profile['avatar_path'] as String?;
        setState(() {
          _fullNameCtrl.text = (profile['full_name'] as String?) ?? '';
          _newUsernameEditCtrl.text = (profile['username'] as String?) ?? '';
          if (avatarPath != null && avatarPath.isNotEmpty) {
            _avatarUrl = '${widget.apiService.baseUrl}$avatarPath';
          }
        });
      }
    } catch (_) {
      final cached = widget.apiService.loadSettingsCache();
      if (cached != null) _applySettings(cached);
    } finally {
      if (mounted) setState(() => _isLoadingSettings = false);
    }
  }

  void _applySettings(Map<String, dynamic> s) {
    setState(() {
      _tmdbKeyCtrl.text = s['TMDB_API_KEY'] ?? '';
      _omdbKeyCtrl.text = s['OMDB_API_KEY'] ?? '';
      _simklKeyCtrl.text = s['SIMKL_CLIENT_ID'] ?? '';
      _simklSecretCtrl.text = s['SIMKL_CLIENT_SECRET'] ?? '';
      _simklTokenCtrl.text = s['SIMKL_ACCESS_TOKEN'] ?? '';
      _traktKeyCtrl.text = s['TRAKT_API_KEY'] ?? '';
      _traktSecretCtrl.text = s['TRAKT_CLIENT_SECRET'] ?? '';
      _traktTokenCtrl.text = s['TRAKT_ACCESS_TOKEN'] ?? '';
      _imdbUserIdCtrl.text = s['IMDB_USER_ID'] ?? '';
      _tmdbAuthCtrl.text = s['TMDB_USER_AUTH'] ?? '';
      _defaultSubLangCtrl.text = s['DEFAULT_SUBTITLE_LANG'] ?? 'sv';
      _metadataLanguage = s['METADATA_LANGUAGE'] ?? 'sv-SE';
      _fallbackLanguage = s['METADATA_FALLBACK_LANGUAGE'] ?? 'en-US';
      _defaultAudioLanguage = s['DEFAULT_AUDIO_LANG'] ?? 'sv';
      _watchProviderRegion = s['WATCH_PROVIDER_REGION'] ?? 'SE';
      _titleDisplayStyle = s['TITLE_DISPLAY_STYLE'] ?? 'Translated';
      _preferLocalNfo = s['PREFER_LOCAL_NFO'] != 'false';
      _versionPriority = s['VERSION_PRIORITY'] ?? '1080p,720p,4K';
      _syncTraktRatings = s['sync_trakt_ratings'] != 'false';
      _syncTraktWatched = s['sync_trakt_watched'] != 'false';
      _syncSimklRatings = s['sync_simkl_ratings'] != 'false';
      _syncSimklWatched = s['sync_simkl_watched'] != 'false';
      _discordWebhookCtrl.text = s['DISCORD_WEBHOOK_URL'] ?? '';
      _smtpHostCtrl.text = s['SMTP_HOST'] ?? '';
      _smtpPortCtrl.text = s['SMTP_PORT'] ?? '587';
      _smtpUserCtrl.text = s['SMTP_USER'] ?? '';
      _smtpPassCtrl.text = s['SMTP_PASS'] ?? '';
      _smtpFromCtrl.text = s['SMTP_FROM'] ?? '';
      _smtpToCtrl.text = s['SMTP_TO'] ?? '';
      _serverNameCtrl.text = s['SERVER_NAME'] ?? '';
      _scanSkipWordsCtrl.text = s['SCAN_SKIP_WORDS'] ?? '';
      _scanMinSizeCtrl.text = s['SCAN_MIN_SIZE_MB'] ?? '0';
      _showClock = s['SHOW_CLOCK'] == 'true';
      _showUpcomingEpisodes = s['SHOW_UPCOMING_EPISODES'] != 'false';
      _alwaysOnTop = s['ALWAYS_ON_TOP'] == 'true';
      _diskRuleWatchedEnabled   = s['DISK_RULE_WATCHED_ENABLED'] == 'true';
      _diskWatchedDaysCtrl.text  = s['DISK_RULE_WATCHED_DAYS'] ?? '7';
      _diskRuleUnseenEnabled    = s['DISK_RULE_UNSEEN_ENABLED'] == 'true';
      _diskUnseenDaysCtrl.text   = s['DISK_RULE_UNSEEN_DAYS'] ?? '60';
      _diskRuleInactiveEnabled  = s['DISK_RULE_INACTIVE_ENABLED'] == 'true';
      _diskInactiveDaysCtrl.text = s['DISK_RULE_INACTIVE_DAYS'] ?? '365';
      _diskRuleSizeEnabled      = s['DISK_RULE_SIZE_ENABLED'] == 'true';
      _diskSizeGbCtrl.text       = s['DISK_RULE_SIZE_GB'] ?? '50';
      _diskRuleSizeRequireWatched = s['DISK_RULE_SIZE_REQUIRE_WATCHED'] == 'true';
      _diskRuleRatingEnabled    = s['DISK_RULE_RATING_ENABLED'] == 'true';
      _diskRatingMaxCtrl.text    = s['DISK_RULE_RATING_MAX'] ?? '3';
      _diskSeriesMode           = s['DISK_RULE_SERIES_MODE'] ?? 'episode';
      _diskProtectFavorites     = s['DISK_RULE_PROTECT_FAVORITES'] != 'false';
    });
    if (_alwaysOnTop && !kIsWeb) {
      windowManager.setAlwaysOnTop(true).catchError((_) {});
    }
  }

  void _scheduleSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () async {
      await _saveSettings();
    });
  }

  Future<void> _saveSettings() async {
    if (mounted) setState(() => _autoSaveStatus = 'saving');
    try {
      final payload = {
        'TMDB_API_KEY': _tmdbKeyCtrl.text.trim(),
        'OMDB_API_KEY': _omdbKeyCtrl.text.trim(),
        'SIMKL_CLIENT_ID': _simklKeyCtrl.text.trim(),
        'SIMKL_CLIENT_SECRET': _simklSecretCtrl.text.trim(),
        'SIMKL_ACCESS_TOKEN': _simklTokenCtrl.text.trim(),
        'TRAKT_API_KEY': _traktKeyCtrl.text.trim(),
        'TRAKT_CLIENT_SECRET': _traktSecretCtrl.text.trim(),
        'TRAKT_ACCESS_TOKEN': _traktTokenCtrl.text.trim(),
        'IMDB_USER_ID': _imdbUserIdCtrl.text.trim(),
        'TMDB_USER_AUTH': _tmdbAuthCtrl.text.trim(),
        'DEFAULT_SUBTITLE_LANG': _defaultSubLangCtrl.text.trim(),
        'METADATA_LANGUAGE': _metadataLanguage,
        'METADATA_FALLBACK_LANGUAGE': _fallbackLanguage,
        'DEFAULT_AUDIO_LANG': _defaultAudioLanguage,
        'WATCH_PROVIDER_REGION': _watchProviderRegion,
        'TITLE_DISPLAY_STYLE': _titleDisplayStyle,
        'PREFER_LOCAL_NFO': _preferLocalNfo ? 'true' : 'false',
        'sync_trakt_ratings': _syncTraktRatings ? 'true' : 'false',
        'sync_trakt_watched': _syncTraktWatched ? 'true' : 'false',
        'sync_simkl_ratings': _syncSimklRatings ? 'true' : 'false',
        'sync_simkl_watched': _syncSimklWatched ? 'true' : 'false',
        'DISCORD_WEBHOOK_URL': _discordWebhookCtrl.text.trim(),
        'SMTP_HOST': _smtpHostCtrl.text.trim(),
        'SMTP_PORT': _smtpPortCtrl.text.trim(),
        'SMTP_USER': _smtpUserCtrl.text.trim(),
        'SMTP_PASS': _smtpPassCtrl.text.trim(),
        'SMTP_FROM': _smtpFromCtrl.text.trim(),
        'SMTP_TO': _smtpToCtrl.text.trim(),
        'SERVER_NAME': _serverNameCtrl.text.trim(),
        'VERSION_PRIORITY': _versionPriority,
        'ALWAYS_ON_TOP': _alwaysOnTop ? 'true' : 'false',
        'SCAN_SKIP_WORDS': _scanSkipWordsCtrl.text.trim(),
        'SCAN_MIN_SIZE_MB': _scanMinSizeCtrl.text.trim(),
        'SHOW_CLOCK': _showClock ? 'true' : 'false',
        'SHOW_UPCOMING_EPISODES': _showUpcomingEpisodes ? 'true' : 'false',
        'DISK_RULE_WATCHED_ENABLED': _diskRuleWatchedEnabled ? 'true' : 'false',
        'DISK_RULE_WATCHED_DAYS': _diskWatchedDaysCtrl.text.trim(),
        'DISK_RULE_UNSEEN_ENABLED': _diskRuleUnseenEnabled ? 'true' : 'false',
        'DISK_RULE_UNSEEN_DAYS': _diskUnseenDaysCtrl.text.trim(),
        'DISK_RULE_INACTIVE_ENABLED': _diskRuleInactiveEnabled ? 'true' : 'false',
        'DISK_RULE_INACTIVE_DAYS': _diskInactiveDaysCtrl.text.trim(),
        'DISK_RULE_SIZE_ENABLED': _diskRuleSizeEnabled ? 'true' : 'false',
        'DISK_RULE_SIZE_GB': _diskSizeGbCtrl.text.trim(),
        'DISK_RULE_SIZE_REQUIRE_WATCHED': _diskRuleSizeRequireWatched ? 'true' : 'false',
        'DISK_RULE_RATING_ENABLED': _diskRuleRatingEnabled ? 'true' : 'false',
        'DISK_RULE_RATING_MAX': _diskRatingMaxCtrl.text.trim(),
        'DISK_RULE_SERIES_MODE': _diskSeriesMode,
        'DISK_RULE_PROTECT_FAVORITES': _diskProtectFavorites ? 'true' : 'false',
      };
      await widget.apiService.updateSettings(payload);
      await widget.apiService.saveSettingsCache(payload);
      if (!mounted) return;
      setState(() => _autoSaveStatus = 'saved');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _autoSaveStatus = '');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoSaveStatus = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte spara: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _scheduleProfileSave() {
    _profileSaveTimer?.cancel();
    _profileSaveTimer = Timer(const Duration(milliseconds: 900), () async {
      final fullName = _fullNameCtrl.text.trim();
      final newUsername = _newUsernameEditCtrl.text.trim();
      if (fullName.isEmpty && newUsername.isEmpty) return;
      if (mounted) setState(() => _profileSaveStatus = 'saving');
      try {
        await widget.apiService.updateOwnProfile(
          fullName: fullName.isNotEmpty ? fullName : null,
          newUsername: newUsername.isNotEmpty ? newUsername : null,
          // Only update username if it actually differs from JWT-stored value
        );
        if (!mounted) return;
        setState(() => _profileSaveStatus = 'saved');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _profileSaveStatus = '');
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _profileSaveStatus = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profil: $e'), backgroundColor: Colors.redAccent),
        );
      }
    });
  }

  void _schedulePin() {
    _profileSaveTimer?.cancel();
    _profileSaveTimer = Timer(const Duration(milliseconds: 900), () async {
      final pin = _pinCtrl.text.trim();
      if (pin.isEmpty) return;
      if (pin.length < 4 || pin.length > 8 || !RegExp(r'^\d+$').hasMatch(pin)) return;
      if (mounted) setState(() => _profileSaveStatus = 'saving');
      try {
        await widget.apiService.updateOwnProfile(pin: pin);
        if (!mounted) return;
        _pinCtrl.clear();
        setState(() { _hasPinSet = true; _profileSaveStatus = 'saved'; });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _profileSaveStatus = '');
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _profileSaveStatus = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PIN: $e'), backgroundColor: Colors.redAccent),
        );
      }
    });
  }

  Future<void> _setPreferLocalNfo(bool value) async {
    setState(() => _preferLocalNfo = value);
    try {
      await widget.apiService.updateSettings({'PREFER_LOCAL_NFO': value ? 'true' : 'false'});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // ─────────────────────────────────────────────
  //  Manual sync
  // ─────────────────────────────────────────────
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
      setState(() => _isManualSyncing = false);
      if (!mounted) return;
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
        if (!mounted) { timer.cancel(); return; }
        final bool syncing = status['isSyncing'] == true;
        setState(() {
          _manualSyncProgress = ((status['progress'] ?? 0) as num) / 100.0;
          _manualSyncStep = status['currentStep'] ?? '';
        });
        if (!syncing) {
          timer.cancel();
          setState(() => _isManualSyncing = false);
          final lastResult = status['lastSyncResult'];
          if (lastResult != null && lastResult['success'] == true) {
            final traktR = lastResult['trakt']?['ratings'] ?? 0;
            final traktW = lastResult['trakt']?['watched'] ?? 0;
            final simklR = lastResult['simkl']?['ratings'] ?? 0;
            final simklW = lastResult['simkl']?['watched'] ?? 0;
            _showToast('Synkronisering slutförd!',
                'Trakt: $traktR betyg & $traktW sedda. Simkl: $simklR betyg & $simklW sedda.',
                isSuccess: true);
            widget.onLibraryChanged?.call();
          } else {
            _showToast('Synkronisering misslyckades',
                lastResult?['error'] ?? 'Okänt fel',
                isSuccess: false);
          }
        }
      } catch (_) {}
    });
  }

  void _showToast(String title, String message, {required bool isSuccess}) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        title: title,
        message: message,
        isSuccess: isSuccess,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  // ─────────────────────────────────────────────
  //  Library / scanner
  // ─────────────────────────────────────────────
  Future<void> _loadLibraryPaths() async {
    try {
      final paths = await widget.apiService.fetchLibraryPaths();
      if (mounted) setState(() => _libraryPaths = paths);
    } catch (e) {
      debugPrint('Error loading library paths: $e');
    }
  }

  Future<void> _checkScannerStatus() async {
    try {
      final status = await widget.apiService.getLibraryStatus();
      if (!mounted) return;
      setState(() {
        _isScanning = status['isScanning'] ?? false;
        if (!_isScanning) _currentlyScanningPath = null;
      });
    } catch (_) {}
  }

  Future<void> _addNewPath(String folderPath, String type) async {
    try {
      await widget.apiService.addLibraryPath(folderPath, type);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Lade till: "$folderPath"'),
        backgroundColor: const Color(0xFF8A5BFF),
      ));
      _loadLibraryPaths();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _deletePath(String id) async {
    try {
      await widget.apiService.deleteLibraryPath(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sökväg borttagen'),
        backgroundColor: Color(0xFF8A5BFF),
      ));
      _loadLibraryPaths();
      widget.onLibraryChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _updatePath(String id, String newPath) async {
    try {
      final res = await widget.apiService.updateLibraryPath(id, newPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Uppdaterad! ${res['updatedCount'] ?? 0} filer ändrade.'),
        backgroundColor: const Color(0xFF8A5BFF),
      ));
      _loadLibraryPaths();
      widget.onLibraryChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _showEditPathDialog(dynamic pathItem) async {
    final editCtrl = TextEditingController(text: pathItem['path']);
    bool browsing = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF15102A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          title: Text('Redigera ${pathItem['type'] == 'Show' ? 'TV-seriemapp' : pathItem['type'] == 'Movie' ? 'Filmmapp' : 'Musikmapp'}'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Att redigera sökvägen uppdaterar alla matchande filer i databasen.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13.5),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: editCtrl,
                      style: const TextStyle(color: Colors.white),
                      contextMenuBuilder: (ctx, state) =>
                          AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                      decoration: _inputDeco('Ny sökväg...'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _browseButton(
                    browsing: browsing,
                    onTap: () async {
                      setDs(() => browsing = true);
                      try {
                        final r = await widget.apiService.browseNativeDirectory();
                        if (r['path'] != null) editCtrl.text = r['path'];
                      } finally {
                        setDs(() => browsing = false);
                      }
                    },
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(),
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
                final np = editCtrl.text.trim();
                if (np.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  await _updatePath(pathItem['id'], np);
                }
              },
              child: const Text('Spara'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectFolderNatively() async {
    setState(() => _isBrowsingDirectory = true);
    try {
      final r = await widget.apiService.browseNativeDirectory();
      if (r['path'] != null) setState(() => _pathCtrl.text = r['path']);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Kunde inte öppna bläddraren: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isBrowsingDirectory = false);
    }
  }

  Future<void> _triggerScanOfSpecificPath(String folderPath, String type) async {
    setState(() {
      _isScanning = true;
      _currentlyScanningPath = folderPath;
      _scanLog = [];
      _lastScanEventId = 0;
    });
    try {
      final r = await widget.apiService.triggerLibraryScan(
        folderPath, type, preferLocalNfo: _preferLocalNfo,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['message'] ?? 'Skanning startad!'),
        backgroundColor: const Color(0xFF8A5BFF),
      ));
      _startScanEventPolling();
      _pollScannerUntilFinished();
    } catch (e) {
      setState(() => _isScanning = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _triggerScanAllPaths(List<dynamic> paths) async {
    for (final p in paths) {
      if (_isScanning) break;
      await _triggerScanOfSpecificPath(p['path'] as String, p['type'] as String);
      // Wait until this scan finishes before starting the next
      while (_isScanning) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }

  void _startScanEventPolling() {
    _scanEventTimer?.cancel();
    _scanEventTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      if (!_isScanning) {
        _scanEventTimer?.cancel();
        return;
      }
      try {
        final result = await widget.apiService.fetchScanEvents(sinceId: _lastScanEventId);
        final events = (result['events'] as List<dynamic>?) ?? [];
        if (events.isNotEmpty && mounted) {
          setState(() {
            for (final e in events) {
              _scanLog.add(Map<String, dynamic>.from(e as Map));
              if (_scanLog.length > 200) _scanLog.removeAt(0);
            }
            _lastScanEventId = (events.last['id'] as int?) ?? _lastScanEventId;
          });
        }
      } catch (_) {}
    });
  }

  void _pollScannerUntilFinished() async {
    for (int i = 0; i < 300 && _isScanning; i++) {
      await Future.delayed(const Duration(seconds: 2));
      await _checkScannerStatus();
      if (!_isScanning) {
        _scanEventTimer?.cancel();
        widget.onLibraryChanged?.call();
        _loadLibraryPaths(); // Refresh counts
        break;
      }
    }
  }

  // ─────────────────────────────────────────────
  //  Build — full-page med dashboard-stil sidebar
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0714),
      body: Row(
        children: [
          _buildSidebar(),
          Container(width: 1, color: Colors.white.withValues(alpha: 0.06)),
          Expanded(
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    const activeColor = Color(0xFFB593FF);
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
              boxShadow: enabled
                  ? [BoxShadow(color: activeColor.withValues(alpha: 0.12), blurRadius: 8)]
                  : [],
            ),
            child: Icon(
              icon,
              color: enabled ? Colors.white : Colors.white24,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      color: const Color(0xFF0F0B21),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 35),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nav buttons — same style as dashboard
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      _buildNavButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: 'Gå tillbaka',
                        enabled: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      _buildNavButton(
                        icon: Icons.home_rounded,
                        tooltip: 'Hem',
                        enabled: true,
                        onPressed: () {
                          widget.onNavigateHome?.call();
                          Navigator.of(context).pop();
                        },
                      ),
                      const SizedBox(width: 12),
                      _buildNavButton(
                        icon: Icons.arrow_forward_ios_rounded,
                        tooltip: 'Gå framåt',
                        enabled: false,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
                // LOOM logo — same as dashboard
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.play_circle_fill,
                            color: Color(0xFF8A5BFF),
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'LOOM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          // ── Kategorilista ───────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              itemCount: _cats.length,
              itemBuilder: (_, i) {
                final (outlineIcon, filledIcon, label) = _cats[i];
                final selected = _selectedCategory == i;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _selectedCategory = i);
                      if (i == 8) { _startLogPolling(); } else { _stopLogPolling(); }
                      if (i == 7) { _startStatsPolling(); } else { _stopStatsPolling(); }
                      if (i == 5 && _rssFeeds.isEmpty) _loadRssFeeds();
                      if (i == 9) _loadServerInfo();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF8A5BFF).withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? const Color(0xFF8A5BFF).withValues(alpha: 0.2) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected ? filledIcon : outlineIcon,
                            color: selected ? const Color(0xFFB593FF) : Colors.white54,
                            size: 22,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            label,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white60,
                              fontSize: 16,
                              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return switch (_selectedCategory) {
      0 => _buildKonto(),
      1 => _buildAnvandare(),
      2 => _buildBibliotek(),
      3 => _buildPapperskorg(),
      4 => _buildUppspelning(),
      5 => _buildKallor(),
      6 => _buildNotifieringar(),
      7 => _buildStatistik(),
      8 => _buildLoggning(),
      9 => _buildServer(),
      10 => _buildDiskutrymme(),
      _ => const SizedBox(),
    };
  }

  // ─────────────────────────────────────────────
  //  Category: Bibliotek
  // ─────────────────────────────────────────────
  Widget _buildBibliotek() {
    return DefaultTabController(
      length: 3,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Sub-tab bar
                Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.01),
                    borderRadius: BorderRadius.circular(12),
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
                      Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.movie_outlined, size: 16), SizedBox(width: 6), Text('Filmer')])),
                      Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.tv_outlined, size: 16), SizedBox(width: 6), Text('TV-Serier')])),
                      Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.music_note_outlined, size: 16), SizedBox(width: 6), Text('Musik')])),
                    ],
                  ),
                ),
                // Metadata section
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _buildSection('Metadata', Icons.translate_outlined, [
                    Row(children: [
                      Expanded(child: _buildDropdown('Metadataspråk', _metadataLanguage, ['sv-SE', 'en-US', 'no-NO'], (v) { setState(() => _metadataLanguage = v!); _scheduleSave(); })),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown('Fallback-språk', _fallbackLanguage, ['sv-SE', 'en-US', 'no-NO'], (v) { setState(() => _fallbackLanguage = v!); _scheduleSave(); })),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown('JustWatch-region', _watchProviderRegion, ['SE', 'US', 'NO', 'GB'], (v) { setState(() => _watchProviderRegion = v!); _scheduleSave(); })),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown('Titeldisplay', _titleDisplayStyle, ['Translated', 'Original'], (v) { setState(() => _titleDisplayStyle = v!); _scheduleSave(); })),
                    ]),
                    const SizedBox(height: 12),
                    _switchTile('Föredra lokal NFO-metadata', 'Använd .nfo-filer framför online-metadata.', _preferLocalNfo, _setPreferLocalNfo),
                  ]),
                ),
              ],
            ),
          ),
        ],
        body: TabBarView(children: [
          _buildScannerSubTab('Movie'),
          _buildScannerSubTab('Show'),
          _buildScannerSubTab('Music'),
        ]),
      ),
    );
  }

  Widget _buildScannerSubTab(String type) {
    final paths = _libraryPaths.where((p) => p['type'] == type).toList();
    final typeLabel = type == 'Show' ? 'TV-seriemappar' : type == 'Movie' ? 'filmmappar' : 'musikmappar';
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Konfigurerade $typeLabel',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isScanning)
                const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))))
              else if (paths.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _triggerScanAllPaths(paths),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Skanna alla'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (paths.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.01),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Text('Inga mappar tillagda för $typeLabel.',
                  style: const TextStyle(color: Colors.white24)),
            )
          else
            ...paths.map((p) => _buildFolderListItem(p)),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          Text(
            'Lägg till ${type == 'Show' ? 'TV-seriemapp' : type == 'Movie' ? 'filmmapp' : 'musikmapp'}',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildAddFolderForm(type),
          const SizedBox(height: 24),
          const Divider(color: Colors.white10),
          const SizedBox(height: 16),
          _buildScanFilterSection(),
          if (type == 'Show') ...[],
        ],
      ),
    );
  }

  Widget _buildScanFilterSection() {
    return _buildSection('Skanningfilter', Icons.filter_list, [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hoppa över ord i filnamn',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: _scanSkipWordsCtrl,
            onChanged: (_) => _scheduleSave(),
            style: const TextStyle(color: Colors.white),
            contextMenuBuilder: (ctx, state) =>
                AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
            decoration: InputDecoration(
              hintText: 'commentary, extras, trailer, sample...',
              hintStyle: TextStyle(color: Colors.white24),
              fillColor: Colors.white.withValues(alpha: 0.04),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              helperText: 'Kommaseparerade ord. Filer vars namn innehåller dessa hoppar över.',
              helperStyle: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Minsta filstorlek (MB)',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _scanMinSizeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _scheduleSave(),
                      style: const TextStyle(color: Colors.white),
                      contextMenuBuilder: (ctx, state) =>
                          AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: Colors.white24),
                        fillColor: Colors.white.withValues(alpha: 0.04),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        helperText: '0 = ingen begränsning',
                        helperStyle: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: const SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ),
    ]);
  }

  Widget _buildExportSection() {
    return _buildSection('Exportera data', Icons.download_outlined, [
      Text(
        'Exportera din sedda-status och betyg från hela biblioteket.',
        style: TextStyle(color: Colors.white54, fontSize: 13),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            icon: const Icon(Icons.data_object, size: 18),
            label: const Text('Exportera JSON'),
            onPressed: () => _doWatchedExport('json'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('Exportera CSV'),
            onPressed: () => _doWatchedExport('csv'),
          ),
        ],
      ),
    ]);
  }

  Future<void> _doWatchedExport(String format) async {
    try {
      final bytes = await widget.apiService.exportWatched(format: format);
      final ext = format == 'csv' ? 'csv' : 'json';
      final filename = 'loom-export-${DateTime.now().toIso8601String().substring(0, 10)}.$ext';

      if (kIsWeb) {
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Spara export',
          fileName: filename,
          type: FileType.any,
        );
        if (savePath == null) return;
        await File(savePath).writeAsBytes(bytes);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export sparad: $savePath'),
          backgroundColor: Colors.greenAccent.shade700,
        ));
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Export nedladdad!'),
        backgroundColor: Colors.greenAccent,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export misslyckades: $e'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Widget _buildFolderListItem(dynamic p) {
    final isThisScanning = _isScanning && (_currentlyScanningPath == p['path'] || _currentlyScanningPath == null);
    final mediaCount = (p['media_count'] as int?) ?? 0;
    final watchEnabled = (p['watch_for_changes'] == 1 || p['watch_for_changes'] == true);
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, color: const Color(0xFFB593FF).withValues(alpha: 0.8), size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p['path'], style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8A5BFF).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$mediaCount ${p['type'] == 'Movie' ? 'filmer' : p['type'] == 'Show' ? 'avsnitt' : 'låtar'}',
                                style: const TextStyle(color: Color(0xFFB593FF), fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () async {
                                final newVal = !watchEnabled;
                                try {
                                  await widget.apiService.toggleWatchPath(p['id'] as String, newVal);
                                  setState(() {
                                    p['watch_for_changes'] = newVal ? 1 : 0;
                                  });
                                } catch (_) {}
                              },
                              child: Row(
                                children: [
                                  Icon(
                                    watchEnabled ? Icons.remove_red_eye : Icons.visibility_off_outlined,
                                    size: 14,
                                    color: watchEnabled ? Colors.greenAccent : Colors.white38,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Bevaka',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: watchEnabled ? Colors.greenAccent : Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showEditPathDialog(p),
                    icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                    tooltip: 'Redigera',
                  ),
                  IconButton(
                    onPressed: _isScanning ? null : () => _triggerScanOfSpecificPath(p['path'], p['type']),
                    icon: const Icon(Icons.sync_outlined, color: Colors.greenAccent, size: 20),
                    tooltip: 'Skanna nu',
                  ),
                  IconButton(
                    onPressed: () => _deletePath(p['id']),
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    tooltip: 'Ta bort',
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isThisScanning && _isScanning) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: const LinearProgressIndicator(
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8A5BFF)),
                minHeight: 3,
              ),
            ),
          ),
          if (_scanLog.isNotEmpty) _buildScanLogPanel(),
        ],
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildScanLogPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.all(10),
      height: 160,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ListView.builder(
        reverse: true,
        itemCount: _scanLog.length,
        itemBuilder: (context, i) {
          final event = _scanLog[_scanLog.length - 1 - i];
          final type = event['type'] as String? ?? '';
          Color color;
          IconData icon;
          switch (type) {
            case 'item_added': color = Colors.greenAccent; icon = Icons.add_circle_outline; break;
            case 'item_updated': color = Colors.blueAccent; icon = Icons.update; break;
            case 'item_skipped': color = Colors.white38; icon = Icons.skip_next; break;
            case 'scan_start': color = const Color(0xFF8A5BFF); icon = Icons.play_arrow; break;
            case 'scan_complete': color = Colors.greenAccent; icon = Icons.check_circle_outline; break;
            case 'scan_error': color = Colors.redAccent; icon = Icons.error_outline; break;
            default: color = Colors.white54; icon = Icons.info_outline;
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 13, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event['message'] as String? ?? '',
                    style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddFolderForm(String type) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.01),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pathCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  contextMenuBuilder: (ctx, state) =>
                      AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                  decoration: _inputDeco('Ange sökväg eller klicka Bläddra...'),
                ),
              ),
              const SizedBox(width: 12),
              _browseButton(browsing: _isBrowsingDirectory, onTap: _selectFolderNatively),
            ],
          ),
          const SizedBox(height: 12),
          _switchTile('Föredra lokal NFO-metadata',
              'Importera från .nfo-filer istället för online.',
              _preferLocalNfo, _setPreferLocalNfo),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final folder = _pathCtrl.text.trim();
                if (folder.isNotEmpty) {
                  _addNewPath(folder, type);
                  _pathCtrl.clear();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Välj eller ange en mappsökväg')),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: Text(
                'Lägg till ${type == 'Show' ? 'TV-seriemapp' : type == 'Movie' ? 'filmmapp' : 'musikmapp'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  // ─────────────────────────────────────────────
  //  Category: Uppspelning
  // ─────────────────────────────────────────────
  Widget _buildResolutionPriorityList() {
    final items = _versionPriority.split(',').map((s) => s.trim()).toList();

    return SizedBox(
      height: 52,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        proxyDecorator: (child, _, __) => Material(
          color: Colors.transparent,
          child: child,
        ),
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            final item = items.removeAt(oldIndex);
            items.insert(newIndex, item);
            _versionPriority = items.join(',');
          });
          _scheduleSave();
        },
        children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              key: ValueKey(items[i]),
              padding: const EdgeInsets.only(right: 8),
              child: ReorderableDragStartListener(
                index: i,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5BFF).withValues(alpha: i == 0 ? 0.20 : 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF8A5BFF).withValues(alpha: i == 0 ? 0.50 : 0.20),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i == 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.star, color: const Color(0xFFB593FF), size: 14),
                        ),
                      Text(
                        items[i],
                        style: TextStyle(
                          color: i == 0 ? Colors.white : Colors.white60,
                          fontSize: 14,
                          fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.drag_indicator, color: Colors.white.withValues(alpha: 0.3), size: 16),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUppspelning() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildSection('Standardspråk', Icons.language_outlined, [
            Row(children: [
              Expanded(child: _buildDropdown('Standardljudspråk', _defaultAudioLanguage, ['sv', 'en', 'no'], (v) { setState(() => _defaultAudioLanguage = v!); _scheduleSave(); })),
              const SizedBox(width: 16),
              Expanded(child: _buildDropdown('Standardundertextspråk', _defaultSubLangCtrl.text, ['sv', 'en', 'no', 'None'], (v) { if (v != null) { setState(() => _defaultSubLangCtrl.text = v); _scheduleSave(); } })),
            ]),
          ]),
          const SizedBox(height: 16),
          _buildSection('Standardversion', Icons.layers_outlined, [
            Text(
              'Dra för att ändra ordning — överst = högst prioritet',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildResolutionPriorityList(),
            const SizedBox(height: 6),
            Text(
              'Styr vilken version som väljs automatiskt när en film har flera versioner.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11, height: 1.5),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection('TV-Serier', Icons.tv_outlined, [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visa kommande avsnitt', style: TextStyle(color: Colors.white70, fontSize: 14)),
              subtitle: const Text('Visar ej tillgängliga avsnitt som gråade i avsnittslistan', style: TextStyle(color: Colors.white38, fontSize: 12)),
              value: _showUpcomingEpisodes,
              onChanged: (v) {
                setState(() => _showUpcomingEpisodes = v);
                _scheduleSave();
              },
              activeColor: const Color(0xFF8A5BFF),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection('Fönster', Icons.window_outlined, [
            _switchTile('Alltid överst', 'Håller Loom-fönstret ovanpå alla andra fönster.',
                _alwaysOnTop, (val) async {
              if (!kIsWeb) {
                try {
                  await windowManager.setAlwaysOnTop(val);
                  setState(() => _alwaysOnTop = val);
                  _scheduleSave();
                } catch (_) {}
              }
            }),
          ]),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Category: Källor & Integrationer
  // ─────────────────────────────────────────────
  Widget _buildKallor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildAutoSaveIndicator(),
              const SizedBox(width: 12),
              if (_isManualSyncing) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF00E676)))),
                      const SizedBox(width: 8),
                      Text('${(_manualSyncProgress * 100).toInt()}% — $_manualSyncStep',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    foregroundColor: const Color(0xFF00E676),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: const Color(0xFF00E676).withValues(alpha: 0.4))),
                  ),
                  onPressed: _startManualSync,
                  icon: const Icon(Icons.sync, color: Color(0xFF00E676)),
                  label: const Text('Synkronisera nu', style: TextStyle(color: Colors.white)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          _buildSection('TMDB', Icons.movie_outlined, [
            _buildField('TMDB API-nyckel', _tmdbKeyCtrl, obscure: true),
            const SizedBox(height: 12),
            _buildField('TMDB User Auth', _tmdbAuthCtrl, obscure: true),
          ]),
          const SizedBox(height: 16),
          _buildSection('OMDb', Icons.star_outlined, [
            _buildField('OMDb API-nyckel', _omdbKeyCtrl, obscure: true),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _openUrl('https://www.omdbapi.com/apikey.aspx'),
              child: const Text('Skaffa en gratis OMDb API-nyckel här',
                  style: TextStyle(color: Colors.white38, fontSize: 11, decoration: TextDecoration.underline)),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSection('Simkl', Icons.link_outlined, [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Simkl Integration', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => _openUrl('https://simkl.com/settings/developer/'),
                  icon: const Icon(Icons.open_in_new, size: 12, color: Colors.green),
                  label: const Text('Skapa Simkl App', style: TextStyle(color: Colors.green, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildField('Simkl Client ID', _simklKeyCtrl, obscure: true),
            const SizedBox(height: 10),
            _buildField('Simkl Client Secret', _simklSecretCtrl, obscure: true),
            const SizedBox(height: 6),
            Text('Redirect URI: http://localhost:8080/api/oauth/simkl/callback',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            const SizedBox(height: 12),
            _buildOAuthRow(
              label: 'Simkl',
              isConnected: _simklTokenCtrl.text.isNotEmpty,
              color: Colors.green,
              onTap: () async {
                if (_simklTokenCtrl.text.isNotEmpty) {
                  setState(() => _simklTokenCtrl.clear());
                  await _saveSettings();
                } else {
                  await _saveSettings();
                  await _openUrl('${widget.apiService.baseUrl}/api/oauth/simkl/authorize');
                  Timer.periodic(const Duration(seconds: 2), (timer) async {
                    if (timer.tick > 30) { timer.cancel(); return; }
                    final s = await widget.apiService.getSettings();
                    if ((s['SIMKL_ACCESS_TOKEN'] ?? '').toString().isNotEmpty) {
                      setState(() => _simklTokenCtrl.text = s['SIMKL_ACCESS_TOKEN']);
                      timer.cancel();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Simkl ansluten! ✅'), backgroundColor: Colors.green),
                      );
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            _buildField('Simkl Access Token', _simklTokenCtrl, obscure: true),
            if (_simklTokenCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              _syncOptions('Simkl', Colors.green, _syncSimklRatings, _syncSimklWatched,
                  (v) { setState(() => _syncSimklRatings = v); _scheduleSave(); },
                  (v) { setState(() => _syncSimklWatched = v); _scheduleSave(); }),
            ],
          ]),
          const SizedBox(height: 16),
          _buildSection('Trakt.tv', Icons.movie_filter_outlined, [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Trakt.tv Integration', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => _openUrl('https://trakt.tv/oauth/applications'),
                  icon: const Icon(Icons.open_in_new, size: 12, color: Colors.redAccent),
                  label: const Text('Skapa Trakt App', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildField('Trakt API Key (Client ID)', _traktKeyCtrl, obscure: true),
            const SizedBox(height: 10),
            _buildField('Trakt Client Secret', _traktSecretCtrl, obscure: true),
            const SizedBox(height: 6),
            Text('Redirect URI: http://localhost:8080/api/oauth/trakt/callback',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            const SizedBox(height: 12),
            _buildOAuthRow(
              label: 'Trakt.tv',
              isConnected: _traktTokenCtrl.text.isNotEmpty,
              color: Colors.redAccent,
              onTap: () async {
                if (_traktTokenCtrl.text.isNotEmpty) {
                  setState(() => _traktTokenCtrl.clear());
                  await _saveSettings();
                } else {
                  await _saveSettings();
                  await _openUrl('${widget.apiService.baseUrl}/api/oauth/trakt/authorize');
                  Timer.periodic(const Duration(seconds: 2), (timer) async {
                    if (timer.tick > 30) { timer.cancel(); return; }
                    final s = await widget.apiService.getSettings();
                    if ((s['TRAKT_ACCESS_TOKEN'] ?? '').toString().isNotEmpty) {
                      setState(() => _traktTokenCtrl.text = s['TRAKT_ACCESS_TOKEN']);
                      timer.cancel();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Trakt.tv ansluten! ✅'), backgroundColor: Colors.green),
                      );
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            _buildField('Trakt Access Token', _traktTokenCtrl, obscure: true),
            if (_traktTokenCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              _syncOptions('Trakt.tv', Colors.redAccent, _syncTraktRatings, _syncTraktWatched,
                  (v) { setState(() => _syncTraktRatings = v); _scheduleSave(); },
                  (v) { setState(() => _syncTraktWatched = v); _scheduleSave(); }),
            ],
          ]),
          const SizedBox(height: 16),
          // ── IMDb ─────────────────────────────
          _buildSection('IMDb', Icons.star_rate_outlined, [
            // Rubrik
            const Text(
              'IMDb Watchlist',
              style: TextStyle(color: Color(0xFFF5C518), fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Viktig info om offentlig lista
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5C518).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF5C518).withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFF5C518), size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Din IMDb-watchlist måste vara offentlig',
                          style: TextStyle(color: Color(0xFFF5C518), fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Gå till din Watchlist på imdb.com → kopiera URL:en från adressfältet (t.ex. imdb.com/list/ls003160623) → klistra in den nedan. Se till att "Public" är On.',
                          style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // User ID-fält
            const Text(
              'IMDb User ID',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final raw = _imdbUserIdCtrl.text.trim();
              // Extract ls/ur ID from pasted URL or bare ID
              final lsId = RegExp(r'ls\d+').firstMatch(raw)?.group(0);
              final urId = RegExp(r'ur[\w]+').firstMatch(raw)?.group(0);
              final isDigitsOnly = RegExp(r'^\d+$').hasMatch(raw);
              final isValid = raw.isEmpty || lsId != null || urId != null || isDigitsOnly;
              final hasError = raw.isNotEmpty && !isValid;

              String? errorText;
              if (hasError) {
                errorText = 'Ogiltigt format. Klistra in din watchlist-URL (t.ex. https://www.imdb.com/list/ls003160623) eller bara ID:t (ls003160623 / ur12345678).';
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _imdbUserIdCtrl,
                    onChanged: (_) { setState(() {}); _scheduleSave(); },
                    style: TextStyle(color: hasError ? Colors.redAccent : Colors.white),
                    contextMenuBuilder: (ctx, state) =>
                        AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                    decoration: InputDecoration(
                      hintText: 'https://www.imdb.com/list/ls003160623  eller bara  ls003160623',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12),
                      filled: true,
                      fillColor: hasError
                          ? Colors.redAccent.withValues(alpha: 0.06)
                          : Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: hasError ? Colors.redAccent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: hasError ? Colors.redAccent : const Color(0xFFF5C518)),
                      ),
                      prefixIcon: Icon(
                        hasError ? Icons.error_outline : Icons.person_outline,
                        color: hasError ? Colors.redAccent : const Color(0xFFF5C518),
                        size: 18,
                      ),
                      suffixText: (!hasError && raw.isNotEmpty) ? '✓' : '',
                      suffixStyle: const TextStyle(color: Color(0xFFF5C518)),
                    ),
                  ),
                  if (hasError && errorText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Colors.redAccent, size: 15),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorText,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Hitta ditt User ID: gå till imdb.com, logga in → klicka din profilbild → "Ditt konto" → titta på URL:en: imdb.com/user/ur12345678/',
                        style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ] else if (!hasError && raw.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      lsId != null
                          ? 'RSS: rss.imdb.com/list/$lsId/'
                          : urId != null
                              ? 'RSS: rss.imdb.com/user/$urId/watchlist'
                              : 'RSS: rss.imdb.com/user/ur$raw/watchlist',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
                    ),
                  ],
                ],
              );
            }),
          ]),
          const SizedBox(height: 16),
          // ── RSS ──────────────────────────────
          _buildSection('RSS-flöden', Icons.rss_feed_outlined, [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_rssFeeds.length} flöden', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Row(children: [
                  if (_isRefreshingRss)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))))
                  else
                    TextButton.icon(
                      onPressed: _rssRefresh,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Uppdatera', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFB593FF)),
                    ),
                  if (_rssFeeds.isEmpty && !_isLoadingRss)
                    const SizedBox.shrink()
                  else
                    IconButton(
                      onPressed: _isLoadingRss ? null : _loadRssFeeds,
                      icon: const Icon(Icons.sync, color: Colors.white24, size: 16),
                      tooltip: 'Ladda om lista',
                    ),
                ]),
              ],
            ),
            const SizedBox(height: 8),
            if (_rssFeeds.isEmpty && !_isLoadingRss)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: const Text('Inga RSS-flöden tillagda', style: TextStyle(color: Colors.white24, fontSize: 13)),
              )
            else
              ..._rssFeeds.map((f) => _buildRssFeedItem(f as Map<String, dynamic>)),
            const SizedBox(height: 12),
            // Lägg till flöde
            Row(children: [
              Expanded(child: TextField(
                controller: _rssFeedUrlCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                contextMenuBuilder: (ctx, state) =>
                    AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                decoration: _inputDeco('https://exempel.com/feed.rss'),
              )),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                onPressed: _isLoadingRss ? null : _addRssFeed,
                icon: _isLoadingRss
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : const Icon(Icons.add, size: 16),
                label: const Text('Lägg till', style: TextStyle(fontSize: 13)),
              ),
            ]),
            if (_rssItems.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 8),
              const Text('Senaste poster', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              ..._rssItems.take(10).map((item) => _buildRssItem(item as Map<String, dynamic>)),
            ],
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _loadRssFeeds() async {
    if (_isLoadingRss) return;
    setState(() => _isLoadingRss = true);
    try {
      final feeds = await widget.apiService.fetchRssFeeds();
      final items = await widget.apiService.fetchRssItems();
      if (mounted) setState(() { _rssFeeds = feeds; _rssItems = items; });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingRss = false);
    }
  }

  Future<void> _addRssFeed() async {
    final url = _rssFeedUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _isLoadingRss = true);
    try {
      await widget.apiService.addRssFeed(url);
      _rssFeedUrlCtrl.clear();
      await _loadRssFeeds();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RSS-flöde tillagt!'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoadingRss = false);
    }
  }

  Future<void> _rssRefresh() async {
    setState(() => _isRefreshingRss = true);
    try {
      final result = await widget.apiService.refreshRssFeeds();
      await _loadRssFeeds();
      if (!mounted) return;
      final n = result['newItems'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(n > 0 ? '$n nya poster hämtade!' : 'Allt redan uppdaterat.'), backgroundColor: const Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isRefreshingRss = false);
    }
  }

  Widget _buildRssFeedItem(Map<String, dynamic> feed) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        const Icon(Icons.rss_feed, color: Color(0xFFB593FF), size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(feed['title'] as String? ?? feed['url'] as String,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
          Text(feed['url'] as String? ?? '',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ])),
        IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
          onPressed: () async {
            try {
              await widget.apiService.deleteRssFeed(feed['id'] as String);
              _loadRssFeeds();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent));
            }
          },
          tooltip: 'Ta bort',
        ),
      ]),
    );
  }

  Widget _buildRssItem(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 4, height: 4, margin: const EdgeInsets.only(top: 6, right: 10),
          decoration: const BoxDecoration(color: Color(0xFF8A5BFF), shape: BoxShape.circle),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item['title'] as String? ?? '—',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis),
          Text(item['feed_title'] as String? ?? '',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
        ])),
      ]),
    );
  }

  // ─────────────────────────────────────────────
  //  Category: Notifieringar
  // ─────────────────────────────────────────────
  Widget _buildNotifieringar() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Discord ──────────────────────────────
          _buildSection('Discord', Icons.forum_outlined, [
            _buildField('Webhook-URL', _discordWebhookCtrl),
            const SizedBox(height: 8),
            Text(
              'Skapa en Incoming Webhook i Discord-kanalens inställningar och klistra in URL:en ovan.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 14),
            _buildTestButton(
              label: 'Skicka testmeddelande',
              icon: Icons.send_outlined,
              color: const Color(0xFF5865F2),
              isTesting: _isTestingDiscord,
              result: _discordTestResult,
              onTap: _testDiscord,
            ),
          ]),
          const SizedBox(height: 16),
          // ── E-post (SMTP) ────────────────────────
          _buildSection('E-post via SMTP', Icons.email_outlined, [
            Row(children: [
              Expanded(flex: 3, child: _buildField('SMTP-server (host)', _smtpHostCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _buildField('Port', _smtpPortCtrl)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _buildField('Användarnamn', _smtpUserCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _buildField('Lösenord', _smtpPassCtrl, obscure: true)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _buildField('Avsändaradress (From)', _smtpFromCtrl)),
              const SizedBox(width: 12),
              Expanded(child: _buildField('Mottagaradress (To)', _smtpToCtrl)),
            ]),
            const SizedBox(height: 14),
            _buildTestButton(
              label: 'Skicka testmejl',
              icon: Icons.mail_outline,
              color: const Color(0xFF8A5BFF),
              isTesting: _isTestingEmail,
              result: _emailTestResult,
              onTap: _testEmail,
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTestButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isTesting,
    required bool? result,
    required VoidCallback onTap,
  }) {
    return Row(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: color.withValues(alpha: 0.12),
            foregroundColor: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: isTesting ? null : onTap,
          icon: isTesting
              ? SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(color)))
              : Icon(icon, size: 16),
          label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        if (result != null) ...[
          const SizedBox(width: 12),
          Icon(
            result ? Icons.check_circle : Icons.error_outline,
            color: result ? Colors.greenAccent : Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 6),
          Text(
            result ? 'Skickat!' : 'Misslyckades',
            style: TextStyle(
              color: result ? Colors.greenAccent : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  Logging helpers
  // ─────────────────────────────────────────────
  void _startLogPolling() {
    _logPollTimer?.cancel();
    _fetchLogs(); // immediate first fetch
    _logPollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchLogs());
  }

  void _stopLogPolling() {
    _logPollTimer?.cancel();
    _logPollTimer = null;
  }

  Future<void> _fetchLogs() async {
    if (_logPaused) return;
    try {
      final data = await widget.apiService.fetchLogs(sinceId: _lastLogId > 0 ? _lastLogId : null);
      final entries = (data['entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (!mounted || entries.isEmpty) return;
      setState(() {
        _logEntries.addAll(entries);
        if (_logEntries.length > 1000) {
          _logEntries.removeRange(0, _logEntries.length - 1000);
        }
        _lastLogId = entries.last['id'] as int;
      });
      if (_logAutoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScrollCtrl.hasClients) {
            _logScrollCtrl.animateTo(
              _logScrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (_) {}
  }

  void _clearLogs() => setState(() { _logEntries.clear(); _lastLogId = 0; });

  Future<void> _testDiscord() async {
    setState(() { _isTestingDiscord = true; _discordTestResult = null; });
    try {
      await _saveSettings();
      final res = await widget.apiService.testDiscordWebhook();
      if (!mounted) return;
      setState(() => _discordTestResult = res['success'] == true);
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Discord-fel: ${res['error'] ?? 'Okänt fel'}'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _discordTestResult = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isTestingDiscord = false);
    }
  }

  Future<void> _testEmail() async {
    setState(() { _isTestingEmail = true; _emailTestResult = null; });
    try {
      await _saveSettings();
      final res = await widget.apiService.testEmail();
      if (!mounted) return;
      setState(() => _emailTestResult = res['success'] == true);
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('E-postfel: ${res['error'] ?? 'Okänt fel'}'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _emailTestResult = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'),
        backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isTestingEmail = false);
    }
  }

  // ─────────────────────────────────────────────
  //  Category: Loggning
  // ─────────────────────────────────────────────
  Widget _buildLoggning() {
    final levels = ['Alla', 'info', 'warn', 'error'];
    final filtered = _logLevelFilter == 'Alla'
        ? _logEntries
        : _logEntries.where((e) => e['level'] == _logLevelFilter).toList();

    return Column(
      children: [
        // ── Toolbar ────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.01),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              // Level filter
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _logLevelFilter,
                    dropdownColor: const Color(0xFF15102A),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: levels.map((l) => DropdownMenuItem(
                      value: l,
                      child: Text(l == 'Alla' ? 'Alla nivåer' : l.toUpperCase()),
                    )).toList(),
                    onChanged: (v) => setState(() => _logLevelFilter = v ?? 'Alla'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Pause toggle
              GestureDetector(
                onTap: () => setState(() => _logPaused = !_logPaused),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _logPaused
                        ? Colors.orangeAccent.withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _logPaused
                          ? Colors.orangeAccent.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _logPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 14,
                      color: _logPaused ? Colors.orangeAccent : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _logPaused ? 'Pausad' : 'Pausa',
                      style: TextStyle(
                        fontSize: 12,
                        color: _logPaused ? Colors.orangeAccent : Colors.white38,
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              // Auto-scroll toggle
              GestureDetector(
                onTap: () => setState(() => _logAutoScroll = !_logAutoScroll),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _logAutoScroll
                        ? const Color(0xFF8A5BFF).withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _logAutoScroll
                          ? const Color(0xFF8A5BFF).withValues(alpha: 0.3)
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.vertical_align_bottom,
                        size: 14,
                        color: _logAutoScroll ? const Color(0xFFB593FF) : Colors.white38),
                    const SizedBox(width: 6),
                    Text('Auto-scroll',
                        style: TextStyle(
                          fontSize: 12,
                          color: _logAutoScroll ? const Color(0xFFB593FF) : Colors.white38,
                        )),
                  ]),
                ),
              ),
              const Spacer(),
              // Entry count
              Text('${filtered.length} rader',
                  style: const TextStyle(color: Colors.white24, fontSize: 12)),
              const SizedBox(width: 16),
              // Clear
              TextButton.icon(
                onPressed: _clearLogs,
                icon: const Icon(Icons.clear_all, size: 16, color: Colors.white38),
                label: const Text('Rensa', style: TextStyle(color: Colors.white38, fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const SizedBox(width: 8),
              // Download
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFFB593FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  elevation: 0,
                ),
                onPressed: _downloadLogs,
                icon: const Icon(Icons.download_outlined, size: 15),
                label: const Text('Ladda ner', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        // ── Log view ───────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.terminal_outlined, size: 40, color: Colors.white12),
                      const SizedBox(height: 12),
                      Text(
                        _logPollTimer != null ? 'Väntar på loggposter...' : 'Inga loggar',
                        style: const TextStyle(color: Colors.white24, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : SelectionArea(
                  child: ListView.builder(
                    controller: _logScrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _buildLogLine(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLogLine(Map<String, dynamic> entry) {
    final level = (entry['level'] as String?) ?? 'info';
    final msg = (entry['msg'] as String?) ?? '';
    final time = entry['time'] is int
        ? DateTime.fromMillisecondsSinceEpoch(entry['time'] as int)
        : DateTime.now();
    final timeStr = '${time.hour.toString().padLeft(2,'0')}:${time.minute.toString().padLeft(2,'0')}:${time.second.toString().padLeft(2,'0')}';

    final Color levelColor;
    final Color bgColor;
    switch (level) {
      case 'error':
        levelColor = Colors.redAccent;
        bgColor = Colors.redAccent.withValues(alpha: 0.04);
      case 'warn':
        levelColor = Colors.orangeAccent;
        bgColor = Colors.orangeAccent.withValues(alpha: 0.03);
      case 'debug':
        levelColor = Colors.blueAccent;
        bgColor = Colors.transparent;
      default:
        levelColor = Colors.white38;
        bgColor = Colors.transparent;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timeStr,
              style: const TextStyle(
                  color: Colors.white24, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Container(
            width: 38,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              level.toUpperCase(),
              style: TextStyle(color: levelColor, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                color: level == 'error' ? Colors.redAccent.withValues(alpha: 0.9) : Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Category: Server
  // ─────────────────────────────────────────────
  Future<void> _loadServerInfo() async {
    try {
      final info = await widget.apiService.fetchServerInfo();
      if (mounted) setState(() => _serverInfo = info);
    } catch (_) {}
  }

  Future<void> _optimizeDb() async {
    setState(() { _isOptimizing = true; _optimizeResult = null; });
    try {
      final res = await widget.apiService.optimizeDatabase();
      if (!mounted) return;
      setState(() {
        _optimizeResult = res['success'] == true;
        if (_optimizeResult == true) _loadServerInfo();
      });
    } catch (e) {
      if (mounted) setState(() => _optimizeResult = false);
    } finally {
      if (mounted) setState(() => _isOptimizing = false);
    }
  }

  Future<void> _downloadLogs() async {
    try {
      final bytes = await widget.apiService.downloadLogsBytes();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Spara loggfil',
        fileName: 'loom-logs-$date.txt',
        type: FileType.any,
      );
      if (savePath == null) return;
      await File(savePath).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logg sparad: $savePath'), backgroundColor: const Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export misslyckades: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _downloadBackup() async {
    try {
      final bytes = await widget.apiService.downloadBackupBytes();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Spara backup',
        fileName: 'loom-backup-$date.db',
        type: FileType.any,
      );
      if (savePath == null) return;
      await File(savePath).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup sparad: $savePath'), backgroundColor: const Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup misslyckades: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _restoreDb() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final bytes = result.files.single.bytes!;
    final name = result.files.single.name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text('Bekräfta återställning', style: TextStyle(color: Colors.white)),
        content: Text(
          'Den nuvarande databasen ersätts med "$name".\nServern startas om automatiskt.\n\nÄr du säker?',
          style: const TextStyle(color: Colors.white70, height: 1.5),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Återställ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRestoring = true);
    try {
      final res = await widget.apiService.restoreDatabase(bytes, name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message'] ?? 'Återställning pågår...'),
        backgroundColor: const Color(0xFF8A5BFF),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fel: $e'), backgroundColor: Colors.redAccent,
      ));
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _confirmRestartServer() async {
    final callerPayload = widget.apiService.currentUserPayload;
    if (callerPayload?['role'] != 'Admin') return;

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

    setState(() => _isRestarting = true);
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
    } finally {
      if (mounted) setState(() => _isRestarting = false);
    }
  }

  Widget _buildServer() {
    if (_serverInfo == null) Future.microtask(_loadServerInfo);
    final info = _serverInfo;
    final isAdmin = widget.apiService.currentUserPayload?['role'] == 'Admin';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Servernamn ────────────────────────
          _buildSection('Server', Icons.dns_outlined, [
            _buildField('Servernamn', _serverNameCtrl),
            const SizedBox(height: 8),
            if (info != null)
              Text('Port: ${info['port']}  •  Platform: ${info['platform']}  •  Node ${info['nodeVersion']}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            const SizedBox(height: 14),
            // Clock toggle
            Row(children: [
              const Icon(Icons.access_time_outlined, size: 16, color: Colors.white38),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Visa klocka', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                  Text('Klockan visas i sidomenyn, till höger om navigeringspilarna.',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ),
              Switch(
                value: _showClock,
                activeColor: const Color(0xFF8A5BFF),
                onChanged: (v) {
                  setState(() => _showClock = v);
                  // Spara direkt (ingen debounce) — annars hinner inte inställningen sparas
                  widget.apiService.updateSettings({'SHOW_CLOCK': v ? 'true' : 'false'}).catchError((_) {});
                },
              ),
            ]),
            if (isAdmin) ...[
              const SizedBox(height: 14),
              const Divider(color: Colors.white12),
              const SizedBox(height: 14),
              // Restart button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent.withValues(alpha: 0.10),
                    foregroundColor: Colors.orangeAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.35)),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _isRestarting ? null : _confirmRestartServer,
                  icon: _isRestarting
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.orangeAccent)))
                      : const Icon(Icons.restart_alt_rounded, size: 18),
                  label: Text(_isRestarting ? 'Startar om...' : 'Starta om servern',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          // ── Databasinformation ────────────────
          _buildSection('Databas', Icons.storage_outlined, [
            if (info == null)
              Center(child: TextButton.icon(
                onPressed: _loadServerInfo,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Hämta info'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFB593FF)),
              ))
            else ...[
              _infoRow(Icons.folder_outlined, 'Databasstorlek', _formatBytes(info['dbSizeBytes'] as int)),
              _infoRow(Icons.movie_outlined, 'Medieföremål', '${info['mediaCount']} titlar, ${info['episodeCount']} avsnitt'),
              _infoRow(Icons.people_outline, 'Användare', '${info['userCount']} st'),
              _infoRow(Icons.timer_outlined, 'Upptime', _formatUptime(info['uptimeSeconds'] as int)),
            ],
            const SizedBox(height: 14),
            // Optimize
            Row(children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFFB593FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3))),
                  elevation: 0,
                ),
                onPressed: _isOptimizing ? null : _optimizeDb,
                icon: _isOptimizing
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFB593FF))))
                    : const Icon(Icons.auto_fix_high_outlined, size: 16),
                label: const Text('Optimera databas', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (_optimizeResult != null) ...[
                const SizedBox(width: 12),
                Icon(_optimizeResult! ? Icons.check_circle : Icons.error_outline,
                    color: _optimizeResult! ? Colors.greenAccent : Colors.redAccent, size: 18),
                const SizedBox(width: 6),
                Text(_optimizeResult! ? 'Klar!' : 'Misslyckades',
                    style: TextStyle(color: _optimizeResult! ? Colors.greenAccent : Colors.redAccent, fontSize: 13)),
              ],
            ]),
          ]),
          const SizedBox(height: 16),
          // ── Backup & Återställning ─────────────
          _buildSection('Backup & Återställning', Icons.backup_outlined, [
            Text('Backup laddar ned hela databasen som en .db-fil. '
                'Återställning ersätter databasen och startar om servern.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5)),
            const SizedBox(height: 16),
            Row(children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.withValues(alpha: 0.12),
                  foregroundColor: Colors.tealAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.teal.withValues(alpha: 0.3))),
                  elevation: 0,
                ),
                onPressed: _downloadBackup,
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Ladda ned backup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                  foregroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3))),
                  elevation: 0,
                ),
                onPressed: _isRestoring ? null : _restoreDb,
                icon: _isRestoring
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.redAccent)))
                    : const Icon(Icons.restore_outlined, size: 16),
                label: const Text('Återställ från backup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          // ── Exportera / Importera inställningar ───
          _buildSection('Exportera / Importera inställningar', Icons.swap_vert_outlined, [
            Text('Välj vad du vill inkludera i ZIP-filen. Inställningar och biblioteksvägar är valda som standard.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _expChip('Inställningar', _expSettings, (v) => setState(() => _expSettings = v)),
              _expChip('Biblioteksvägar', _expLibraryPaths, (v) => setState(() => _expLibraryPaths = v)),
              _expChip('Användare', _expUsers, (v) => setState(() => _expUsers = v)),
              _expChip('Spelhistorik', _expWatchHistory, (v) => setState(() => _expWatchHistory = v)),
              _expChip('Bevakningslista', _expWatchlist, (v) => setState(() => _expWatchlist = v)),
              _expChip('Markörer', _expMarkers, (v) => setState(() => _expMarkers = v)),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFFB593FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: const Color(0xFF8A5BFF).withValues(alpha: 0.35))),
                  elevation: 0,
                ),
                onPressed: (_isExporting || (!_expSettings && !_expLibraryPaths && !_expUsers && !_expWatchHistory && !_expWatchlist && !_expMarkers))
                    ? null : _doExport,
                icon: _isExporting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFB593FF))))
                    : const Icon(Icons.download_outlined, size: 16),
                label: const Text('Exportera ZIP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                  foregroundColor: Colors.orangeAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.orange.withValues(alpha: 0.3))),
                  elevation: 0,
                ),
                onPressed: _isImporting ? null : _doImport,
                icon: _isImporting
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.orangeAccent)))
                    : const Icon(Icons.upload_outlined, size: 16),
                label: const Text('Importera ZIP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ]),
            if (_importResult != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Import slutförd:', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...(_importResult!['results'] as Map<String, dynamic>).entries.map((e) =>
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('• ${e.value}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          _buildExportSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _expChip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: value ? Colors.white : Colors.white54,
      )),
      selected: value,
      onSelected: onChanged,
      selectedColor: const Color(0xFF8A5BFF).withValues(alpha: 0.25),
      backgroundColor: Colors.white.withValues(alpha: 0.04),
      checkmarkColor: const Color(0xFFB593FF),
      side: BorderSide(color: value
          ? const Color(0xFF8A5BFF).withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      showCheckmark: true,
    );
  }

  Future<void> _doExport() async {
    setState(() { _isExporting = true; });
    try {
      final bytes = await widget.apiService.exportBackup(
        settings: _expSettings,
        libraryPaths: _expLibraryPaths,
        users: _expUsers,
        watchHistory: _expWatchHistory,
        watchlist: _expWatchlist,
        markers: _expMarkers,
      );
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final filename = 'loom_backup_$date.zip';
      if (kIsWeb) {
        final blob = html.Blob([Uint8List.fromList(bytes)], 'application/zip');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final savePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Spara backup-ZIP',
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        if (savePath != null) {
          await File(savePath).writeAsBytes(bytes);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup sparad: $savePath'), backgroundColor: const Color(0xFF8A5BFF)),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export misslyckades: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _doImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      dialogTitle: 'Välj backup-ZIP',
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    setState(() { _isImporting = true; _importResult = null; });
    try {
      final res = await widget.apiService.importBackup(bytes, file.name);
      if (mounted) setState(() => _importResult = res);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import misslyckades: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: const Color(0xFF8A5BFF)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String _formatUptime(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  // ─────────────────────────────────────────────
  //  Category: Statistik (steg 9)
  // ─────────────────────────────────────────────
  void _startStatsPolling() {
    _statsPollTimer?.cancel();
    _fetchStats();
    _statsPollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchStats());
  }

  void _stopStatsPolling() {
    _statsPollTimer?.cancel();
    _statsPollTimer = null;
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetchStats() async {
    try {
      final results = await Future.wait([
        widget.apiService.fetchStatsRealtime(),
        widget.apiService.fetchStatsHistory(
          userId: _statsSelectedUserId,
          days: (_statsDateFrom == null && _statsDaysFilter > 0) ? _statsDaysFilter : null,
          startDate: _statsDateFrom != null ? _formatDate(_statsDateFrom!) : null,
          endDate: _statsDateTo != null ? _formatDate(_statsDateTo!) : null,
          limit: 50,
        ),
        widget.apiService.fetchStatsUsers(),
        widget.apiService.fetchStatsTops(),
      ]);
      if (!mounted) return;
      setState(() {
        _statsError    = null;
        _statsRealtime = results[0] as Map<String, dynamic>;
        _statsHistory  = results[1] as Map<String, dynamic>;
        _statsUsers    = results[2] as List<dynamic>;
        _statsTops     = results[3] as Map<String, dynamic>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _statsError = e.toString());
    }
  }

  Future<void> _refreshHistory() async {
    setState(() => _statsHistoryLoading = true);
    try {
      final hist = await widget.apiService.fetchStatsHistory(
        userId: _statsSelectedUserId,
        days: (_statsDateFrom == null && _statsDaysFilter > 0) ? _statsDaysFilter : null,
        startDate: _statsDateFrom != null ? _formatDate(_statsDateFrom!) : null,
        endDate: _statsDateTo != null ? _formatDate(_statsDateTo!) : null,
        limit: 50,
      );
      if (mounted) setState(() { _statsHistory = hist; });
    } catch (_) {} finally {
      if (mounted) setState(() => _statsHistoryLoading = false);
    }
  }

  Future<void> _loadTopItemPlays(String mediaId) async {
    if (_topItemPlaysLoading[mediaId] == true) return;
    setState(() => _topItemPlaysLoading[mediaId] = true);
    try {
      final data = await widget.apiService.fetchMediaPlays(mediaId);
      if (mounted) {
        setState(() {
          _topItemPlays[mediaId] = data['plays'] as List<dynamic>? ?? [];
          _topItemPlaysLoading[mediaId] = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _topItemPlaysLoading[mediaId] = false);
    }
  }

  void _toggleTopItem(String mediaId) {
    final nowExpanded = !(_expandedTopItems[mediaId] == true);
    setState(() => _expandedTopItems[mediaId] = nowExpanded);
    if (nowExpanded && _topItemPlays[mediaId] == null) {
      _loadTopItemPlays(mediaId);
    }
  }

  Widget _buildStatistik() {
    if (_statsRealtime == null && _statsPollTimer == null) {
      Future.microtask(_startStatsPolling);
    }
    if (_statsUsers.isNotEmpty && _statsUsers.first is Map && !_statsUsers.first.containsKey('id')) {
      Future.microtask(_fetchStats);
    }

    if (_statsError != null && _statsRealtime == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
            const SizedBox(height: 12),
            const Text('Kunde inte hämta statistik',
                style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_statsError!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white30, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () { setState(() => _statsError = null); _startStatsPolling(); },
              icon: const Icon(Icons.refresh),
              label: const Text('Försök igen'),
            ),
          ],
        ),
      );
    }

    final rt   = _statsRealtime;
    final hist = _statsHistory;
    final tops = _statsTops;
    final allTime = hist?['allTimeTotals'] as Map<String, dynamic>?;

    return Column(
      children: [
        // ── Tab bar ──────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          ),
          child: Row(
            children: [
              for (final (i, label) in [
                (0, 'Överblick'), (1, 'Historik'), (2, 'Toppar'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _statsTabIndex = i);
                      widget.apiService.lastStatsTabIndex = i;
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _statsTabIndex == i
                            ? const Color(0xFF8A5BFF).withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _statsTabIndex == i
                              ? const Color(0xFF8A5BFF).withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: Text(label,
                          style: TextStyle(
                            color: _statsTabIndex == i ? const Color(0xFFB593FF) : Colors.white38,
                            fontSize: 13,
                            fontWeight: _statsTabIndex == i ? FontWeight.bold : FontWeight.normal,
                          )),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ── Tab content ──────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _statsTabIndex == 0
                ? _buildStatsOverview(rt, hist, allTime)
                : _statsTabIndex == 1
                    ? _buildStatsHistory(hist)
                    : _buildStatsTops(tops),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsOverview(
    Map<String, dynamic>? rt,
    Map<String, dynamic>? hist,
    Map<String, dynamic>? allTime,
  ) {
    return Column(
      children: [
        // ── 4 stora siffror ─────────────────────
        if (allTime != null) ...[
          Row(children: [
            Expanded(child: _dashStat(Icons.schedule_outlined, 'Total seendetid',
                _formatMinutes(((allTime['totalSeconds'] as num?) ?? 0).toInt() ~/ 60),
                const Color(0xFF8A5BFF))),
            const SizedBox(width: 12),
            Expanded(child: _dashStat(Icons.movie_outlined, 'Unika titlar',
                '${(allTime['uniqueTitles'] as num?) ?? 0}',
                Colors.tealAccent)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _dashStat(Icons.people_outline, 'Aktiva användare',
                '${(allTime['activeUsers'] as num?) ?? 0}',
                Colors.orangeAccent)),
            const SizedBox(width: 12),
            Expanded(child: _dashStat(Icons.history_outlined, 'Sedda (filtrerat)',
                '${hist?['totalWatched'] ?? 0}',
                Colors.greenAccent)),
          ]),
          const SizedBox(height: 20),
        ],
        // ── CPU/RAM ─────────────────────────────
        _buildSection('Serverresurser', Icons.speed_outlined, [
          if (rt == null)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))),
            ))
          else ...[
            _statGaugeRow(
              label: 'CPU',
              value: rt['cpuPercent'] as int,
              subtitle: '${rt['cpuCores']} kärnor  •  ${rt['cpuModel'] ?? ''}',
              color: _gaugeColor(rt['cpuPercent'] as int),
            ),
            const SizedBox(height: 14),
            _statGaugeRow(
              label: 'RAM',
              value: rt['memPercent'] as int,
              subtitle: '${_formatBytes(rt['usedMemBytes'] as int)} / ${_formatBytes(rt['totalMemBytes'] as int)}',
              color: _gaugeColor(rt['memPercent'] as int),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _miniStat(Icons.timer_outlined, 'Upptime', _formatUptime(rt['uptimeSeconds'] as int))),
              const SizedBox(width: 12),
              Expanded(child: _miniStat(Icons.storage_outlined, 'Databas', _formatBytes(rt['dbSizeBytes'] as int))),
            ]),
          ],
        ]),
        const SizedBox(height: 16),
        // ── Per-användare ─────────────────────
        _buildSection('Per användare', Icons.people_outline, [
          if (_statsUsers.isEmpty)
            const Center(child: Text('Ingen data', style: TextStyle(color: Colors.white24)))
          else
            ..._statsUsers.map((u) => _userStatRow(u as Map<String, dynamic>)),
        ]),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStatsHistory(Map<String, dynamic>? hist) {
    final recent = (hist?['recent'] as List<dynamic>?) ?? [];
    final hasDateFilter = _statsDateFrom != null || _statsDateTo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Filter rad 1: användare + snabbval ─
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _statsSelectedUserId,
                    dropdownColor: const Color(0xFF15102A),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    hint: const Text('Alla användare', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Alla användare')),
                      ..._statsUsers.map((u) {
                        final um = u as Map<String, dynamic>;
                        return DropdownMenuItem<String?>(
                          value: um['id'].toString(),
                          child: Text(um['username'] as String? ?? '?'),
                        );
                      }),
                    ],
                    onChanged: (v) {
                      setState(() => _statsSelectedUserId = v);
                      _refreshHistory();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: hasDateFilter
                    ? Colors.black.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasDateFilter
                      ? Colors.white.withValues(alpha: 0.03)
                      : Colors.white.withValues(alpha: 0.07),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: hasDateFilter ? 0 : _statsDaysFilter,
                  dropdownColor: const Color(0xFF15102A),
                  style: TextStyle(
                    color: hasDateFilter ? Colors.white24 : Colors.white,
                    fontSize: 13,
                  ),
                  items: const [
                    DropdownMenuItem(value: 0,  child: Text('Alla tider')),
                    DropdownMenuItem(value: 7,  child: Text('7 dagar')),
                    DropdownMenuItem(value: 30, child: Text('30 dagar')),
                    DropdownMenuItem(value: 90, child: Text('90 dagar')),
                  ],
                  onChanged: hasDateFilter ? null : (v) {
                    setState(() => _statsDaysFilter = v ?? 0);
                    _refreshHistory();
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_statsHistoryLoading)
              const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))),
          ],
        ),
        const SizedBox(height: 8),
        // ── Filter rad 2: datumintervall ────────
        Row(
          children: [
            _datePicker(
              label: 'Från',
              value: _statsDateFrom,
              lastDate: _statsDateTo ?? DateTime.now(),
              onPicked: (d) {
                setState(() {
                  _statsDateFrom = d;
                  _statsDaysFilter = 0;
                });
                _refreshHistory();
              },
              onClear: () {
                setState(() => _statsDateFrom = null);
                _refreshHistory();
              },
            ),
            const SizedBox(width: 8),
            _datePicker(
              label: 'Till',
              value: _statsDateTo,
              firstDate: _statsDateFrom ?? DateTime(2020),
              onPicked: (d) {
                setState(() {
                  _statsDateTo = d;
                  _statsDaysFilter = 0;
                });
                _refreshHistory();
              },
              onClear: () {
                setState(() => _statsDateTo = null);
                _refreshHistory();
              },
            ),
            if (hasDateFilter) ...[
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    setState(() { _statsDateFrom = null; _statsDateTo = null; });
                    _refreshHistory();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
                    ),
                    child: const Text('Rensa datum',
                        style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (recent.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Text('Ingen spelningshistorik',
                  style: TextStyle(color: Colors.white24, fontSize: 14)),
            ),
          )
        else
          ...recent.map((e) => _historyItem(e as Map<String, dynamic>)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _datePicker({
    required String label,
    required DateTime? value,
    DateTime? firstDate,
    DateTime? lastDate,
    required void Function(DateTime) onPicked,
    required VoidCallback onClear,
  }) {
    final active = value != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: firstDate ?? DateTime(2020),
            lastDate: lastDate ?? DateTime.now(),
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFF8A5BFF),
                  onPrimary: Colors.white,
                  surface: Color(0xFF1A1230),
                  onSurface: Colors.white,
                ),
                dialogBackgroundColor: const Color(0xFF1A1230),
              ),
              child: child!,
            ),
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF8A5BFF).withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? const Color(0xFF8A5BFF).withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today_outlined, size: 13,
                color: active ? const Color(0xFFB593FF) : Colors.white38),
            const SizedBox(width: 5),
            Text(
              active ? _formatDate(value!) : label,
              style: TextStyle(
                color: active ? Colors.white : Colors.white38,
                fontSize: 12,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 5),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 12, color: Colors.white38),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildStatsTops(Map<String, dynamic>? tops) {
    if (tops == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))),
        ),
      );
    }
    final topMovies = (tops['topMovies'] as List<dynamic>?) ?? [];
    final topShows  = (tops['topShows']  as List<dynamic>?) ?? [];
    final topUsers  = (tops['topUsers']  as List<dynamic>?) ?? [];

    return Column(
      children: [
        _buildSection('Mest sedda filmer', Icons.movie_outlined, [
          if (topMovies.isEmpty)
            const Text('Ingen data', style: TextStyle(color: Colors.white24))
          else
            ...topMovies.asMap().entries.map((e) => _topMediaRow(e.key + 1, e.value as Map<String, dynamic>, 'Movie')),
        ]),
        const SizedBox(height: 16),
        _buildSection('Mest sedda TV-serier', Icons.tv_outlined, [
          if (topShows.isEmpty)
            const Text('Ingen data', style: TextStyle(color: Colors.white24))
          else
            ...topShows.asMap().entries.map((e) => _topMediaRow(e.key + 1, e.value as Map<String, dynamic>, 'Show')),
        ]),
        const SizedBox(height: 16),
        _buildSection('Mest aktiva användare (30 dagar)', Icons.emoji_events_outlined, [
          if (topUsers.isEmpty)
            const Text('Ingen data', style: TextStyle(color: Colors.white24))
          else
            ...topUsers.asMap().entries.map((e) => _topUserRow(e.key + 1, e.value as Map<String, dynamic>)),
        ]),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _dashStat(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ])),
      ]),
    );
  }

  Widget _historyItem(Map<String, dynamic> e) {
    final year       = (e['year'] as num?)?.toInt();
    final rawTitle   = (e['title'] as String?) ?? 'Okänd';
    final title      = year != null ? '$rawTitle ($year)' : rawTitle;
    final type       = (e['type']  as String?) ?? '';
    final user       = (e['username'] as String?) ?? '—';
    final posterPath = (e['poster_path'] as String?) ?? '';
    final mediaId    = e['media_item_id']?.toString();
    final sn  = e['season_number'];
    final ep  = e['episode_number'];
    final sub = sn != null ? 'S${sn.toString().padLeft(2,'0')}E${ep.toString().padLeft(2,'0')}' : type;
    final durSec = (e['total_duration_seconds'] as num?)?.toInt() ?? 0;
    final updAt = (e['updated_at'] as String?) ?? '';
    final dateStr = updAt.length >= 10 ? updAt.substring(0, 10) : updAt;
    final canNav = mediaId != null && widget.onNavigateToMedia != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        // Cover — klickbar
        MouseRegion(
          cursor: canNav ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            onTap: canNav ? () => widget.onNavigateToMedia!(mediaId!, _statsTabIndex) : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: posterPath.isNotEmpty
                  ? Image.network(posterPath, width: 36, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _posterPlaceholder())
                  : _posterPlaceholder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
            if (sub.isNotEmpty)
              Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            Row(children: [
              Icon(Icons.person_outline, size: 11, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(width: 4),
              Text(user, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(dateStr, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          if (durSec > 0)
            Text(_formatMinutes(durSec ~/ 60),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _posterPlaceholder() {
    return Container(
      width: 36, height: 52,
      color: Colors.white.withValues(alpha: 0.04),
      child: const Icon(Icons.movie_outlined, color: Colors.white12, size: 18),
    );
  }

  Widget _topMediaRow(int rank, Map<String, dynamic> m, String mediaType) {
    final year       = (m['year'] as num?)?.toInt();
    final rawTitle   = (m['title']       as String?) ?? 'Okänd';
    final title      = year != null ? '$rawTitle ($year)' : rawTitle;
    final posterPath = (m['poster_path'] as String?) ?? '';
    final mediaId    = m['id']?.toString() ?? '';
    final count      = (m['playCount']   as num?)?.toInt() ?? 0;
    final secs       = (m['totalSeconds'] as num?)?.toInt() ?? 0;
    final rankColor  = rank == 1 ? Colors.amber : rank == 2 ? Colors.white54 : rank == 3 ? const Color(0xFFCD7F32) : Colors.white24;
    final canNav     = mediaId.isNotEmpty && widget.onNavigateToMedia != null;
    final isExpanded = _expandedTopItems[mediaId] == true;
    final plays      = _topItemPlays[mediaId];
    final playsLoading = _topItemPlaysLoading[mediaId] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: isExpanded ? 0 : 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: isExpanded
                ? const BorderRadius.vertical(top: Radius.circular(8))
                : BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: Row(children: [
            SizedBox(width: 24,
                child: Text('#$rank', style: TextStyle(color: rankColor, fontSize: 13, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            // poster + tittel — klickbar för navigering
            MouseRegion(
              cursor: canNav ? SystemMouseCursors.click : MouseCursor.defer,
              child: GestureDetector(
                onTap: canNav ? () => widget.onNavigateToMedia!(mediaId, _statsTabIndex) : null,
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: posterPath.isNotEmpty
                        ? Image.network(posterPath, width: 30, height: 44, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _posterPlaceholder())
                        : Container(width: 30, height: 44, color: Colors.white.withValues(alpha: 0.04),
                              child: const Icon(Icons.movie_outlined, color: Colors.white12, size: 14)),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MouseRegion(
                cursor: canNav ? SystemMouseCursors.click : MouseCursor.defer,
                child: GestureDetector(
                  onTap: canNav ? () => widget.onNavigateToMedia!(mediaId, _statsTabIndex) : null,
                  child: Text(title,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
            // spelningsräknare — klickbar för att expandera
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _toggleTopItem(mediaId),
                child: Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$count spelningar',
                          style: TextStyle(
                            color: isExpanded ? const Color(0xFFB593FF) : Colors.white70,
                            fontSize: 12, fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                            decorationColor: isExpanded
                                ? const Color(0xFFB593FF)
                                : Colors.white54,
                          )),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: Icon(Icons.keyboard_arrow_down,
                            size: 15,
                            color: isExpanded ? const Color(0xFFB593FF) : Colors.white38),
                      ),
                    ]),
                    if (secs > 0)
                      Text(_formatMinutes(secs ~/ 60),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
        // ── expanderat spelpanel ──────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: isExpanded
              ? _buildPlaysExpandedSection(mediaId, mediaType, plays, playsLoading)
              : const SizedBox.shrink(),
        ),
        if (!isExpanded) const SizedBox.shrink()
        else const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildPlaysExpandedSection(
    String mediaId,
    String mediaType,
    List<dynamic>? plays,
    bool loading,
  ) {
    Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF)))),
        ),
      );
    } else if (plays == null || plays.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text('Ingen spelningshistorik', style: TextStyle(color: Colors.white24, fontSize: 12)),
      );
    } else {
      final isMovie = mediaType == 'Movie';
      body = Column(
        children: plays.map((raw) {
          final p = raw as Map<String, dynamic>;
          final username    = (p['username']  as String?) ?? '—';
          final initials    = username.isNotEmpty ? username[0].toUpperCase() : '?';

          if (isMovie) {
            final isWatched  = (p['is_watched'] as num?)?.toInt() == 1;
            final durSec     = (p['total_duration_seconds'] as num?)?.toInt() ?? 0;
            final posSec     = (p['last_position_seconds']  as num?)?.toInt() ?? 0;
            final pct        = durSec > 0 ? (posSec / durSec * 100).round() : 0;
            final updAt      = (p['updated_at']         as String?) ?? '';
            final startAt    = (p['started_at_approx']  as String?) ?? '';
            final endLabel   = updAt.length  >= 16 ? updAt.substring(0, 16)   : updAt;
            final startLabel = startAt.length >= 16 ? startAt.substring(0, 16) : startAt;

            return _playEntryRow(
              initials: initials,
              username: username,
              line1: startLabel.isNotEmpty ? 'Start: $startLabel' : null,
              line2: 'Slut: $endLabel',
              trailing: isWatched
                  ? Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.check_circle, size: 13, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text('Slutförd', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                    ])
                  : Text('$pct% sedd',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
            );
          } else {
            final epCount   = (p['episode_count']      as num?)?.toInt() ?? 0;
            final compCount = (p['completed_count']    as num?)?.toInt() ?? 0;
            final totSec    = (p['totalSeconds']       as num?)?.toInt() ?? 0;
            final lastAt    = (p['updated_at']         as String?) ?? '';
            final firstAt   = (p['first_watched_approx'] as String?) ?? '';
            final lastLabel  = lastAt.length  >= 10 ? lastAt.substring(0, 10)  : lastAt;
            final firstLabel = firstAt.length >= 10 ? firstAt.substring(0, 10) : firstAt;

            return _playEntryRow(
              initials: initials,
              username: username,
              line1: firstLabel.isNotEmpty ? 'Första: $firstLabel' : null,
              line2: 'Senast: $lastLabel  •  $epCount avsnitt ($compCount klara)',
              trailing: Text(_formatMinutes(totSec ~/ 60),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            );
          }
        }).toList(),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF8A5BFF).withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.12)),
      ),
      child: body,
    );
  }

  Widget _playEntryRow({
    required String initials,
    required String username,
    String? line1,
    required String line2,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
          child: Text(initials,
              style: const TextStyle(color: Color(0xFFB593FF), fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(username, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
            if (line1 != null)
              Text(line1, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
            Text(line2, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10)),
          ]),
        ),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }

  Widget _topUserRow(int rank, Map<String, dynamic> u) {
    final username  = (u['username'] as String?) ?? '—';
    final userId    = u['id']?.toString() ?? '';
    final role      = (u['role']     as String?) ?? 'User';
    final secs      = (u['totalSeconds'] as num?)?.toInt() ?? 0;
    final watched   = (u['watched']  as num?)?.toInt() ?? 0;
    final rankColor = rank == 1 ? Colors.amber : rank == 2 ? Colors.white54 : rank == 3 ? const Color(0xFFCD7F32) : Colors.white24;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _statsTabIndex = 1;
            _statsSelectedUserId = userId.isNotEmpty ? userId : null;
          });
          widget.apiService.lastStatsTabIndex = 1;
          _refreshHistory();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
          ),
          child: Row(children: [
            SizedBox(width: 24,
                child: Text('#$rank', style: TextStyle(color: rankColor, fontSize: 13, fontWeight: FontWeight.bold))),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: role == 'Admin'
                  ? Colors.amber.withValues(alpha: 0.12)
                  : const Color(0xFF8A5BFF).withValues(alpha: 0.12),
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                  color: role == 'Admin' ? Colors.amber : const Color(0xFFB593FF),
                  fontSize: 12, fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(username,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                const Text('Tryck för att visa historik',
                    style: TextStyle(color: Colors.white24, fontSize: 10)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('$watched sedda',
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              Text(_formatMinutes(secs ~/ 60),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            ]),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios, size: 11, color: Colors.white24),
          ]),
        ),
      ),
    );
  }

  Color _gaugeColor(int percent) {
    if (percent >= 85) return Colors.redAccent;
    if (percent >= 65) return Colors.orangeAccent;
    return const Color(0xFF8A5BFF);
  }

  Widget _statGaugeRow({required String label, required int value, required String subtitle, required Color color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('$value%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
      ],
    );
  }

  Widget _miniStat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF8A5BFF), size: 18),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  Widget _recentItem(Map<String, dynamic> e) {
    final title = (e['title'] as String?) ?? 'Okänd';
    final type  = (e['type']  as String?) ?? '';
    final user  = (e['username'] as String?) ?? '—';
    final sn    = e['season_number'];
    final ep    = e['episode_number'];
    final subtitle = sn != null ? 'S${sn.toString().padLeft(2,'0')}E${ep.toString().padLeft(2,'0')}' : type;
    final watched = e['is_watched'] == 1;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(
          watched ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: watched ? Colors.greenAccent.withValues(alpha: 0.7) : Colors.white24,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
          ]),
        ),
        Text(user, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
      ]),
    );
  }

  Widget _userStatRow(Map<String, dynamic> u) {
    final username = (u['username'] as String?) ?? '—';
    final role     = (u['role']     as String?) ?? 'User';
    final watched  = (u['watched']  as int?)    ?? 0;
    final secs     = (u['totalSeconds'] as int?) ?? 0;
    final lastSeen = (u['lastSeen'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: role == 'Admin'
              ? Colors.amber.withValues(alpha: 0.12)
              : const Color(0xFF8A5BFF).withValues(alpha: 0.10),
          child: Text(
            username.isNotEmpty ? username[0].toUpperCase() : '?',
            style: TextStyle(
              color: role == 'Admin' ? Colors.amber : const Color(0xFFB593FF),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(username, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(
            lastSeen != null ? 'Senast: ${lastSeen.substring(0,10)}' : 'Aldrig',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
          ),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$watched sedda', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(_formatMinutes(secs ~/ 60), style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
        ]),
      ]),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h >= 24) return '${h ~/ 24}d ${h % 24}h';
    return '${h}h ${m}m';
  }

  // ─────────────────────────────────────────────
  //  Category: Konto (steg 8)
  // ─────────────────────────────────────────────
  Widget _buildAvatarDisplay({required double radius, required String initials}) {
    if (_avatarImageBytes == null) {
      if (_avatarUrl != null) {
        return ClipOval(
          child: Image.network(
            _avatarUrl!,
            width: radius * 2, height: radius * 2, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => CircleAvatar(
              radius: radius,
              backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
              child: Text(initials, style: TextStyle(color: const Color(0xFFB593FF), fontSize: radius * 0.65, fontWeight: FontWeight.bold)),
            ),
          ),
        );
      }
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
        child: Text(initials,
            style: TextStyle(color: const Color(0xFFB593FF),
                fontSize: radius * 0.65, fontWeight: FontWeight.bold)),
      );
    }
    final size = radius * 2;
    final factor = size / 180.0;
    return ClipOval(
      child: SizedBox(
        width: size, height: size,
        child: OverflowBox(
          maxWidth: double.infinity, maxHeight: double.infinity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translate(_avatarOffset.dx * factor, _avatarOffset.dy * factor)
              ..scale(_avatarScale),
            child: Image.memory(_avatarImageBytes!, width: size, height: size, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _cropAvatar(Uint8List bytes, double scale, Offset offset) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    const size = 180.0;
    final iW = img.width.toDouble();
    final iH = img.height.toDouble();

    // Scale the image to cover the 180×180 canvas (same as BoxFit.cover)
    final coverScale = max(size / iW, size / iH);
    final drawW = iW * coverScale;
    final drawH = iH * coverScale;
    final drawX = (size - drawW) / 2;
    final drawY = (size - drawH) / 2;

    // Compute the visible rectangle in IMAGE pixel coordinates directly.
    // The preview uses: T(90+dx,90+dy) * S(scale) * T(-90,-90) applied to drawn space.
    // The inverse maps output (cx,cy) → drawn (cx-90-dx)/scale+90.
    // Then drawn → image via  (drawn - drawOrigin) / coverScale.
    final drawnLeft   = (0.0  - size/2 - offset.dx) / scale + size/2;
    final drawnTop    = (0.0  - size/2 - offset.dy) / scale + size/2;
    final drawnRight  = (size - size/2 - offset.dx) / scale + size/2;
    final drawnBottom = (size - size/2 - offset.dy) / scale + size/2;

    final srcLeft   = (drawnLeft   - drawX) / coverScale;
    final srcTop    = (drawnTop    - drawY) / coverScale;
    final srcRight  = (drawnRight  - drawX) / coverScale;
    final srcBottom = (drawnBottom - drawY) / coverScale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.clipRect(const Rect.fromLTWH(0, 0, size, size));

    canvas.drawImageRect(
      img,
      Rect.fromLTRB(srcLeft, srcTop, srcRight, srcBottom),
      const Rect.fromLTWH(0, 0, size, size),
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final result = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await result.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final bytes = result.files.single.bytes!;

    double scale = 1.0;
    Offset offset = Offset.zero;
    Offset? panStart;
    Offset offsetAtPanStart = Offset.zero;
    final valueNotifier = ValueNotifier<int>(0);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF15102A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          title: const Text('Välj profilbild', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Zooma och flytta bilden för att välja utsnitt.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
              const SizedBox(height: 20),
              // Preview med ring
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Cirkulär klipp
                    ClipOval(
                      child: SizedBox(
                        width: 180, height: 180,
                        child: GestureDetector(
                          onScaleStart: (d) {
                            panStart = d.focalPoint;
                            offsetAtPanStart = offset;
                          },
                          onScaleUpdate: (d) {
                            setDs(() {
                              scale = (scale * d.scale).clamp(0.5, 4.0);
                              if (panStart != null) {
                                offset = offsetAtPanStart + (d.focalPoint - panStart!);
                              }
                            });
                          },
                          child: ValueListenableBuilder<int>(
                            valueListenable: valueNotifier,
                            builder: (_, __, ___) => Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..translate(offset.dx, offset.dy)
                                ..scale(scale),
                              child: Image.memory(bytes, fit: BoxFit.cover,
                                  width: 180, height: 180),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Ring overlay
                    IgnorePointer(
                      child: Container(
                        width: 184, height: 184,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF8A5BFF), width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Zoom-slider
              Row(children: [
                const Icon(Icons.zoom_out, color: Colors.white38, size: 18),
                Expanded(
                  child: StatefulBuilder(
                    builder: (_, ss) => SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: const Color(0xFF8A5BFF),
                        inactiveTrackColor: Colors.white12,
                        thumbColor: const Color(0xFFB593FF),
                        overlayColor: const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: scale,
                        min: 0.5, max: 4.0,
                        onChanged: (v) { setDs(() => scale = v); },
                      ),
                    ),
                  ),
                ),
                const Icon(Icons.zoom_in, color: Colors.white38, size: 18),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Avbryt', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Välj bild'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    // Rendera det valda utsnittet till en 180×180 bild
    final croppedBytes = await _cropAvatar(bytes, scale, offset);
    // Spara croppade bytes i state — ingen transform behövs längre
    setState(() {
      _avatarImageBytes = croppedBytes;
      _avatarScale = 1.0;
      _avatarOffset = Offset.zero;
    });
    // Upload till backend
    try {
      // Evict stale cached avatar before uploading so all Image.network widgets
      // refetch the new image instead of serving the old cached version.
      if (_avatarUrl != null) {
        PaintingBinding.instance.imageCache.evict(NetworkImage(_avatarUrl!));
      }
      await widget.apiService.uploadAvatar(croppedBytes);
      if (!mounted) return;
      final payload = widget.apiService.currentUserPayload;
      if (payload != null) {
        // Append timestamp to bust any remaining cache in widgets still holding the old URL.
        final ts = DateTime.now().millisecondsSinceEpoch;
        setState(() => _avatarUrl = '${widget.apiService.baseUrl}/api/avatars/${payload['id']}.jpg?t=$ts');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profilbild uppdaterad ✅'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kunde inte ladda upp bild: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Widget _buildKonto() {
    final payload = widget.apiService.currentUserPayload;
    final username = payload?['username'] as String? ?? '—';
    final role = payload?['role'] as String? ?? '—';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Inloggad som ──────────────────────
          _buildSection('Inloggad som', Icons.person_outline, [
            Row(children: [
              // Avatar med klick för uppladdning
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    _buildAvatarDisplay(radius: 34, initials: username.isNotEmpty ? username[0].toUpperCase() : '?'),
                    Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF8A5BFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(username, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: role == 'Admin'
                        ? Colors.amber.withValues(alpha: 0.12)
                        : const Color(0xFF8A5BFF).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: role == 'Admin'
                          ? Colors.amber.withValues(alpha: 0.4)
                          : const Color(0xFF8A5BFF).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(role,
                      style: TextStyle(
                        color: role == 'Admin' ? Colors.amber : const Color(0xFFB593FF),
                        fontSize: 11, fontWeight: FontWeight.bold,
                      )),
                ),
                const SizedBox(height: 4),
                Text('Klicka på bilden för att byta profilbild',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
              ]),
            ]),
          ]),
          const SizedBox(height: 16),

          // ── Profilinformation (auto-save) ─────
          _buildSection('Profilinformation', Icons.edit_outlined, [
            Row(children: [
              const Spacer(),
              if (_profileSaveStatus == 'saving')
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFFB593FF))))
              else if (_profileSaveStatus == 'saved')
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                  SizedBox(width: 4),
                  Text('Sparat', style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                ]),
            ]),
            const SizedBox(height: 4),
            _buildField('Fullständigt namn', _fullNameCtrl,
                hint: 'Ditt riktiga namn (valfritt)',
                onSave: _scheduleProfileSave),
            const SizedBox(height: 12),
            _buildField('Användarnamn', _newUsernameEditCtrl,
                hint: 'Ditt användarnamn',
                onSave: _scheduleProfileSave),
          ]),
          const SizedBox(height: 16),

          // ── PIN-kod (auto-save vid korrekt indata) ─
          _buildSection('PIN-kod', Icons.pin_outlined, [
            Text('PIN-koden visas vid profilval i startskärmen.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, height: 1.5)),
            const SizedBox(height: 12),
            _buildField('PIN-kod (4–8 siffror)', _pinCtrl,
                hint: 'Ange ny PIN — sparas automatiskt när den är giltig',
                onSave: _schedulePin),
            const SizedBox(height: 10),
            ExcludeFocusTraversal(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _removePin,
                  icon: const Icon(Icons.no_encryption_outlined, size: 14, color: Colors.redAccent),
                  label: const Text('Ta bort PIN', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Byt lösenord (behöver bekräftelse → behåller knapp) ──
          _buildSection('Byt lösenord', Icons.lock_outline, [
            _buildField('Nuvarande lösenord', _currentPassCtrl, obscure: true, noAutoSave: true),
            const SizedBox(height: 12),
            _buildField('Nytt lösenord', _newPassCtrl, obscure: true, noAutoSave: true),
            const SizedBox(height: 12),
            _buildField('Bekräfta nytt lösenord', _confirmPassCtrl, obscure: true, noAutoSave: true),
            const SizedBox(height: 16),
            ExcludeFocusTraversal(
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A5BFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isChangingPassword ? null : _changeOwnPassword,
                  icon: _isChangingPassword
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                      : const Icon(Icons.lock_reset),
                  label: Text(_isChangingPassword ? 'Sparar...' : 'Byt lösenord',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final fullName = _fullNameCtrl.text.trim();
    final newUsername = _newUsernameEditCtrl.text.trim();
    if (fullName.isEmpty && newUsername.isEmpty) return;
    setState(() => _isSavingProfile = true);
    try {
      await widget.apiService.updateOwnProfile(
        fullName: fullName.isNotEmpty ? fullName : null,
        newUsername: newUsername.isNotEmpty ? newUsername : null,
      );
      if (!mounted) return;
      _fullNameCtrl.clear();
      _newUsernameEditCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil uppdaterad ✅'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _savePin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ange en PIN-kod'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (pin.length < 4 || pin.length > 8 || !RegExp(r'^\d+$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN måste vara 4–8 siffror'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _isSavingProfile = true);
    try {
      await widget.apiService.updateOwnProfile(pin: pin);
      if (!mounted) return;
      _pinCtrl.clear();
      setState(() => _hasPinSet = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN-kod satt ✅'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _removePin() async {
    setState(() => _isSavingProfile = true);
    try {
      await widget.apiService.updateOwnProfile(pin: '');
      if (!mounted) return;
      setState(() => _hasPinSet = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN-kod borttagen'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _changeOwnPassword() async {
    final current = _currentPassCtrl.text.trim();
    final newPw = _newPassCtrl.text.trim();
    final confirm = _confirmPassCtrl.text.trim();

    if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll i alla fält'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (newPw != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lösenorden matchar inte'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isChangingPassword = true);
    try {
      await widget.apiService.updateOwnPassword(current, newPw);
      if (!mounted) return;
      _currentPassCtrl.clear();
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lösenord bytt! ✅'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  // ─────────────────────────────────────────────
  //  Category: Användare (steg 7)
  // ─────────────────────────────────────────────
  Future<void> _loadUsers() async {
    if (_isLoadingUsers) return;
    setState(() => _isLoadingUsers = true);
    try {
      final list = await widget.apiService.fetchUsers();
      if (mounted) {
        setState(() => _users = list.cast<Map<String, dynamic>>());
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  Future<void> _createUser() async {
    final un = _newUsernameCtrl.text.trim();
    final pw = _newPasswordCtrl.text.trim();
    if (un.isEmpty || pw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fyll i användarnamn och lösenord'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _isCreatingUser = true);
    try {
      await widget.apiService.createUser(un, pw, _newUserRole);
      if (!mounted) return;
      _newUsernameCtrl.clear();
      _newPasswordCtrl.clear();
      setState(() => _newUserRole = 'User');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Användare "$un" skapad!'), backgroundColor: const Color(0xFF8A5BFF)),
      );
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isCreatingUser = false);
    }
  }

  Future<void> _showResetPasswordDialog(Map<String, dynamic> user) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: Text('Återställ lösenord — ${user['username']}',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: ctrl,
            obscureText: true,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            contextMenuBuilder: (ctx, state) =>
                AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
            decoration: _inputDeco('Nytt lösenord...'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8A5BFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final pw = ctrl.text.trim();
              if (pw.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await widget.apiService.updateUser(user['id'] as String, password: pw);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lösenord återställt för ${user['username']}'), backgroundColor: const Color(0xFF8A5BFF)),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Spara'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final uid = user['id'] as String;
    final fullNameCtrl = TextEditingController(text: user['full_name'] as String? ?? '');
    final usernameCtrl = TextEditingController(text: user['username'] as String? ?? '');
    final pinCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    // Prefill PIN field with stored plaintext so admin can see/edit it
    final existingPin = user['pin_plain'] as String? ?? '';
    pinCtrl.text = existingPin;
    bool savingEdit = false;
    bool showPin = false;
    bool showPass = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF15102A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          title: Row(children: [
            _buildUserAvatar(user, user['role'] as String? ?? 'User', user['username'] as String? ?? '?', radius: 16),
            const SizedBox(width: 10),
            Text('Redigera — ${user['username']}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
          ]),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: usernameCtrl,
                style: const TextStyle(color: Colors.white),
                contextMenuBuilder: (ctx, state) =>
                    AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                decoration: _inputDeco('Användarnamn'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fullNameCtrl,
                style: const TextStyle(color: Colors.white),
                contextMenuBuilder: (ctx, state) =>
                    AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                decoration: _inputDeco('Fullständigt namn (valfritt)'),
              ),
              const SizedBox(height: 14),
              // PIN — visa nuvarande + kan redigera
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PIN-kod (4–8 siffror)',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                const SizedBox(height: 6),
                TextField(
                  controller: pinCtrl,
                  keyboardType: TextInputType.number,
                  obscureText: !showPin,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                  style: const TextStyle(color: Colors.white, letterSpacing: 3),
                  contextMenuBuilder: (ctx, state) =>
                      AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                  decoration: _inputDeco('Lämna tomt för att ta bort PIN').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.white38, size: 18),
                      onPressed: () => setDs(() => showPin = !showPin),
                    ),
                    prefixIcon: const Icon(Icons.pin_outlined, color: Colors.white30, size: 16),
                    hintText: existingPin.isNotEmpty ? 'Nuvarande: ${existingPin.length} siffror' : 'Ingen PIN satt',
                  ),
                ),
                if (existingPin.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text('Nuvarande PIN är förifylld',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
                  ),
              ]),
              const SizedBox(height: 14),
              // Nytt lösenord (admin kan byta)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nytt lösenord (lämna tomt = ingen ändring)',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
                const SizedBox(height: 6),
                TextField(
                  controller: passwordCtrl,
                  obscureText: !showPass,
                  style: const TextStyle(color: Colors.white),
                  contextMenuBuilder: (ctx, state) =>
                      AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
                  decoration: _inputDeco('').copyWith(
                    hintText: 'Nytt lösenord...',
                    suffixIcon: IconButton(
                      icon: Icon(showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.white38, size: 18),
                      onPressed: () => setDs(() => showPass = !showPass),
                    ),
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.white30, size: 16),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
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
              onPressed: savingEdit ? null : () async {
                setDs(() => savingEdit = true);
                final newUsername = usernameCtrl.text.trim();
                final fullName = fullNameCtrl.text.trim();
                final pin = pinCtrl.text.trim();
                final password = passwordCtrl.text;
                try {
                  await widget.apiService.updateUser(uid,
                    username: newUsername.isNotEmpty ? newUsername : null,
                    fullName: fullName,
                    // empty pin field = remove PIN, changed pin = update, same as existing = no change
                    pin: pin != existingPin ? pin : null,
                    password: password.isNotEmpty ? password : null,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadUsers();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Användare uppdaterad ✅'), backgroundColor: Color(0xFF8A5BFF)),
                  );
                } catch (e) {
                  setDs(() => savingEdit = false);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              },
              child: savingEdit
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                  : const Text('Spara'),
            ),
          ],
        ),
      ),
    );
    fullNameCtrl.dispose();
    usernameCtrl.dispose();
    pinCtrl.dispose();
    passwordCtrl.dispose();
  }

  // Determinstic avatar color (same palette as user_picker_overlay)
  static Color _userAvatarColor(String username) {
    const palette = [
      Color(0xFF8A5BFF), Color(0xFF5B8AFF), Color(0xFF5BFFB5),
      Color(0xFFFF5B8A), Color(0xFFFFB55B), Color(0xFF5BD4FF),
      Color(0xFFD45BFF), Color(0xFF5BFF5B),
    ];
    int hash = 0;
    for (final c in username.codeUnits) hash = (hash * 31 + c) & 0x7FFFFFFF;
    return palette[hash % palette.length];
  }

  static String _userInitials(String username) {
    final parts = username.trim().split(RegExp(r'[\s_.-]+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return username.substring(0, username.length.clamp(0, 2)).toUpperCase();
  }

  Widget _buildUserAvatar(Map<String, dynamic> user, String role, String username, {double radius = 20}) {
    final color = _userAvatarColor(username);
    final avatarPath = user['avatar_path'] as String?;
    final avatarUrl = (avatarPath != null && avatarPath.isNotEmpty)
        ? '${widget.apiService.baseUrl}$avatarPath?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}'
        : null;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.2),
      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
      child: avatarUrl == null
          ? Text(
              _userInitials(username),
              style: TextStyle(color: color, fontSize: radius * 0.6, fontWeight: FontWeight.bold),
            )
          : null,
    );
  }

  Widget _buildAnvandare() {
    final callerPayload = widget.apiService.currentUserPayload;
    final isAdmin = callerPayload?['role'] == 'Admin';

    if (!isAdmin) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 48, color: Colors.white12),
            const SizedBox(height: 16),
            const Text('Kräver Admin-rättigheter',
                style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Kontakta en administratör för att hantera användare.',
                style: TextStyle(color: Colors.white24, fontSize: 13)),
          ],
        ),
      );
    }

    if (_users.isEmpty && !_isLoadingUsers) {
      Future.microtask(_loadUsers);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // ── Befintliga användare ──────────────
          _buildSection('Användare', Icons.group_outlined, [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_users.length} användare',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                IconButton(
                  onPressed: _isLoadingUsers ? null : _loadUsers,
                  icon: _isLoadingUsers
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))))
                      : const Icon(Icons.refresh, color: Colors.white38, size: 18),
                  tooltip: 'Uppdatera',
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_users.isEmpty && !_isLoadingUsers)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                alignment: Alignment.center,
                child: const Text('Inga användare hittades', style: TextStyle(color: Colors.white24)),
              )
            else
              ..._users.map((u) => _buildUserListItem(u, callerPayload?['id'] as String?)),
          ]),
          const SizedBox(height: 16),
          // ── Skapa ny användare ────────────────
          _buildSection('Lägg till användare', Icons.person_add_outlined, [
            _buildField('Användarnamn', _newUsernameCtrl),
            const SizedBox(height: 12),
            _buildField('Lösenord', _newPasswordCtrl, obscure: true),
            const SizedBox(height: 12),
            _buildDropdown('Roll', _newUserRole, ['User', 'Admin'],
                (v) => setState(() => _newUserRole = v ?? 'User')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8A5BFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isCreatingUser ? null : _createUser,
                icon: _isCreatingUser
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : const Icon(Icons.add),
                label: Text(_isCreatingUser ? 'Skapar...' : 'Skapa användare',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildUserListItem(Map<String, dynamic> user, String? callerId) {
    final uid    = user['id'] as String;
    final username = user['username'] as String;
    final role   = user['role'] as String;
    final isSelf = uid == callerId;
    final hasPin = (user['has_pin'] as int? ?? 0) == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          _buildUserAvatar(user, role, username, radius: 18),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(username,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                if (isSelf) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Du', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: role == 'Admin'
                      ? Colors.amber.withValues(alpha: 0.1)
                      : const Color(0xFF8A5BFF).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: role == 'Admin'
                        ? Colors.amber.withValues(alpha: 0.3)
                        : const Color(0xFF8A5BFF).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(role,
                    style: TextStyle(
                      color: role == 'Admin' ? Colors.amber : const Color(0xFFB593FF),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    )),
              ),
              if (hasPin) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.3)),
                  ),
                  child: const Text('PIN ✓', style: TextStyle(color: Color(0xFFB593FF), fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
          ),
          // Toggle roll
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white38, size: 20),
            color: const Color(0xFF15102A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 16, color: Colors.white54),
                  SizedBox(width: 8),
                  Text('Redigera (namn, PIN)', style: TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              PopupMenuItem(
                value: 'role',
                child: Row(children: [
                  Icon(role == 'Admin' ? Icons.person_outline : Icons.admin_panel_settings_outlined,
                      size: 16, color: Colors.white54),
                  const SizedBox(width: 8),
                  Text(role == 'Admin' ? 'Ändra till User' : 'Ändra till Admin',
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Row(children: [
                  Icon(Icons.lock_reset, size: 16, color: Colors.white54),
                  SizedBox(width: 8),
                  Text('Återställ lösenord', style: TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
              if (hasPin)
                const PopupMenuItem(
                  value: 'remove_pin',
                  child: Row(children: [
                    Icon(Icons.pin_outlined, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Ta bort PIN', style: TextStyle(color: Colors.orange, fontSize: 13)),
                  ]),
                ),
              if (!isSelf)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Ta bort', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ]),
                ),
            ],
            onSelected: (action) async {
              if (action == 'edit') {
                await _showEditUserDialog(user);
              } else if (action == 'role') {
                final newRole = role == 'Admin' ? 'User' : 'Admin';
                try {
                  await widget.apiService.updateUser(uid, role: newRole);
                  _loadUsers();
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              } else if (action == 'reset') {
                await _showResetPasswordDialog(user);
              } else if (action == 'remove_pin') {
                try {
                  await widget.apiService.updateUser(uid, pin: '');
                  _loadUsers();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('PIN borttagen för $username'), backgroundColor: const Color(0xFF8A5BFF)),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              } else if (action == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF15102A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    title: const Text('Ta bort användare', style: TextStyle(color: Colors.white)),
                    content: Text('Är du säker på att du vill ta bort "$username"?',
                        style: const TextStyle(color: Colors.white70)),
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
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Ta bort'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await widget.apiService.deleteUser(uid);
                    _loadUsers();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fel: $e'), backgroundColor: Colors.redAccent),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Stub for coming-soon categories
  // ─────────────────────────────────────────────
  Widget _buildStub(String title, IconData icon, String description) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.white12),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            width: 360,
            child: Text(description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Helper widgets
  // ─────────────────────────────────────────────
  Widget _buildAutoSaveIndicator() {
    if (_autoSaveStatus == 'saving') {
      return Row(mainAxisSize: MainAxisSize.min, children: const [
        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white38))),
        SizedBox(width: 6),
        Text('Sparar...', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]);
    }
    if (_autoSaveStatus == 'saved') {
      return const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF00E676)),
        SizedBox(width: 6),
        Text('Sparat', style: TextStyle(color: Color(0xFF00E676), fontSize: 12)),
      ]);
    }
    return const SizedBox.shrink();
  }

  // ─────────────────────────────────────────────
  //  Category: Diskutrymme
  // ─────────────────────────────────────────────

  Future<void> _loadDiskStats() async {
    setState(() { _isDiskStatsLoading = true; _diskStats = null; });
    try {
      final data = await widget.apiService.diskStats();
      if (mounted) setState(() { _diskStats = data; _isDiskStatsLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isDiskStatsLoading = false);
    }
  }

  Future<void> _runDiskScan() async {
    setState(() { _isDiskScanning = true; _diskScanError = null; _diskCleanResult = null; _diskCandidates = []; });
    try {
      final data = await widget.apiService.diskScan();
      if (!mounted) return;
      final raw = (data['candidates'] as List<dynamic>? ?? [])
          .map((c) => Map<String, dynamic>.from(c as Map)..['_selected'] = true)
          .toList();
      setState(() {
        _diskCandidates = raw;
        _diskTotalCandidates = data['total_candidates'] as int? ?? 0;
        _diskTotalFreeableGb = (data['total_freeable_gb'] as num?)?.toDouble() ?? 0;
        _isDiskScanning = false;
      });
    } catch (e) {
      if (mounted) setState(() { _isDiskScanning = false; _diskScanError = e.toString(); });
    }
  }

  Future<void> _runDiskCleanup() async {
    final selected = _diskCandidates.where((c) => c['_selected'] == true).toList();
    if (selected.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        title: const Text('Bekräfta rensning', style: TextStyle(color: Colors.white)),
        content: Text(
          'Flytta ${selected.length} objekt till papperskorgen?\nDe märks som AUTO-RADERAT och kan återställas.',
          style: const TextStyle(color: Colors.white70),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Radera markerade'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() { _isDiskCleaning = true; _diskCleanResult = null; });
    try {
      final ids = selected.map((c) => c['id'] as String).toList();
      final result = await widget.apiService.diskCleanup(ids: ids);
      if (!mounted) return;
      final count = result['deleted_count'] as int? ?? 0;
      setState(() {
        _isDiskCleaning = false;
        _diskCleanResult = '$count objekt flyttades till papperskorgen.';
        _diskCandidates = [];
        _diskTotalCandidates = 0;
        _diskTotalFreeableGb = 0;
      });
      widget.onLibraryChanged?.call();
    } catch (e) {
      if (mounted) setState(() { _isDiskCleaning = false; _diskScanError = e.toString(); });
    }
  }

  Widget _diskStatPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskRuleCard({
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    Widget? configChild,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? color.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enabled ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            secondary: Icon(icon, color: enabled ? color : Colors.white24, size: 20),
            title: Text(title, style: TextStyle(color: enabled ? Colors.white : Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11)),
            value: enabled,
            activeThumbColor: color,
            activeTrackColor: color.withValues(alpha: 0.25),
            onChanged: onToggle,
          ),
          if (enabled && configChild != null) ...[
            Divider(color: color.withValues(alpha: 0.12), height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: configChild,
            ),
          ],
        ],
      ),
    );
  }

  Widget _diskNumberField(String label, TextEditingController ctrl, {String hint = ''}) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            onChanged: (_) => _scheduleSave(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
            decoration: _inputDeco(hint),
          ),
        ),
      ],
    );
  }

  Widget _buildDiskCandidateRow(Map<String, dynamic> c) {
    final selected = c['_selected'] == true;
    final itemType = c['item_type'] as String? ?? 'movie';
    final sizeMb = (c['file_size_mb'] as num?)?.toInt() ?? 0;
    final sizeLabel = sizeMb >= 1024 ? '${(sizeMb / 1024).toStringAsFixed(1)} GB' : '$sizeMb MB';

    Color typeColor;
    String typeLabel;
    switch (itemType) {
      case 'episode': typeColor = Colors.blue; typeLabel = 'AVSNITT'; break;
      case 'season':  typeColor = Colors.orange; typeLabel = 'SÄSONG'; break;
      case 'show':    typeColor = Colors.purple; typeLabel = 'SERIE'; break;
      default:        typeColor = const Color(0xFF8A5BFF); typeLabel = 'FILM';
    }

    final title = itemType == 'episode'
        ? '${c['show_title']} · S${(c['season_number'] as int? ?? 0).toString().padLeft(2,'0')}E${(c['episode_number'] as int? ?? 0).toString().padLeft(2,'0')}'
        : itemType == 'season'
        ? '${c['show_title']} · Säsong ${c['season_number']}'
        : c['title'] as String? ?? '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.02)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            activeColor: const Color(0xFF8A5BFF),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            onChanged: (v) => setState(() => c['_selected'] = v ?? false),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
            child: Text(typeLabel, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(sizeLabel, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(c['reason_details'] as String? ?? '', style: const TextStyle(color: Colors.white24, fontSize: 11), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildDiskutrymme() {
    final selectedCount = _diskCandidates.where((c) => c['_selected'] == true).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Diskstatistik ─────────────────────────────
          _buildSection('Diskstatistik', Icons.storage_outlined, [
            if (_diskStats != null) ...[
              Row(children: [
                _diskStatPill('Totalt', '${_diskStats!['total_gb']} GB', Colors.white54),
                const SizedBox(width: 8),
                _diskStatPill('Filmer', '${_diskStats!['movies_gb']} GB', const Color(0xFF8A5BFF)),
                const SizedBox(width: 8),
                _diskStatPill('Serier', '${_diskStats!['shows_gb']} GB', Colors.orange),
              ]),
              const SizedBox(height: 8),
              Text(
                '${_diskStats!['movie_count']} filmer · ${_diskStats!['episode_count']} avsnitt',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 10),
            ],
            if (_isDiskStatsLoading)
              const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            ElevatedButton.icon(
              onPressed: _isDiskStatsLoading ? null : _loadDiskStats,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(_diskStats == null ? 'Hämta statistik' : 'Uppdatera'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                foregroundColor: Colors.white70,
                elevation: 0,
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Regler ────────────────────────────────────
          _buildSection('Regler', Icons.rule_outlined, [
            Text(
              'Välj vilka regler som ska avgöra om en fil ska flyttas till papperskorgen. Reglerna kombineras med ELLER — en fil som träffar minst en aktiverad regel är kandidat. Allt är avstängt som standard.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
            ),
            const SizedBox(height: 14),

            _buildDiskRuleCard(
              enabled: _diskRuleWatchedEnabled,
              onToggle: (v) { setState(() => _diskRuleWatchedEnabled = v); _scheduleSave(); },
              title: 'Sedd',
              subtitle: 'Radera om sedd för mer än X dagar sedan.',
              icon: Icons.check_circle_outline,
              color: Colors.green,
              configChild: _diskNumberField('Dagar efter sedd', _diskWatchedDaysCtrl, hint: 'dagar'),
            ),
            const SizedBox(height: 10),

            _buildDiskRuleCard(
              enabled: _diskRuleUnseenEnabled,
              onToggle: (v) { setState(() => _diskRuleUnseenEnabled = v); _scheduleSave(); },
              title: 'Osedd',
              subtitle: 'Radera om aldrig sedd och tillagd för mer än X dagar sedan.',
              icon: Icons.visibility_off_outlined,
              color: Colors.orange,
              configChild: _diskNumberField('Dagar sedan tillagd', _diskUnseenDaysCtrl, hint: 'dagar'),
            ),
            const SizedBox(height: 10),

            _buildDiskRuleCard(
              enabled: _diskRuleInactiveEnabled,
              onToggle: (v) { setState(() => _diskRuleInactiveEnabled = v); _scheduleSave(); },
              title: 'Inaktiv',
              subtitle: 'Radera om inte spelad på X dagar (räknat från senaste aktivitet).',
              icon: Icons.timer_off_outlined,
              color: Colors.blue,
              configChild: _diskNumberField('Dagar utan aktivitet', _diskInactiveDaysCtrl, hint: 'dagar'),
            ),
            const SizedBox(height: 10),

            _buildDiskRuleCard(
              enabled: _diskRuleSizeEnabled,
              onToggle: (v) { setState(() => _diskRuleSizeEnabled = v); _scheduleSave(); },
              title: 'Filstorlek',
              subtitle: 'Radera filer som är större än X GB.',
              icon: Icons.folder_outlined,
              color: Colors.redAccent,
              configChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _diskNumberField('Storlek (GB)', _diskSizeGbCtrl, hint: 'GB'),
                  const SizedBox(height: 10),
                  _switchTile(
                    'Kräv att sedd',
                    'Radera bara stora filer som redan har setts.',
                    _diskRuleSizeRequireWatched,
                    (v) { setState(() => _diskRuleSizeRequireWatched = v); _scheduleSave(); },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            _buildDiskRuleCard(
              enabled: _diskRuleRatingEnabled,
              onToggle: (v) { setState(() => _diskRuleRatingEnabled = v); _scheduleSave(); },
              title: 'Lågt betyg',
              subtitle: 'Radera om eget betyg är lika med eller lägre än X (skala 0–10).',
              icon: Icons.star_border_outlined,
              color: Colors.amber,
              configChild: _diskNumberField('Max betyg', _diskRatingMaxCtrl, hint: '0–10'),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Seriehantering ────────────────────────────
          _buildSection('Seriehantering', Icons.tv_outlined, [
            Text('Hur ska TV-serier hanteras vid radering?', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
            const SizedBox(height: 12),
            _buildDropdown(
              'Raderingsenhet',
              _diskSeriesMode,
              ['episode', 'season', 'show'],
              (v) { if (v != null) { setState(() => _diskSeriesMode = v); _scheduleSave(); } },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Text(
                _diskSeriesMode == 'season'
                    ? 'Hela säsongen raderas när ALLA avsnitt i säsongen är sedda.'
                    : _diskSeriesMode == 'show'
                    ? 'Hela serien raderas när ALLA avsnitt i alla säsonger är sedda.'
                    : 'Varje avsnitt utvärderas individuellt — serier raderas aldrig i ett svep.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Skydd ─────────────────────────────────────
          _buildSection('Skydd', Icons.shield_outlined, [
            _switchTile(
              'Skydda favoriter',
              'Titlar markerade som favorit raderas aldrig automatiskt.',
              _diskProtectFavorites,
              (v) { setState(() => _diskProtectFavorites = v); _scheduleSave(); },
            ),
          ]),

          const SizedBox(height: 16),

          // ── Dry-run & Rensning ─────────────────────────
          _buildSection('Dry-run & Rensning', Icons.cleaning_services_outlined, [
            Text(
              'Kör en genomsökning utan att radera något (dry-run), granska listan och radera sedan det du vill.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isDiskScanning ? null : _runDiskScan,
                  icon: _isDiskScanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search, size: 16),
                  label: Text(_isDiskScanning ? 'Skannar...' : 'Kör dry-run'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_isDiskCleaning || selectedCount == 0) ? null : _runDiskCleanup,
                  icon: _isDiskCleaning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: Text(_isDiskCleaning ? 'Rensar...' : 'Radera markerade ($selectedCount)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.14),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ]),

            if (_diskScanError != null) ...[
              const SizedBox(height: 10),
              Text(_diskScanError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],

            if (_diskCleanResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.15)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Text(_diskCleanResult!, style: const TextStyle(color: Colors.green, fontSize: 13)),
                ]),
              ),
            ],

            if (_diskCandidates.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_diskTotalCandidates kandidater · ${_diskTotalFreeableGb.toStringAsFixed(2)} GB kan frigöras',
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: () {
                      final allSelected = _diskCandidates.every((c) => c['_selected'] == true);
                      setState(() {
                        for (final c in _diskCandidates) { c['_selected'] = !allSelected; }
                      });
                    },
                    child: Text(
                      _diskCandidates.every((c) => c['_selected'] == true) ? 'Avmarkera alla' : 'Markera alla',
                      style: const TextStyle(color: Color(0xFF8A5BFF), fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ..._diskCandidates.map(_buildDiskCandidateRow),
            ] else if (!_isDiskScanning && _diskTotalCandidates == 0 && _diskCleanResult == null) ...[
              const SizedBox(height: 10),
              Text(
                'Inga kandidater ännu. Aktivera regler och kör dry-run för att se vad som matchar.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
              ),
            ],
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
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
          Row(children: [
            Icon(icon, color: const Color(0xFF8A5BFF), size: 20),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          const Divider(color: Colors.white10, height: 24),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    String? hint,
    VoidCallback? onSave,   // override save callback; defaults to _scheduleSave
    bool noAutoSave = false, // set true for fields that must NOT auto-save (e.g. password confirm)
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          onChanged: noAutoSave ? null : (_) => onSave != null ? onSave() : _scheduleSave(),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          contextMenuBuilder: (ctx, state) =>
              AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
          decoration: _inputDeco(hint ?? ''),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> options, ValueChanged<String?> onChange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: const Color(0xFF15102A),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              isExpanded: true,
              items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: onChange,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOAuthRow({required String label, required bool isConnected, required Color color, required VoidCallback onTap}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(isConnected ? Icons.check_circle : Icons.link, color: isConnected ? Colors.green : color, size: 18),
            const SizedBox(width: 8),
            Text(isConnected ? '$label är kopplad' : 'Koppla till $label',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isConnected ? Colors.white12 : color,
              foregroundColor: isConnected ? Colors.white70 : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              elevation: isConnected ? 0 : 2,
            ),
            onPressed: onTap,
            icon: Icon(isConnected ? Icons.link_off : Icons.login, size: 14),
            label: Text(isConnected ? 'Koppla från' : 'Anslut nu',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _syncOptions(String platform, Color color, bool ratings, bool watched,
      ValueChanged<bool> onRatings, ValueChanged<bool> onWatched) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Synkronisera betyg', style: TextStyle(color: Colors.white, fontSize: 13)),
            value: ratings,
            activeColor: color,
            onChanged: onRatings,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Synkronisera sedda', style: TextStyle(color: Colors.white, fontSize: 13)),
            value: watched,
            activeColor: color,
            onChanged: onWatched,
          ),
        ],
      ),
    );
  }

  Widget _switchTile(String title, String subtitle, bool value, ValueChanged<bool> onChange) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
        value: value,
        activeThumbColor: const Color(0xFF8A5BFF),
        activeTrackColor: const Color(0xFF8A5BFF).withValues(alpha: 0.25),
        onChanged: onChange,
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.3),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white24),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF8A5BFF), width: 1.5)),
  );

  Widget _browseButton({required bool browsing, required VoidCallback onTap}) {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.04),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        onPressed: browsing ? null : onTap,
        icon: browsing
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
            : const Icon(Icons.folder_open_outlined, color: Color(0xFFB593FF)),
        label: const Text('Bläddra...'),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Toast widget (moved from dashboard)
// ─────────────────────────────────────────────
class _ToastWidget extends StatefulWidget {
  final String title;
  final String message;
  final bool isSuccess;
  final VoidCallback onDismiss;

  const _ToastWidget({required this.title, required this.message, required this.isSuccess, required this.onDismiss});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _ac;
  late Animation<double> _fade, _slide;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _ac, curve: Curves.easeOut);
    _slide = Tween<double>(begin: 40, end: 0).animate(CurvedAnimation(parent: _ac, curve: Curves.easeOut));
    _ac.forward();
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) _ac.reverse().then((_) => widget.onDismiss());
    });
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      right: 24,
      child: AnimatedBuilder(
        animation: _ac,
        builder: (_, child) => Opacity(
          opacity: _fade.value,
          child: Transform.translate(offset: Offset(_slide.value, 0), child: child),
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF15102A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isSuccess ? Colors.green.withValues(alpha: 0.3) : Colors.redAccent.withValues(alpha: 0.3),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20)],
            ),
            child: Row(
              children: [
                Icon(widget.isSuccess ? Icons.check_circle : Icons.error_outline,
                    color: widget.isSuccess ? Colors.green : Colors.redAccent, size: 24),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(widget.message, style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
}

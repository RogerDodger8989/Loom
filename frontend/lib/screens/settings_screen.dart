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

part 'settings/bibliotek_tab.dart';
part 'settings/papperskorg_tab.dart';
part 'settings/uppspelning_tab.dart';
part 'settings/kallor_tab.dart';
part 'settings/notifieringar_tab.dart';
part 'settings/loggning_tab.dart';
part 'settings/server_tab.dart';
part 'settings/statistik_tab.dart';
part 'settings/konto_tab.dart';
part 'settings/anvandare_tab.dart';
part 'settings/diskutrymme_tab.dart';


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
  final _fallbackSubLangCtrl = TextEditingController(text: 'en');

  String _versionPriority = '1080p,720p,4K';
  String _metadataLanguage = 'sv-SE';
  String _fallbackLanguage = 'en-US';
  String _defaultAudioLanguage = 'sv';
  String _watchProviderRegion = 'SE';
  String _titleDisplayStyle = 'Translated';
  bool _showReleaseVersion = true;
  bool _preferLocalNfo = true;
  bool _alwaysOnTop = false;
  bool _syncTraktRatings = true;
  bool _syncTraktWatched = true;
  bool _syncSimklRatings = true;
  bool _syncSimklWatched = true;
  bool _isLoadingSettings = false;

  // -- Music Settings --
  bool _useMusicBrainz = true;
  bool _readMusicBrainzTags = true;
  bool _enableAcoustId = false;
  bool _fetchWikidataTrivia = true;
  bool _fetchFanartAndAudioDb = true;
  bool _linkSoundtracksAutomatically = true;

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
      _fallbackSubLangCtrl.text = s['FALLBACK_SUBTITLE_LANG'] ?? 'en';
      _metadataLanguage = s['METADATA_LANGUAGE'] ?? 'sv-SE';
      _fallbackLanguage = s['METADATA_FALLBACK_LANGUAGE'] ?? 'en-US';
      _defaultAudioLanguage = s['DEFAULT_AUDIO_LANG'] ?? 'sv';
      _watchProviderRegion = s['WATCH_PROVIDER_REGION'] ?? 'SE';
      _titleDisplayStyle = s['TITLE_DISPLAY_STYLE'] ?? 'Translated';
      _showReleaseVersion = s['SHOW_RELEASE_VERSION'] != 'false';
      _preferLocalNfo = s['PREFER_LOCAL_NFO'] != 'false';
      _useMusicBrainz = s['USE_MUSICBRAINZ'] != 'false';
      _readMusicBrainzTags = s['READ_MUSICBRAINZ_TAGS'] != 'false';
      _enableAcoustId = s['ENABLE_ACOUSTID'] == 'true';
      _fetchWikidataTrivia = s['FETCH_WIKIDATA_TRIVIA'] != 'false';
      _fetchFanartAndAudioDb = s['FETCH_FANART_AUDIODB'] != 'false';
      _linkSoundtracksAutomatically = s['LINK_SOUNDTRACKS_AUTO'] != 'false';
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
        'FALLBACK_SUBTITLE_LANG': _fallbackSubLangCtrl.text.trim(),
        'METADATA_LANGUAGE': _metadataLanguage,
        'METADATA_FALLBACK_LANGUAGE': _fallbackLanguage,
        'DEFAULT_AUDIO_LANG': _defaultAudioLanguage,
        'WATCH_PROVIDER_REGION': _watchProviderRegion,
        'TITLE_DISPLAY_STYLE': _titleDisplayStyle,
        'SHOW_RELEASE_VERSION': _showReleaseVersion ? 'true' : 'false',
        'PREFER_LOCAL_NFO': _preferLocalNfo ? 'true' : 'false',
        'USE_MUSICBRAINZ': _useMusicBrainz ? 'true' : 'false',
        'READ_MUSICBRAINZ_TAGS': _readMusicBrainzTags ? 'true' : 'false',
        'ENABLE_ACOUSTID': _enableAcoustId ? 'true' : 'false',
        'FETCH_WIKIDATA_TRIVIA': _fetchWikidataTrivia ? 'true' : 'false',
        'FETCH_FANART_AUDIODB': _fetchFanartAndAudioDb ? 'true' : 'false',
        'LINK_SOUNDTRACKS_AUTO': _linkSoundtracksAutomatically ? 'true' : 'false',
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
                if (!widget.apiService.isAdmin && ![0, 4, 5, 6, 7].contains(i)) {
                  return const SizedBox.shrink();
                }
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

}

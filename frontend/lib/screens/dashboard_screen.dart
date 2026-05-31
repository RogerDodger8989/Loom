import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';
import 'dart:ui' as ui;
import '../services/api.dart';
import 'pairing_screen.dart';
import 'media_details_screen.dart';
import 'person_details_screen.dart';

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
  bool _isSidebarExpanded = true;

  final List<Map<String, String>> _navHistory = [];
  final List<Map<String, String>> _forwardHistory = [];

  void _navigateTo(String type, String id) {
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

      if (type == 'media') {
        _selectedMediaId = id;
        _selectedPersonId = null;
      } else if (type == 'person') {
        _selectedPersonId = id;
        _selectedMediaId = null;
      }
      
      _forwardHistory.clear();
    });
  }

  void _goBack() {
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

      final prev = _navHistory.removeLast();
      if (prev['type'] == 'media') {
        _selectedMediaId = prev['id'];
        _selectedPersonId = null;
      } else if (prev['type'] == 'person') {
        _selectedPersonId = prev['id'];
        _selectedMediaId = null;
      }
    });
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

  Widget _buildNavigationButtons() {
    final hasBack = _navHistory.isNotEmpty || _selectedMediaId != null || _selectedPersonId != null;
    final hasForward = _forwardHistory.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          _buildNavIcon(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Gå bakåt',
            enabled: hasBack,
            onPressed: _goBack,
          ),
          const SizedBox(width: 12),
          _buildNavIcon(
            icon: Icons.arrow_forward_ios_rounded,
            tooltip: 'Gå framåt',
            enabled: hasForward,
            onPressed: _goForward,
          ),
        ],
      ),
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
  List<dynamic> _trustedDevices = [];
  bool _isLoadingDevices = false;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _homeSections = _defaultHomeSections();
    _tabController.addListener(() {
      if (_tabController.index == 4) {
        _loadDevices();
        _loadSettings();
      }
    });
    _loadAllMedia();
    _checkScannerStatus();
    _loadLibraryPaths();
    _loadDevices();
    _loadSettings();
  }

  List<Map<String, dynamic>> _defaultHomeSections() {
    return [
      {'id': 'continue_watching', 'title': 'Fortsätt titta', 'visible': true, 'comingSoon': false, 'days': 365},
      {'id': 'recent_movies', 'title': 'Nyligen tillagda Filmer', 'visible': true, 'comingSoon': false},
      {'id': 'recent_watched_movies', 'title': 'Nyligen sedda Filmer', 'visible': true, 'comingSoon': false},
      {'id': 'recent_shows', 'title': 'Nyligen tillagda Serier', 'visible': false, 'comingSoon': true},
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
          _homeSections = parsed.where((section) => (section['id'] ?? '').toString().isNotEmpty).toList();
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
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Avbryt', style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8A5BFF)),
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
          content: Text('Added path: "$folderPath" to ${type == 'Show' ? 'TV Shows' : type == 'Movie' ? 'Movies' : 'Music'}'),
          backgroundColor: const Color(0xFF8A5BFF),
        ),
      );
      _loadLibraryPaths();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add path: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _deletePath(String id) async {
    try {
      await widget.apiService.deleteLibraryPath(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Removed path successfully'),
          backgroundColor: Color(0xFF8A5BFF),
        ),
      );
      _loadLibraryPaths();
      _loadAllMedia();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove path: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _updatePath(String id, String newPath) async {
    try {
      final res = await widget.apiService.updateLibraryPath(id, newPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated path! Bulk modified ${res['updatedCount'] ?? 0} file paths in DB.'),
          backgroundColor: const Color(0xFF8A5BFF),
        ),
      );
      _loadLibraryPaths();
      _loadAllMedia();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update path: $e'), backgroundColor: Colors.redAccent),
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
              title: Text('Edit ${type == 'Show' ? 'TV Show' : type == 'Movie' ? 'Movie' : 'Music'} Folder'),
              content: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Editing this path will update all matching files in your database to the new path prefix.',
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
                              hintText: 'Enter new path or click Browse...',
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
                            label: const Text('Browse...'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
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
                  child: const Text('Save Changes'),
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
        _scanStatusText = _isScanning ? 'Scanning...' : 'Idle';
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
            content: Text('Selected folder: ${result['path']}'),
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
          content: Text('Failed to open native folder browser: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _triggerScan() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid path to scan')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _scanStatusText = 'Starting scan...';
    });

    try {
      final response = await widget.apiService.triggerLibraryScan(
        path, 
        _selectedScanType,
        preferLocalNfo: _preferLocalNfo,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'Scan started successfully!'),
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
        SnackBar(content: Text('Failed to trigger scan: $e'), backgroundColor: Colors.redAccent),
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
          children: [
            // Left sidebar navigation
            _buildSidebar(),

            // Main Content Area
            Expanded(
              child: SafeArea(
                child: _selectedPersonId != null
                    ? PersonDetailsScreen(
                        personId: _selectedPersonId!,
                        apiService: widget.apiService,
                        onBack: _goBack,
                        onMediaSelected: (mediaId) {
                          _navigateTo('media', mediaId);
                        },
                      )
                    : _selectedMediaId != null
                        ? MediaDetailsScreen(
                            mediaId: _selectedMediaId!,
                            apiService: widget.apiService,
                            onBack: _goBack,
                            onGenreSelected: (g) {
                              setState(() {
                                _selectedMediaId = null;
                                _genreFilter = g;
                                _keywordFilter = null; // clear keyword when picking genre
                              });
                              // Switch to Movies tab so the filtered list is visible
                              try {
                                _tabController.animateTo(1);
                              } catch (_) {}
                            },
                            onKeywordSelected: (k) {
                              setState(() {
                                _selectedMediaId = null;
                                _keywordFilter = k;
                                _genreFilter = null; // clear genre when picking keyword
                              });
                              // Ensure Movies tab is selected when filtering by keyword
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
                          )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 30),
                            
                            // Tab views
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildHomeView(),
                                  _buildMoviesView(),
                                  _buildShowsView(),
                                  _buildScannerView(),
                                  _buildSettingsView(),
                                ],
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
          
          // Sidebar Header: back button above collapse/expand control
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _isSidebarExpanded ? 24 : 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNavigationButtons(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: _isSidebarExpanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
                  children: [
                    if (_isSidebarExpanded) ...[
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _tabController.animateTo(0);
                              _selectedMediaId = null;
                              _selectedPersonId = null;
                            });
                          },
                          child: Row(
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
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: IconButton(
                          icon: const Icon(Icons.chevron_left, color: Colors.white54),
                          onPressed: () {
                            setState(() {
                              _isSidebarExpanded = false;
                            });
                          },
                        ),
                      ),
                    ] else ...[
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _isSidebarExpanded = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.menu,
                              color: Color(0xFF8A5BFF),
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Navigation Items (Tab-based)

          _buildSidebarItem(0, Icons.home_outlined, Icons.home, 'Hem'),
          _buildSidebarItem(1, Icons.movie_outlined, Icons.movie, 'Movies'),
          _buildSidebarItem(2, Icons.tv_outlined, Icons.tv, 'TV Shows'),
          _buildSidebarItem(3, Icons.scanner_outlined, Icons.scanner, 'Library Scanner'),
          _buildSidebarItem(4, Icons.settings_outlined, Icons.settings, 'Settings'),
          
          const Spacer(),
          
          // User profile card at bottom
          _buildUserProfileCard(),
          
          const SizedBox(height: 30),
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
          setState(() {
            _tabController.animateTo(index);
            _selectedMediaId = null; // reset selected media details when shifting tabs
          });
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
            onTap: _isSidebarExpanded ? null : _handleLogout,
            child: CircleAvatar(
              backgroundColor: const Color(0xFF8A5BFF),
              radius: 20,
              child: Text(
                'A',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontWeight: FontWeight.bold),
              ),
            ),
          ),
          if (_isSidebarExpanded) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'admin',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    'Server Owner',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white30, size: 20),
              onPressed: _handleLogout,
              tooltip: 'Logga ut',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    try {
      final deviceId = widget.apiService.getOrCreateDeviceId();
      await widget.apiService.unpairDevice(deviceId);
    } catch (e) {
      debugPrint('Error unpairing device on server during logout: $e');
    }

    widget.apiService.clearToken();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const PairingScreen()),
      );
    }
  }

  Widget _buildHeader() {
    final isHome = _tabController.index == 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_tabController.indexIsChanging && !isHome)
              Text(
                _tabController.index == 1
                    ? 'Movies'
                    : _tabController.index == 2
                        ? 'TV Shows'
                        : _tabController.index == 3
                            ? 'Library Scanner'
                            : 'Settings',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            const SizedBox(height: 6),
            if (isHome)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 10),
                      child: IconButton(
                        tooltip: 'Redigera hemsektioner',
                        onPressed: _openHomeLayoutEditor,
                        icon: const Icon(Icons.tune, color: Colors.white70),
                      ),
                    ),
                    SizedBox(
                      width: 680,
                      child: _buildHomeSearchBox(),
                    ),
                  ],
                )
            else
              Text(
                _tabController.index == 3
                    ? 'Manage media scan routes and server settings'
                    : _tabController.index == 4
                        ? 'Manage trusted devices and server preferences'
                        : 'Manage and stream your media collection',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 15),
              ),
          ],
        ),
        
        // Quick Actions
        Row(
          children: [
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
                      'Scanning Library',
                      style: TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            IconButton(
              onPressed: () {
                _loadAllMedia();
                _checkScannerStatus();
              },
              icon: const Icon(Icons.refresh, color: Colors.white70),
              tooltip: 'Refresh Library',
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
    return movies.where((movie) {
      final metadata = movie['metadata'];
      if (metadata is! Map) return false;
      final progress = int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;
      if (progress <= 0) return false;
      return _isWithinDays(movie['last_watched_at']?.toString(), days);
    }).toList();
  }

  List<dynamic> _getRecentlyWatchedMovies(List<dynamic> movies) {
    final watched = movies.where((movie) {
      final metadata = movie['metadata'];
      return metadata is Map && metadata['watch_status'] == 'watched';
    }).toList();

    watched.sort((a, b) {
      final aTime = DateTime.tryParse(a['last_watched_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = DateTime.tryParse(b['last_watched_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
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
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) => _buildHomeCard(items[index]),
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
    final candidates = _movies.where((m) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
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
            if (_homeSearchIsOpen && hasQuery) const SizedBox(height: 10),
            if (_homeSearchIsOpen && hasQuery)
              Container(
                constraints: const BoxConstraints(maxHeight: 340),
                decoration: BoxDecoration(
                  color: const Color(0xFF141820),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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
          ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Chip(
        backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.1),
        side: const BorderSide(color: Color(0xFF8A5BFF)),
        label: Text(_keywordFilter != null ? 'Keyword: $_keywordFilter' : 'Genre: $_genreFilter', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        deleteIcon: const Icon(Icons.close, color: Colors.white, size: 18),
        onDeleted: () {
          setState(() {
            _genreFilter = null;
            _keywordFilter = null;
          });
        },
      ),
    );
  }


  Widget _buildHomeView() {
    final recentMovies = _movies.take(12).toList();
    final watchedMovies = _getRecentlyWatchedMovies(_movies).take(12).toList();

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
                    final continueWatching = _getContinueWatchingMovies(_movies, days).take(8).toList();
                    if (continueWatching.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHomeSectionHeader(title, subtitle: days == null ? 'Ingen begränsning' : 'Senaste $days dagar'),
                          _buildHomePosterStrip(continueWatching),
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
    final posterPath = movie['poster_path'];
    final title = movie['title'] ?? '';
    final year = movie['year']?.toString() ?? '';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final mId = movie['id']?.toString();
          if (mId != null) {
            _navigateTo('media', mId);
          }
        },
        child: Container(
          width: 130,
          margin: const EdgeInsets.only(right: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 5))],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Gradient placeholder background
                      Container(
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
                        child: const Center(
                          child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
                        ),
                      ),
                      
                      // Actual Network Image with CORS fail-safety
                      if (posterPath != null && posterPath.isNotEmpty)
                        Image.network(
                          posterPath,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
                            );
                          },
                        ),
                      
                      // Top-left watched checkmark badge
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Builder(builder: (context) {
                          final metadata = movie['metadata'] ?? {};
                          if (metadata['watch_status'] == 'watched') {
                            return Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF00E676), width: 1.5), // neon green outline
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00E676).withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  )
                                ],
                              ),
                              child: const Icon(Icons.check, color: Color(0xFF00E676), size: 14),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ),
                      
                      // Bottom progress bar if playback_progress > 0
                      Builder(builder: (context) {
                        final metadata = movie['metadata'] ?? {};
                        final progress = int.tryParse((metadata['playback_progress']?.toString() ?? '0')) ?? 0;
                        if (progress <= 0) return const SizedBox.shrink();

                        int duration = int.tryParse((metadata['duration']?.toString() ?? '0')) ?? 0;
                        if (duration == 0) {
                          final runtimeMinutes = int.tryParse((metadata['runtime']?.toString() ?? '0')) ?? 0;
                          duration = runtimeMinutes * 60;
                        }
                        if (duration == 0) {
                          duration = 7200; // 120 min default fallback
                        }
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
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (year.isNotEmpty)
                Text(year, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
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
      return _buildEmptyState('No movies found', 'Go to the Library Scanner tab to import your media files.');
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
                : (_keywordFilter != null ? 'Inga filmer matchar keyword "$_keywordFilter"' : 'Inga filmer matchar genren "$_genreFilter"'),
            'Ta bort filtret för att se alla filmer.'
          )),
        ],
      );
    }

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
            padding: const EdgeInsets.only(top: 10, bottom: 30),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 30,
              crossAxisSpacing: 24,
              childAspectRatio: 0.72,
            ),
            itemCount: filteredMovies.length,
            itemBuilder: (context, index) {
              final movie = filteredMovies[index];
              return _buildMediaCard(movie);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShowsView() {
    if (_loadingMedia) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))));
    }

    if (_mediaError != null) {
      return _buildErrorState(_mediaError!);
    }

    if (_shows.isEmpty) {
      return _buildEmptyState('No TV shows found', 'Go to the Library Scanner tab to import your media files.');
    }

    List<dynamic> filteredShows = _shows;
    if (_genreFilter != null) {
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

    if (filteredShows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGenreFilterBadge(),
          Expanded(child: _buildEmptyState(
            _keywordFilter != null ? 'Inga serier matchar keyword "$_keywordFilter"' : 'Inga serier matchar genren "$_genreFilter"',
            'Ta bort filtret för att se alla serier.'
          )),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_genreFilter != null) _buildGenreFilterBadge(),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(top: 10, bottom: 30),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 30,
              crossAxisSpacing: 24,
              childAspectRatio: 0.72,
            ),
            itemCount: filteredShows.length,
            itemBuilder: (context, index) {
              final show = filteredShows[index];
              return _buildMediaCard(show);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaCard(dynamic item) {
    final title = (_titleDisplayStyle == 'Original' && item['original_title'] != null && (item['original_title'] as String).isNotEmpty)
        ? item['original_title']
        : (item['title'] ?? 'Unknown');
    final type = item['type'] ?? 'Movie';
    final resolution = item['resolution'] ?? '1080p';
    final versionsCount = item['versions'] != null ? (item['versions'] as List).length : 1;
    final metadata = item['metadata'] ?? {};
    final genre = metadata['genre'] ?? 'Media';
    
    // Check if it's TV show to show episodes count
    final episodesCount = item['episodes'] != null ? (item['episodes'] as List).length : 0;
    final posterPath = item['poster_path'];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final mId = item['id']?.toString();
          if (mId != null) {
            _navigateTo('media', mId);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Simulated Poster Area (Glassmorphism & Gradient)
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF8A5BFF).withValues(alpha: 0.1),
                        const Color(0xFF8A5BFF).withValues(alpha: 0.25),
                      ],
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Actual Network Image with CORS fail-safety
                      if (posterPath != null && posterPath.isNotEmpty)
                        Image.network(
                          posterPath,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Icon(
                                type == 'Movie' ? Icons.movie_outlined : Icons.tv_outlined,
                                color: Colors.white24,
                                size: 48,
                              ),
                            );
                          },
                        )
                      else
                        Center(
                          child: Icon(
                            type == 'Movie' ? Icons.movie_outlined : Icons.tv_outlined,
                            color: Colors.white24,
                            size: 48,
                          ),
                        ),
                      
                      // Top-left watched checkmark badge
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Builder(builder: (context) {
                          if (metadata['watch_status'] == 'watched') {
                            return Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF00E676), width: 1.5), // neon green outline
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00E676).withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  )
                                ],
                              ),
                              child: const Icon(Icons.check, color: Color(0xFF00E676), size: 14),
                            );
                          }
                          return const SizedBox.shrink();
                        }),
                      ),
                      
                      // Resolution Badge
                      if (type == 'Movie')
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8A5BFF),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF8A5BFF).withValues(alpha: 0.3),
                                  blurRadius: 6,
                                )
                              ],
                            ),
                            child: Text(
                              resolution.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      // Thumbnail progress bar for in-progress items (only a small bar)
                      if (metadata is Map && int.tryParse((metadata['playback_progress']?.toString() ?? '0')) != null && int.tryParse((metadata['playback_progress']?.toString() ?? '0'))! > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.white12,
                            ),
                            child: Builder(builder: (context) {
                              final progress = int.tryParse((metadata['playback_progress']?.toString() ?? '0')) ?? 0;
                              int duration = int.tryParse((metadata['duration']?.toString() ?? '0')) ?? 0;
                              if (duration == 0) {
                                final runtimeMinutes = int.tryParse((metadata['runtime']?.toString() ?? '0')) ?? 0;
                                duration = runtimeMinutes * 60;
                              }
                              if (duration == 0) {
                                duration = 7200; // 120 min default fallback
                              }
                              final ratio = (progress / duration).clamp(0.0, 1.0);
                              return LinearProgressIndicator(value: ratio, color: const Color(0xFF8A5BFF), backgroundColor: Colors.transparent);
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              // Details Area
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          genre,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          type == 'Movie' 
                            ? (versionsCount > 1 ? '$versionsCount versions' : 'Movie')
                            : '$episodesCount eps',
                          style: TextStyle(
                            color: const Color(0xFFB593FF).withValues(alpha: 0.8),
                            fontSize: 12,
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
    );
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
                _tabController.animateTo(2);
              });
            },
            icon: const Icon(Icons.scanner_outlined),
            label: const Text('Go to Library Scanner'),
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
            'Failed to load library data',
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
            child: const Text('Try Again'),
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
                      Text('Movies', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tv_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('TV Shows', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.music_note_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Music', style: TextStyle(fontWeight: FontWeight.bold)),
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
              'Configured ${type == 'Show' ? 'TV Show' : type == 'Movie' ? 'Movie' : 'Music'} Folders',
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
                'No folders added yet for ${type == 'Show' ? 'TV Shows' : type == 'Movie' ? 'Movies' : 'Music'}.',
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
          'Add ${type == 'Show' ? 'TV Show' : type == 'Movie' ? 'Movie' : 'Music'} Folder',
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
                tooltip: 'Edit Folder Path',
              ),
              
              // Action: Scan folder
              IconButton(
                onPressed: _isScanning 
                  ? null 
                  : () => _triggerScanOfSpecificPath(folderPath, type),
                icon: const Icon(Icons.sync_outlined, color: Colors.greenAccent),
                tooltip: 'Scan Folder Now',
              ),
              
              // Action: Remove path
              IconButton(
                onPressed: () => _deletePath(id),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Remove Folder',
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
      _scanStatusText = 'Scanning $type...';
    });

    try {
      final response = await widget.apiService.triggerLibraryScan(
        folderPath, 
        type,
        preferLocalNfo: _preferLocalNfo,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? 'Scan started successfully!'),
          backgroundColor: const Color(0xFF8A5BFF),
        ),
      );
      
      _pollScannerUntilFinished();
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to trigger scan: $e'), backgroundColor: Colors.redAccent),
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
                    hintText: 'Enter path or click Browse...',
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
                  label: const Text('Browse...'),
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
                'Prefer local NFO metadata',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Import titles and details from local .nfo files instead of fetching online.',
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
                    const SnackBar(content: Text('Please select or enter a folder path')),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: Text(
                'Add Folder to ${type == 'Show' ? 'TV Shows' : type == 'Movie' ? 'Movies' : 'Music'}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoadingDevices = true);
    try {
      final devices = await widget.apiService.fetchDevices();
      setState(() => _trustedDevices = devices);
    } catch (e) {
      debugPrint('Failed to load devices: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDevices = false);
    }
  }

  Future<void> _loadSettings() async {
    if (_isLoadingSettings) return;
    setState(() {
      _isLoadingSettings = true;
    });
    try {
      final settings = await widget.apiService.getSettings();
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
        _isLoadingSettings = false;
      });
    } catch (e) {
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
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inställningar sparade!'), backgroundColor: Color(0xFF8A5BFF)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: $e'), backgroundColor: Colors.redAccent),
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

  Future<void> _renameDevice(String deviceId, String currentName) async {
    final TextEditingController controller = TextEditingController(text: currentName);
    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        title: const Text('Rename Device', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Device name',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF8A5BFF))),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save', style: TextStyle(color: Color(0xFF8A5BFF))),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await widget.apiService.renameDevice(deviceId, newName);
        _loadDevices();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
        }
      }
    }
  }

  Future<void> _removeDevice(String deviceId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF15102A),
        title: const Text('Remove Device?', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to remove this device? It will need to be paired again to access the server.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.apiService.removeDevice(deviceId);
        
        final currentDeviceId = widget.apiService.getOrCreateDeviceId();
        if (deviceId == currentDeviceId) {
           _handleLogout();
        } else {
           _loadDevices();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove: $e')));
        }
      }
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
                  onTap: () => html.window.open('https://www.omdbapi.com/apikey.aspx', '_blank'),
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
                    onPressed: () => html.window.open('https://simkl.com/settings/developer/', '_blank'),
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
                    html.window.open('${widget.apiService.baseUrl}/api/oauth/simkl/authorize', '_blank');
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
                    onPressed: () => html.window.open('https://trakt.tv/oauth/applications', '_blank'),
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
                    html.window.open('${widget.apiService.baseUrl}/api/oauth/trakt/authorize', '_blank');
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
                      'Standard Titelvisning',
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
                    'Prefer local NFO metadata',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Import titles and details from local .nfo files instead of fetching online.',
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
                      'Default Ljudspråk',
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
                      'Default Undertext-språk',
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
          const SizedBox(height: 30),

          // Trusted Devices List
          const Text('Betrodda Enheter', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _isLoadingDevices
              ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Color(0xFF8A5BFF))))
              : _trustedDevices.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('Inga enheter parade än.', style: TextStyle(color: Colors.white38)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _trustedDevices.length,
                      itemBuilder: (context, index) {
                        final device = _trustedDevices[index];
                        final isCurrentDevice = device['device_id'] == widget.apiService.getOrCreateDeviceId();
                        
                        String addedText = '';
                        if (device['paired_at'] != null) {
                          addedText = 'Parat: ${device['paired_at']}';
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Row(
                            children: [
                              Icon(isCurrentDevice ? Icons.devices : Icons.device_unknown, color: const Color(0xFF8A5BFF), size: 28),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(device['device_name'] ?? 'Unknown Device', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                        if (isCurrentDevice) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(color: const Color(0xFF8A5BFF).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                                            child: const Text('Denna Enhet', style: TextStyle(color: Color(0xFFB593FF), fontSize: 11, fontWeight: FontWeight.bold)),
                                          )
                                        ]
                                      ],
                                    ),
                                    if (addedText.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(addedText, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
                                    ]
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.white60),
                                onPressed: () => _renameDevice(device['device_id'], device['device_name'] ?? ''),
                                tooltip: 'Byt namn',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () => _removeDevice(device['device_id']),
                                tooltip: 'Ta bort enhet',
                              ),
                            ],
                          ),
                        );
                      },
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

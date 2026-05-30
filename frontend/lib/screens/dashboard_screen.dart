import 'package:flutter/material.dart';
import 'dart:convert';
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
  final TextEditingController _defaultSubLangController = TextEditingController(text: 'sv');
  bool _isLoadingSettings = false;
  
  String _metadataLanguage = 'sv-SE';
  String _fallbackLanguage = 'en-US';
  String _defaultAudioLanguage = 'sv';
  String _watchProviderRegion = 'SE';
  String _titleDisplayStyle = 'Translated';

  String? _genreFilter;
  String? _keywordFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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

  @override
  void dispose() {
    _tabController.dispose();
    _pathController.dispose();
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
                        onBack: () {
                          setState(() {
                            _selectedPersonId = null;
                          });
                        },
                        onMediaSelected: (mediaId) {
                          setState(() {
                            _selectedPersonId = null;
                            _selectedMediaId = mediaId;
                          });
                        },
                      )
                    : _selectedMediaId != null
                        ? MediaDetailsScreen(
                            mediaId: _selectedMediaId!,
                            apiService: widget.apiService,
                            onBack: () {
                              setState(() {
                                _selectedMediaId = null;
                              });
                            },
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
                              setState(() {
                                _selectedMediaId = mediaId;
                              });
                            },
                            onPersonSelected: (personId) {
                              setState(() {
                                _selectedPersonId = personId;
                              });
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
              children: [
                if (_selectedMediaId != null || _selectedPersonId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: _isSidebarExpanded ? Alignment.centerLeft : Alignment.center,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: IconButton(
                          tooltip: 'Tillbaka',
                          icon: const Icon(Icons.arrow_back, color: Colors.white70),
                          padding: _isSidebarExpanded ? const EdgeInsets.all(8) : EdgeInsets.zero,
                          constraints: _isSidebarExpanded ? const BoxConstraints() : const BoxConstraints(maxWidth: 36, maxHeight: 36),
                          onPressed: () {
                            setState(() {
                              _selectedMediaId = null;
                              _selectedPersonId = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tabController.index == 0
                  ? 'Hem'
                  : _tabController.index == 1
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
            Text(
              _tabController.index == 0
                  ? 'Din mediesamling och aktivitet'
                  : _tabController.index == 3
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
    final inProgress = _movies.where((m) {
      final meta = m['metadata'];
      if (meta is Map) {
        final progress = int.tryParse(meta['playback_progress']?.toString() ?? '0') ?? 0;
        return progress > 0;
      }
      return false;
    }).take(8).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Banner
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF8A5BFF).withValues(alpha: 0.15),
                  Colors.transparent,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF8A5BFF).withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill, color: Color(0xFF8A5BFF), size: 48),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Välkommen till Loom', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Välj ett innehåll och börja se.', style: TextStyle(color: Colors.white54, fontSize: 15)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),

          // Continue Watching Section
          if (inProgress.isNotEmpty) ...[
            const Text('Fortsätt titta', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: inProgress.length,
                itemBuilder: (context, index) {
                  final movie = inProgress[index];
                  return _buildHomeCard(movie);
                },
              ),
            ),
            const SizedBox(height: 32),
          ],

          // Recently Added Section
          if (recentMovies.isNotEmpty) ...[
            const Text('Nyligen tillagda', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: recentMovies.length,
                itemBuilder: (context, index) {
                  final movie = recentMovies[index];
                  return _buildHomeCard(movie);
                },
              ),
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
          setState(() {
            _selectedMediaId = movie['id']?.toString();
          });
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
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 5))],
                    image: posterPath != null
                        ? DecorationImage(image: NetworkImage(posterPath), fit: BoxFit.cover)
                        : null,
                  ),
                  child: posterPath == null
                      ? const Center(child: Icon(Icons.movie, color: Colors.white24, size: 32))
                      : null,
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

    if (filteredMovies.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGenreFilterBadge(),
          Expanded(child: _buildEmptyState(
            _keywordFilter != null ? 'Inga filmer matchar keyword "$_keywordFilter"' : 'Inga filmer matchar genren "$_genreFilter"',
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
          setState(() {
            _selectedMediaId = item['id'].toString();
          });
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
                    image: posterPath != null
                        ? DecorationImage(
                            image: NetworkImage(posterPath),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: Stack(
                    children: [
                      if (posterPath == null)
                        Center(
                          child: Icon(
                            type == 'Movie' ? Icons.movie_outlined : Icons.tv_outlined,
                            color: Colors.white24,
                            size: 48,
                          ),
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
                            decoration: BoxDecoration(
                              color: Colors.white12,
                            ),
                            child: Builder(builder: (context) {
                              final progress = int.tryParse((metadata['playback_progress']?.toString() ?? '0')) ?? 0;
                              final duration = int.tryParse((metadata['duration']?.toString() ?? '0')) ?? 0;
                              final ratio = (duration > 0) ? (progress / duration).clamp(0.0, 1.0) : 0.0;
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
              onChanged: (bool val) {
                setState(() {
                  _preferLocalNfo = val;
                });
              },
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
        _defaultSubLangController.text = settings['DEFAULT_SUBTITLE_LANG'] ?? 'sv';
        _metadataLanguage = settings['METADATA_LANGUAGE'] ?? 'sv-SE';
        _fallbackLanguage = settings['METADATA_FALLBACK_LANGUAGE'] ?? 'en-US';
        _defaultAudioLanguage = settings['DEFAULT_AUDIO_LANG'] ?? 'sv';
        _watchProviderRegion = settings['WATCH_PROVIDER_REGION'] ?? 'SE';
        _titleDisplayStyle = settings['TITLE_DISPLAY_STYLE'] ?? 'Translated';
        _preferLocalNfo = settings['PREFER_LOCAL_NFO'] != 'false';
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
        'DEFAULT_SUBTITLE_LANG': _defaultSubLangController.text.trim(),
        'METADATA_LANGUAGE': _metadataLanguage,
        'METADATA_FALLBACK_LANGUAGE': _fallbackLanguage,
        'DEFAULT_AUDIO_LANG': _defaultAudioLanguage,
        'WATCH_PROVIDER_REGION': _watchProviderRegion,
        'TITLE_DISPLAY_STYLE': _titleDisplayStyle,
        'PREFER_LOCAL_NFO': _preferLocalNfo ? 'true' : 'false',
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
          const SizedBox(height: 30),

          // Metadata & Library Scanner Preferences
          _buildSettingsSection(
            'Bibliotek & Metadata',
            Icons.library_books_outlined,
            [
              _buildSettingField('TMDB API Nyckel', _tmdbKeyController, obscure: true),
              const SizedBox(height: 20),
              _buildSettingField('OMDb API Nyckel', _omdbKeyController, obscure: true),
              const SizedBox(height: 20),
              _buildSettingField('Simkl Client ID', _simklKeyController, obscure: true),
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
                  onChanged: (bool val) {
                    setState(() {
                      _preferLocalNfo = val;
                    });
                  },
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

          // Trakt / Simkl Sync Section
          _buildSettingsSection(
            'Tredjepartssynkning (Tvåvägs)',
            Icons.sync,
            [
              Row(
                children: [
                  Expanded(
                    child: _buildSyncCard(
                      'Trakt.tv',
                      'Synkronisera din watch-historik och 0-10 betyg automatiskt.',
                      Colors.redAccent,
                      () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Öppnar Trakt OAuth...')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _buildSyncCard(
                      'Simkl',
                      'Håll din Simkl anime- och filmprofil uppdaterad automatiskt.',
                      Colors.green,
                      () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Öppnar Simkl OAuth...')),
                        );
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

  Widget _buildSyncCard(String label, String description, Color color, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(description, style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4)),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: onTap,
            child: const Text('Anslut konto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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

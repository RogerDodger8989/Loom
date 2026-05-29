import 'package:flutter/material.dart';
import '../services/api.dart';

class DashboardScreen extends StatefulWidget {
  final ApiService apiService;

  const DashboardScreen({super.key, required this.apiService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<dynamic> _movies = [];
  List<dynamic> _shows = [];
  bool _loadingMedia = false;
  String? _mediaError;

  // Scanner form state
  final TextEditingController _pathController = TextEditingController(text: 'C:\\Media\\Movies');
  String _selectedScanType = 'Movie';
  bool _isScanning = false;
  String _scanStatusText = 'Idle';
  Map<String, dynamic>? _lastScanResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllMedia();
    _checkScannerStatus();
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

  Future<void> _checkScannerStatus() async {
    try {
      final status = await widget.apiService.getLibraryStatus();
      setState(() {
        _isScanning = status['isScanning'] ?? false;
        _lastScanResult = status['lastScanResult'];
        _scanStatusText = _isScanning ? 'Scanning...' : 'Idle';
      });
    } catch (e) {
      debugPrint('Error checking scanner status: $e');
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
      final response = await widget.apiService.triggerLibraryScan(path, _selectedScanType);
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
        _scanStatusText = 'Error';
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
                child: Padding(
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
                            _buildMoviesView(),
                            _buildShowsView(),
                            _buildScannerView(),
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
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0B21).withOpacity(0.6),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.06), width: 1.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 45),
          
          // Brand Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8A5BFF).withOpacity(0.15),
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
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 50),
          
          // Navigation Items (Tab-based)
          _buildSidebarItem(0, Icons.movie_outlined, Icons.movie, 'Movies'),
          _buildSidebarItem(1, Icons.tv_outlined, Icons.tv, 'TV Shows'),
          _buildSidebarItem(2, Icons.scanner_outlined, Icons.scanner, 'Library Scanner'),
          
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: InkWell(
        onTap: () {
          setState(() {
            _tabController.animateTo(index);
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF8A5BFF).withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF8A5BFF).withOpacity(0.2) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? filledIcon : outlineIcon,
                color: isSelected ? const Color(0xFFB593FF) : Colors.white54,
                size: 22,
              ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfileCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF8A5BFF),
            radius: 20,
            child: Text(
              'A',
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.bold),
            ),
          ),
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
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
                  ? 'Movies' 
                  : _tabController.index == 1 
                      ? 'TV Shows' 
                      : 'Server Control Panel',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _tabController.index == 2 
                  ? 'Manage media scan routes and server settings'
                  : 'Manage and stream your media collection',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
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
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
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

    return GridView.builder(
      padding: const EdgeInsets.only(top: 10, bottom: 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 30,
        crossAxisSpacing: 24,
        childAspectRatio: 0.72,
      ),
      itemCount: _movies.length,
      itemBuilder: (context, index) {
        final movie = _movies[index];
        return _buildMediaCard(movie);
      },
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

    return GridView.builder(
      padding: const EdgeInsets.only(top: 10, bottom: 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 30,
        crossAxisSpacing: 24,
        childAspectRatio: 0.72,
      ),
      itemCount: _shows.length,
      itemBuilder: (context, index) {
        final show = _shows[index];
        return _buildMediaCard(show);
      },
    );
  }

  Widget _buildMediaCard(dynamic item) {
    final title = item['title'] ?? 'Unknown';
    final type = item['type'] ?? 'Movie';
    final resolution = item['resolution'] ?? '1080p';
    final versionsCount = item['versions'] != null ? (item['versions'] as List).length : 1;
    final metadata = item['metadata'] ?? {};
    final genre = metadata['genre'] ?? 'Media';
    
    // Check if it's TV show to show episodes count
    final episodesCount = item['episodes'] != null ? (item['episodes'] as List).length : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
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
                    const Color(0xFF8A5BFF).withOpacity(0.1),
                    const Color(0xFF8A5BFF).withOpacity(0.25),
                  ],
                ),
              ),
              child: Stack(
                children: [
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
                              color: const Color(0xFF8A5BFF).withOpacity(0.3),
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
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      type == 'Movie' 
                        ? (versionsCount > 1 ? '$versionsCount versions' : 'Movie')
                        : '$episodesCount eps',
                      style: TextStyle(
                        color: const Color(0xFFB593FF).withOpacity(0.8),
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
              color: Colors.white.withOpacity(0.02),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.04)),
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
            style: TextStyle(
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
            style: TextStyle(color: Colors.white30, fontSize: 14),
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
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF8A5BFF).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF8A5BFF).withOpacity(0.15)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFB593FF)),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Use this control to scanner folder routes on your server. Loom will scan the directories, match files with metadata providers, and update your libraries automatically.',
                      style: TextStyle(color: Color(0xFFD4C4FF), height: 1.4, fontSize: 14.5),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 35),
            
            // Scanner Configuration Form
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Trigger Background Directory Scan',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 25),
                  
                  // Media Type Dropdown
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 150,
                        child: Text(
                          'Library Type:',
                          style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedScanType,
                              dropdownColor: const Color(0xFF0F0B21),
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                              items: ['Movie', 'Show', 'Music']
                                  .map((type) => DropdownMenuItem(
                                        value: type,
                                        child: Text(
                                          type == 'Show' ? 'TV Shows' : type,
                                          style: const TextStyle(color: Colors.white, fontSize: 15),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedScanType = val;
                                    if (val == 'Movie') {
                                      _pathController.text = 'C:\\Media\\Movies';
                                    } else if (val == 'Show') {
                                      _pathController.text = 'C:\\Media\\TV Shows';
                                    } else {
                                      _pathController.text = 'C:\\Media\\Music';
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Directory Path Input
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 150,
                        child: Text(
                          'Folder Path:',
                          style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _pathController,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.4),
                            hintText: 'Enter absolute path (e.g. C:\\Movies)',
                            hintStyle: const TextStyle(color: Colors.white24),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF8A5BFF), width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 35),
                  
                  // Action buttons
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8A5BFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isScanning ? null : _triggerScan,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(
                        _isScanning ? 'Scan in Progress...' : 'Start Directory Scan',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Scanner Status / Log Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.01),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Scanner Status',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _isScanning 
                              ? const Color(0xFFF59E0B).withOpacity(0.12)
                              : Colors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _scanStatusText.toUpperCase(),
                          style: TextStyle(
                            color: _isScanning ? const Color(0xFFF59E0B) : Colors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 15),
                  
                  if (_lastScanResult != null) ...[
                    _buildStatusRow('Last Scan Completed:', _lastScanResult!['timestamp'] ?? 'Never'),
                    _buildStatusRow('Scan Result:', _lastScanResult!['success'] == true ? 'Success' : 'Failed', isSuccess: _lastScanResult!['success'] == true),
                    if (_lastScanResult!['scannedFiles'] != null)
                      _buildStatusRow('Files Scanned:', _lastScanResult!['scannedFiles'].toString()),
                    if (_lastScanResult!['newMovies'] != null)
                      _buildStatusRow('New Movies Added:', _lastScanResult!['newMovies'].toString()),
                    if (_lastScanResult!['newEpisodes'] != null)
                      _buildStatusRow('New Episodes Added:', _lastScanResult!['newEpisodes'].toString()),
                    if (_lastScanResult!['error'] != null)
                      _buildStatusRow('Details/Errors:', _lastScanResult!['error'], isError: true),
                  ] else ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'No prior scan results recorded in this server session',
                          style: TextStyle(color: Colors.white24, fontSize: 14),
                        ),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, {bool? isSuccess, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isSuccess != null 
                    ? (isSuccess ? Colors.green : Colors.redAccent)
                    : isError ? Colors.redAccent : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

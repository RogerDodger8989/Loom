import 'package:flutter/material.dart';
import '../services/api.dart';

class MergeMediaDialog extends StatefulWidget {
  final Map<String, dynamic> sourceShow;
  final ApiService apiService;
  final VoidCallback onMergeSuccess;

  const MergeMediaDialog({
    Key? key,
    required this.sourceShow,
    required this.apiService,
    required this.onMergeSuccess,
  }) : super(key: key);

  @override
  State<MergeMediaDialog> createState() => _MergeMediaDialogState();
}

class _MergeMediaDialogState extends State<MergeMediaDialog> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<dynamic> _allShows = [];
  List<dynamic> _filteredShows = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isMerging = false;

  @override
  void initState() {
    super.initState();
    _fetchShows();
  }

  Future<void> _fetchShows() async {
    try {
      final shows = await widget.apiService.fetchShows();
      if (mounted) {
        setState(() {
          _allShows = shows.where((s) => s['id'] != widget.sourceShow['id']).toList();
          _filteredShows = _allShows;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Kunde inte hämta serier: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _filterShows(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredShows = _allShows;
      });
    } else {
      final q = query.toLowerCase();
      setState(() {
        _filteredShows = _allShows.where((s) {
          final title = (s['title'] ?? '').toString().toLowerCase();
          return title.contains(q);
        }).toList();
      });
    }
  }

  Future<void> _mergeInto(dynamic targetShow) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181D26),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        title: const Text('Bekräfta sammanslagning', style: TextStyle(color: Colors.white)),
        content: Text(
          'Är du säker på att du vill slå ihop "${widget.sourceShow['title']}" in i "${targetShow['title']}"?\n\nDetta kommer att flytta över alla avsnitt till målserien och ta bort källserien från databasen.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8A5BFF), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Slå ihop'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isMerging = true;
    });

    try {
      await widget.apiService.mergeMediaItems(widget.sourceShow['id'].toString(), targetShow['id'].toString());
      if (mounted) {
        Navigator.pop(context); // stäng dialogen
        widget.onMergeSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Fel vid sammanslagning: $e';
          _isMerging = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF11151D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Slå ihop "${widget.sourceShow['title']}"',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Välj den serie du vill flytta över avsnitten till. Källserien kommer att döljas när sammanslagningen är klar.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (_errorMessage.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.red.withValues(alpha: 0.1),
                child: Text(_errorMessage, style: const TextStyle(color: Colors.redAccent)),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _searchController,
              onChanged: _filterShows,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Sök efter mål-serie...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF171C26),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _isMerging
                      ? const Center(
                          child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Slår ihop serier...', style: TextStyle(color: Colors.white70))
                          ],
                        ))
                      : _filteredShows.isEmpty
                          ? const Center(child: Text('Inga andra serier hittades', style: TextStyle(color: Colors.white54)))
                          : ListView.builder(
                              itemCount: _filteredShows.length,
                              itemBuilder: (context, index) {
                                final show = _filteredShows[index];
                                return Card(
                                  color: const Color(0xFF171C26),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    title: Text(show['title'] ?? 'Okänd serie',
                                        style: const TextStyle(color: Colors.white)),
                                    subtitle: Text(show['year']?.toString() ?? '',
                                        style: const TextStyle(color: Colors.white54)),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF8A5BFF).withValues(alpha: 0.2),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => _mergeInto(show),
                                      child: const Text('Välj denna'),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Avbryt', style: TextStyle(color: Colors.white70)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

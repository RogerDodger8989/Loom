import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:async';
import 'package:universal_html/html.dart' as html;
import '../utils/platform_view_registry.dart' as ui_web;
import '../services/api.dart';
import '../screens/fix_match_dialog.dart';
import '../screens/media_info_dialog.dart';
import '../widgets/merge_media_dialog.dart';

class MediaActionsHelper {
  final BuildContext context;
  final ApiService apiService;
  final Future<void> Function() onRefresh;
  final void Function(String type, String id) onNavigate;
  final void Function(String itemId)? onDelete;

  MediaActionsHelper({
    required this.context,
    required this.apiService,
    required this.onRefresh,
    required this.onNavigate,
    this.onDelete,
  });

  Future<void> _showInfoMessage(String message) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmAction(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF181D26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt', style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8A5BFF), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bekräfta'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> openPosterActionsMenu(dynamic item, {required bool isHomeCard, Offset? globalPos, RelativeRect? position}) async {
    final itemId = item['id']?.toString();
    final tmdbId = item['tmdb_id']?.toString();

    if (itemId == null && tmdbId == null) return;

    RelativeRect effectivePosition = position ?? RelativeRect.fromLTRB(MediaQuery.of(context).size.width / 2 - 10, MediaQuery.of(context).size.height / 2 - 10, 0, 0);
    if (globalPos != null) {
      final overlay = Overlay.of(context)?.context.findRenderObject() as RenderBox?;
      if (overlay != null) {
        effectivePosition = RelativeRect.fromRect(Rect.fromPoints(globalPos, globalPos), Offset.zero & overlay.size);
      }
    }

    if (itemId == null && tmdbId != null) {
      final selected = await showMenu<String>(
        context: context,
        color: const Color(0xFF11151D),
        position: effectivePosition,
        items: [
          const PopupMenuItem(
            value: 'watchlist',
            child: Text('Lägg till i bevakningslista'),
          ),
        ],
      );
      if (selected == 'watchlist') {
        try {
          await apiService.addToWatchlist(
            tmdbId: tmdbId,
            title: item['title'] ?? 'Okänd',
            type: item['type'] ?? 'Movie',
            year: item['year'] != null ? int.tryParse(item['year'].toString()) : null,
          );
          _showInfoMessage('Tillagd i bevakningslista');
        } catch (e) {
          _showInfoMessage('Fel vid tillägg i bevakningslista: $e');
        }
      }
      return;
    }

    if (itemId == null) return;

    final metadata = (item['metadata'] is Map ? Map<String, dynamic>.from(item['metadata'] as Map) : <String, dynamic>{});
    final progress = int.tryParse(metadata['playback_progress']?.toString() ?? '0') ?? 0;
    final watched = metadata['watch_status']?.toString() == 'watched';
    final isShow = (item['type']?.toString() ?? '') == 'Show';
    final isFavorite = item['is_favorite'] == true || item['is_favorite'] == 1;

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
      if (isShow) const PopupMenuItem(value: 'merge', child: Text('Slå ihop serie')),
      const PopupMenuItem(value: 'edit', child: Text('Redigera')),
      const PopupMenuItem(value: 'fix_match', child: Text('Fixa matchning')),
      const PopupMenuItem(value: 'unmatch', child: Text('Ta bort matchning')),
      if (apiService.currentUserPayload?['role'] == 'Admin')
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

  if (selected == 'info') {
    _showMediaInfoDialog(item);
    return;
  }

    if (selected == 'edit') {
      openMediaEditor(item);
      return;
    }

  if (selected == 'stats') {
    _showMediaStatsDialog(item);
    return;
  }

  try {
    switch (selected) {
      case 'clear_continue':
        await apiService.saveMediaMetadata(itemId, 'playback_progress', '0');
        break;
      case 'favorite':
        await apiService.toggleFavorite(itemId, isFavorite: true);
        break;
      case 'unfavorite':
        await apiService.toggleFavorite(itemId, isFavorite: false);
        break;
      case 'playlist':
        final playlistName = await _promptText('Lägg till på spellista', 'Spellistnamn');
        if (playlistName != null && playlistName.trim().isNotEmpty) {
          await apiService.createPlaylistAndAddItem(playlistName.trim(), itemId);
        }
        break;
      case 'mark_watched':
        await apiService.toggleSeenStatus(itemId, true);
        break;
      case 'mark_unwatched':
        await apiService.toggleSeenStatus(itemId, false);
        break;
      case 'mark_all_seasons_watched':
        final episodes = (item['episodes'] as List? ?? []);
        final seasons = <int>{};
        for (final ep in episodes) {
          final s = int.tryParse(ep['season_number']?.toString() ?? '');
          if (s != null) seasons.add(s);
        }
        for (final s in seasons) {
          await apiService.markSeasonSeen(itemId, s, true);
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
          await apiService.markSeasonSeen(itemId, s, false);
        }
        break;
      case 'refresh':
        await apiService.refreshMediaMetadata(itemId);
        break;
      case 'analyze':
        await apiService.analyzeMediaItem(itemId);
        break;
      case 'merge':
        if (!context.mounted) break;
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => MergeMediaDialog(
            sourceShow: item,
            apiService: apiService,
            onMergeSuccess: () => onRefresh(),
          ),
        );
        break;
      case 'fix_match':
        if (!context.mounted) break;
        await showDialog(
          context: context,
          barrierDismissible: true,
          builder: (_) => FixMatchDialog(
            mediaId: itemId,
            apiService: apiService,
            currentTitle: item['title']?.toString() ?? '',
            currentYear: item['year']?.toString() ?? '',
            isShow: isShow,
            onMatchSuccess: () => onRefresh(),
          ),
        );
        break;
      case 'unmatch':
        await apiService.unmatchMediaItem(itemId);
        break;
      case 'delete':
        if (await _confirmAction('Flytta till papperskorgen?', 'Ska detta media flyttas till papperskorgen?')) {
          await apiService.deleteMediaItem(itemId);
        }
        break;
    }

    await onRefresh();
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kunde inte utföra åtgärden: $e')));
      }
}

  Future<void> openMediaEditor(dynamic item) async {
  final itemId = item['id']?.toString();
  if (itemId == null) return;

  Map<String, dynamic> details = item is Map<String, dynamic> ? Map<String, dynamic>.from(item) : <String, dynamic>{};
  Map<String, dynamic> metadataState = {};

  try {
    details = Map<String, dynamic>.from(await apiService.fetchMediaDetails(itemId));
    final state = await apiService.fetchMediaMetadataState(itemId);
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
    await apiService.updateMediaItemFields(itemId, {
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
      await apiService.saveMediaMetadata(itemId, entry.key, entry.value);
    }

    for (final entry in lockState.entries) {
      await apiService.setMediaMetadataLock(itemId, entry.key, entry.value);
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
                                      await onRefresh();
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

void _showMediaInfoDialog(dynamic item) {
  final itemId = item['id']?.toString();
  if (itemId == null) return;
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => MediaInfoDialog(
      mediaId: itemId,
      title: item['title']?.toString() ?? 'Media',
      apiService: apiService,
    ),
  );
}

void _showMediaStatsDialog(dynamic item) {
  final itemId = item['id']?.toString();
  if (itemId == null) return;
  final mediaTitle = item['title']?.toString() ?? 'Statistik';
  final future = apiService.fetchMediaPlays(itemId);

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
                        // play_history rows: watched_at + source are the key fields
                        final watchedAt = (p['watched_at'] as String?) ?? '';
                        final source    = (p['source']     as String?) ?? 'local';

                        // Format ISO timestamp → "2018-01-28 19:29"
                        String formatDate(String iso) {
                          if (iso.length < 16) return iso;
                          return iso.replaceFirst('T', ' ').substring(0, 16);
                        }

                        Widget sourceChip;
                        if (source == 'trakt') {
                          sourceChip = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFED1C24).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('trakt',
                                style: TextStyle(color: Color(0xFFED1C24), fontSize: 10, fontWeight: FontWeight.w600)),
                          );
                        } else if (source == 'simkl') {
                          sourceChip = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('simkl',
                                style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.w600)),
                          );
                        } else {
                          sourceChip = Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('lokal',
                                style: TextStyle(color: Colors.white54, fontSize: 10)),
                          );
                        }

                        line1 = null;
                        line2 = watchedAt.isNotEmpty ? formatDate(watchedAt) : '—';
                        trailing = sourceChip;

                        // Fallback: old watch_history data (no watched_at field, has updated_at)
                        if (watchedAt.isEmpty && p.containsKey('updated_at')) {
                          final isWatched = (p['is_watched'] as num?)?.toInt() == 1;
                          final durSec    = (p['total_duration_seconds'] as num?)?.toInt() ?? 0;
                          final posSec    = (p['last_position_seconds']  as num?)?.toInt() ?? 0;
                          final pct       = durSec > 0 ? (posSec / durSec * 100).round() : 0;
                          final updAt     = (p['updated_at'] as String?) ?? '';
                          line2    = updAt.length >= 16 ? updAt.substring(0, 16) : updAt;
                          trailing = isWatched
                              ? const Icon(Icons.check_circle, size: 14, color: Colors.greenAccent)
                              : Text('$pct% sedd',
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11));
                        }
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



}

"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = libraryRoutes;
exports.setupFileWatchers = setupFileWatchers;
const scanner_1 = require("../services/scanner");
const child_process_1 = require("child_process");
const fs = __importStar(require("fs"));
const database_1 = __importDefault(require("../config/database"));
const crypto_1 = __importDefault(require("crypto"));
const rating_sync_1 = require("../services/rating_sync");
const notify_1 = require("../services/notify");
const scan_events_1 = require("../services/scan_events");
let isScanning = false;
let lastScanResult = null;
async function libraryRoutes(fastify) {
    // POST /api/library/scan
    // Triggers media directory scanning in the background
    fastify.post('/api/library/scan', async (request, reply) => {
        const { path: scanPath, type, preferLocalNfo } = request.body;
        if (!scanPath || !type) {
            return reply.code(400).send({ error: 'Parameters "path" and "type" are required' });
        }
        if (!['Movie', 'Show', 'Music'].includes(type)) {
            return reply.code(400).send({ error: 'Type must be one of: Movie, Show, Music' });
        }
        if (isScanning) {
            return reply.code(409).send({ error: 'A library scan is already in progress' });
        }
        isScanning = true;
        lastScanResult = null;
        // Execute scanning asynchronously in the background
        const localNfoPref = preferLocalNfo !== false;
        console.log(`[Library] Initiating background scan of "${scanPath}" (${type})...`);
        scanner_1.mediaScanner.scanLibrary(scanPath, type, localNfoPref)
            .then((result) => {
            isScanning = false;
            lastScanResult = {
                success: true,
                timestamp: new Date().toISOString(),
                itemsAdded: result.added,
                itemsUpdated: result.updated
            };
            console.log(`[Library] Background scan finished successfully. Added: ${result.added}, Updated: ${result.updated}`);
            // Skicka notifiering om nya/uppdaterade objekt hittades
            (0, notify_1.notifyScanComplete)(result.added, result.updated, scanPath).catch(() => { });
            // Trigger external sync immediately so new items can get ratings/watch statuses matched
            (0, rating_sync_1.syncAllExternalData)().catch(e => {
                console.error('[Library Scan Sync] Failed to run syncAllExternalData:', e);
            });
        })
            .catch((err) => {
            isScanning = false;
            lastScanResult = {
                success: false,
                timestamp: new Date().toISOString(),
                error: err.message || String(err)
            };
            console.error(`[Library] Background scan failed:`, err);
        });
        return reply.code(202).send({
            message: 'Library scan triggered successfully in the background',
            status: 'scanning'
        });
    });
    // GET /api/library/status
    // Returns current scanner state
    fastify.get('/api/library/status', async (request, reply) => {
        return reply.send({
            isScanning,
            lastScanResult
        });
    });
    // GET /api/library/browse-native
    // Pops up a 100% native Windows Folder Browser Dialog on the host server
    fastify.get('/api/library/browse-native', async (request, reply) => {
        return new Promise((resolve) => {
            // PowerShell script to launch a native STA FolderBrowserDialog
            const psScript = `
          [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null;
          $f = New-Object System.Windows.Forms.FolderBrowserDialog;
          $f.Description = 'Select Media Folder for Loom Server';
          $f.ShowNewFolderButton = $true;
          if ($f.ShowDialog() -eq 'OK') {
            Write-Output $f.SelectedPath;
          }
        `.replace(/\s+/g, ' ').trim();
            console.log('[Library] Opening native Windows folder browser...');
            (0, child_process_1.exec)(`powershell -NoProfile -STA -Command "${psScript}"`, (error, stdout, stderr) => {
                if (error) {
                    console.error('[Library] Browse native error:', error);
                    return resolve(reply.code(500).send({ error: 'Failed to open directory browser' }));
                }
                const selectedPath = stdout.trim();
                if (!selectedPath) {
                    console.log('[Library] Native folder browser was cancelled.');
                    return resolve(reply.send({ cancelled: true }));
                }
                console.log(`[Library] User selected folder: "${selectedPath}"`);
                return resolve(reply.send({ path: selectedPath }));
            });
        });
    });
    // GET /api/library/scan-events
    // Poll for real-time scanner events (sinceId for incremental polling)
    fastify.get('/api/library/scan-events', async (request, reply) => {
        const { sinceId } = request.query;
        const sinceIdNum = sinceId ? parseInt(sinceId, 10) : undefined;
        return reply.send({ events: (0, scan_events_1.getScanEvents)(sinceIdNum) });
    });
    // GET /api/library/paths
    // Retrieves all configured media library scan paths with media counts
    fastify.get('/api/library/paths', async (request, reply) => {
        try {
            const paths = database_1.default.prepare('SELECT * FROM library_paths ORDER BY added_at ASC').all();
            const withCounts = paths.map(p => {
                let count = 0;
                try {
                    if (p.type === 'Movie') {
                        const row = database_1.default.prepare("SELECT COUNT(*) as cnt FROM media_items WHERE type='Movie' AND file_path LIKE ? AND deleted_at IS NULL").get(p.path + '%');
                        count = row?.cnt ?? 0;
                    }
                    else if (p.type === 'Show') {
                        const row = database_1.default.prepare("SELECT COUNT(*) as cnt FROM episodes WHERE file_path LIKE ?").get(p.path + '%');
                        count = row?.cnt ?? 0;
                    }
                    else if (p.type === 'Music') {
                        const row = database_1.default.prepare("SELECT COUNT(*) as cnt FROM music_tracks WHERE file_path LIKE ?").get(p.path + '%');
                        count = row?.cnt ?? 0;
                    }
                }
                catch (_) { }
                return { ...p, media_count: count };
            });
            return reply.send(withCounts);
        }
        catch (err) {
            console.error('[Library] Failed to retrieve paths:', err);
            return reply.code(500).send({ error: 'Failed to retrieve library paths' });
        }
    });
    // PUT /api/library/paths/watch
    // Toggle watch_for_changes on a library path
    fastify.put('/api/library/paths/watch', async (request, reply) => {
        const { id, watch } = request.body;
        if (!id)
            return reply.code(400).send({ error: 'Parameter "id" is required' });
        try {
            database_1.default.prepare('UPDATE library_paths SET watch_for_changes = ? WHERE id = ?').run(watch ? 1 : 0, id);
            // Restart file watchers
            setupFileWatchers();
            return reply.send({ success: true });
        }
        catch (err) {
            console.error('[Library] Failed to toggle watch_for_changes:', err);
            return reply.code(500).send({ error: 'Failed to update watch setting' });
        }
    });
    // GET /api/library/export
    // Export watched status and ratings as JSON
    fastify.get('/api/library/export', async (request, reply) => {
        try {
            const items = database_1.default.prepare(`
          SELECT
            mi.id, mi.title, mi.type, mi.year, mi.imdb_id, mi.tmdb_id,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'watch_status') as watch_status,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'playback_progress') as playback_progress,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'duration') as duration,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'my_rating') as my_rating,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'imdb_rating') as imdb_rating,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'trakt_rating') as trakt_rating,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'simkl_rating') as simkl_rating,
            (SELECT metadata_value FROM media_metadata WHERE media_item_id = mi.id AND metadata_key = 'last_watched_at') as last_watched_at
          FROM media_items mi
          WHERE mi.deleted_at IS NULL
          ORDER BY mi.type, mi.title
        `).all();
            const format = request.query.format || 'json';
            if (format === 'csv') {
                const header = 'id,title,type,year,imdb_id,tmdb_id,watch_status,playback_progress,duration,my_rating,imdb_rating,trakt_rating,simkl_rating,last_watched_at';
                const rows = items.map(i => [i.id, `"${(i.title || '').replace(/"/g, '""')}"`, i.type, i.year, i.imdb_id || '',
                    i.tmdb_id || '', i.watch_status || '', i.playback_progress || '', i.duration || '',
                    i.my_rating || '', i.imdb_rating || '', i.trakt_rating || '', i.simkl_rating || '',
                    i.last_watched_at || ''].join(','));
                const csv = [header, ...rows].join('\n');
                reply.header('Content-Type', 'text/csv; charset=utf-8');
                reply.header('Content-Disposition', `attachment; filename="loom-export-${new Date().toISOString().slice(0, 10)}.csv"`);
                return reply.send(csv);
            }
            reply.header('Content-Type', 'application/json');
            reply.header('Content-Disposition', `attachment; filename="loom-export-${new Date().toISOString().slice(0, 10)}.json"`);
            return reply.send(items);
        }
        catch (err) {
            console.error('[Library] Export failed:', err);
            return reply.code(500).send({ error: 'Export failed' });
        }
    });
    // POST /api/library/paths
    // Adds a new configured media directory to the SQLite database
    fastify.post('/api/library/paths', async (request, reply) => {
        const { path: folderPath, type } = request.body;
        if (!folderPath || !type) {
            return reply.code(400).send({ error: 'Parameters "path" and "type" are required' });
        }
        if (!['Movie', 'Show', 'Music'].includes(type)) {
            return reply.code(400).send({ error: 'Type must be one of: Movie, Show, Music' });
        }
        try {
            const id = 'path_' + crypto_1.default.randomBytes(8).toString('hex');
            database_1.default.prepare('INSERT INTO library_paths (id, path, type) VALUES (?, ?, ?)').run(id, folderPath, type);
            console.log(`[Library] Configured new library path: "${folderPath}" (${type})`);
            return reply.send({ success: true, id, path: folderPath, type });
        }
        catch (err) {
            if (err.message && err.message.includes('UNIQUE')) {
                return reply.code(409).send({ error: 'This folder path has already been added to your libraries' });
            }
            console.error('[Library] Failed to add path:', err);
            return reply.code(500).send({ error: 'Failed to save library path' });
        }
    });
    // DELETE /api/library/paths
    // Removes a configured media directory and deletes associated media items from DB (NOT physically)
    fastify.delete('/api/library/paths', async (request, reply) => {
        const { id } = request.body;
        if (!id) {
            return reply.code(400).send({ error: 'Parameter "id" is required to delete' });
        }
        try {
            // 1. Get the path and type
            const pathRecord = database_1.default.prepare('SELECT path, type FROM library_paths WHERE id = ?').all(id)[0];
            if (!pathRecord) {
                return reply.code(404).send({ error: 'Library path not found' });
            }
            const { path: folderPath, type } = pathRecord;
            // 2. Start transaction
            database_1.default.exec('BEGIN TRANSACTION;');
            // Delete from library_paths
            database_1.default.prepare('DELETE FROM library_paths WHERE id = ?').run(id);
            let deletedItemsCount = 0;
            if (type === 'Movie') {
                // Delete movies starting with this path
                const result = database_1.default.prepare("DELETE FROM media_items WHERE type = 'Movie' AND file_path LIKE ?").run(folderPath + '%');
                deletedItemsCount = result.changes;
            }
            else if (type === 'Show') {
                // Delete episodes starting with this path
                const result = database_1.default.prepare("DELETE FROM episodes WHERE file_path LIKE ?").run(folderPath + '%');
                deletedItemsCount = result.changes;
                // Clean up shows with no episodes remaining
                database_1.default.prepare("DELETE FROM media_items WHERE type = 'Show' AND id NOT IN (SELECT DISTINCT show_id FROM episodes)").run();
            }
            else if (type === 'Music') {
                // Delete music tracks starting with this path
                const result = database_1.default.prepare("DELETE FROM music_tracks WHERE file_path LIKE ?").run(folderPath + '%');
                deletedItemsCount = result.changes;
            }
            database_1.default.exec('COMMIT;');
            console.log(`[Library] Removed library path: "${folderPath}". Deleted ${deletedItemsCount} items from DB.`);
            return reply.send({
                success: true,
                message: 'Library path and associated items removed from database successfully!',
                deletedItemsCount
            });
        }
        catch (err) {
            try {
                database_1.default.exec('ROLLBACK;');
            }
            catch (e) { }
            console.error('[Library] Failed to delete path and associated items:', err);
            return reply.code(500).send({ error: 'Failed to delete library path and items' });
        }
    });
    // PUT /api/library/paths
    // Edits a configured library path and bulk-updates all matching media file paths in the DB
    fastify.put('/api/library/paths', async (request, reply) => {
        const { id, newPath } = request.body;
        if (!id || !newPath) {
            return reply.code(400).send({ error: 'Parameters "id" and "newPath" are required' });
        }
        try {
            const pathRecord = database_1.default.prepare('SELECT path, type FROM library_paths WHERE id = ?').all(id)[0];
            if (!pathRecord) {
                return reply.code(404).send({ error: 'Library path not found' });
            }
            const oldPath = pathRecord.path;
            database_1.default.exec('BEGIN TRANSACTION;');
            // 1. Update the library path
            database_1.default.prepare('UPDATE library_paths SET path = ? WHERE id = ?').run(newPath, id);
            // 2. Bulk update all media items, episodes, or music tracks
            let updatedCount = 0;
            const resultMovies = database_1.default.prepare(`
          UPDATE media_items 
          SET file_path = REPLACE(file_path, ?, ?) 
          WHERE file_path LIKE ?
        `).run(oldPath, newPath, oldPath + '%');
            updatedCount += resultMovies.changes;
            const resultEpisodes = database_1.default.prepare(`
          UPDATE episodes 
          SET file_path = REPLACE(file_path, ?, ?) 
          WHERE file_path LIKE ?
        `).run(oldPath, newPath, oldPath + '%');
            updatedCount += resultEpisodes.changes;
            const resultMusic = database_1.default.prepare(`
          UPDATE music_tracks 
          SET file_path = REPLACE(file_path, ?, ?) 
          WHERE file_path LIKE ?
        `).run(oldPath, newPath, oldPath + '%');
            updatedCount += resultMusic.changes;
            database_1.default.exec('COMMIT;');
            console.log(`[Library] Updated library path ID "${id}" from "${oldPath}" to "${newPath}". Modified ${updatedCount} file paths in DB.`);
            return reply.send({
                success: true,
                message: 'Library path and associated files updated successfully!',
                updatedCount
            });
        }
        catch (err) {
            try {
                database_1.default.exec('ROLLBACK;');
            }
            catch (e) { }
            console.error('[Library] Failed to update library path:', err);
            return reply.code(500).send({ error: 'Failed to update library path and items' });
        }
    });
}
// File watcher registry: path → fs.FSWatcher
const _watchers = new Map();
let _watchDebounce = null;
function setupFileWatchers() {
    // Close all existing watchers
    for (const [, watcher] of _watchers) {
        try {
            watcher.close();
        }
        catch (_) { }
    }
    _watchers.clear();
    try {
        const watchPaths = database_1.default.prepare("SELECT id, path, type FROM library_paths WHERE watch_for_changes = 1").all();
        for (const lp of watchPaths) {
            if (!fs.existsSync(lp.path))
                continue;
            try {
                const watcher = fs.watch(lp.path, { recursive: true }, (_event, filename) => {
                    if (!filename)
                        return;
                    const ext = filename.toString().split('.').pop()?.toLowerCase() || '';
                    if (!['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm'].includes(ext))
                        return;
                    if (_watchDebounce)
                        clearTimeout(_watchDebounce);
                    _watchDebounce = setTimeout(() => {
                        if (isScanning)
                            return;
                        console.log(`[Library] Change detected in watched folder: ${lp.path}`);
                        isScanning = true;
                        lastScanResult = null;
                        scanner_1.mediaScanner.scanLibrary(lp.path, lp.type)
                            .then(result => {
                            isScanning = false;
                            lastScanResult = { success: true, timestamp: new Date().toISOString(), itemsAdded: result.added, itemsUpdated: result.updated };
                            (0, notify_1.notifyScanComplete)(result.added, result.updated, lp.path).catch(() => { });
                            (0, rating_sync_1.syncAllExternalData)().catch(() => { });
                        })
                            .catch(err => {
                            isScanning = false;
                            lastScanResult = { success: false, timestamp: new Date().toISOString(), error: err.message };
                        });
                    }, 5000);
                });
                _watchers.set(lp.path, watcher);
                console.log(`[Library] Watching for changes: ${lp.path}`);
            }
            catch (watchErr) {
                console.error(`[Library] Failed to watch path ${lp.path}:`, watchErr);
            }
        }
    }
    catch (err) {
        console.error('[Library] setupFileWatchers failed:', err);
    }
}

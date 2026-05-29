import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import { mediaScanner } from '../services/scanner';
import { exec } from 'child_process';
import db from '../config/database';
import crypto from 'crypto';

interface ScanBody {
  path?: string;
  type?: 'Movie' | 'Show' | 'Music';
  preferLocalNfo?: boolean;
}

let isScanning = false;
let lastScanResult: any = null;

export default async function libraryRoutes(fastify: FastifyInstance) {
  
  // POST /api/library/scan
  // Triggers media directory scanning in the background
  fastify.post(
    '/api/library/scan',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Authentication required' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: ScanBody }>, reply: FastifyReply) => {
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
      
      mediaScanner.scanLibrary(scanPath, type, localNfoPref)
        .then((result) => {
          isScanning = false;
          lastScanResult = {
            success: true,
            timestamp: new Date().toISOString(),
            itemsAdded: result.added,
            itemsUpdated: result.updated
          };
          console.log(`[Library] Background scan finished successfully. Added: ${result.added}, Updated: ${result.updated}`);
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
    }
  );

  // GET /api/library/status
  // Returns current scanner state
  fastify.get(
    '/api/library/status',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Authentication required' });
        }
      }]
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      return reply.send({
        isScanning,
        lastScanResult
      });
    }
  );

  // GET /api/library/browse-native
  // Pops up a 100% native Windows Folder Browser Dialog on the host server
  fastify.get(
    '/api/library/browse-native',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Authentication required' });
        }
      }]
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
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
        
        exec(`powershell -NoProfile -STA -Command "${psScript}"`, (error, stdout, stderr) => {
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
    }
  );

  // GET /api/library/paths
  // Retrieves all configured media library scan paths
  fastify.get(
    '/api/library/paths',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Access token required' });
        }
      }]
    },
    async (request: FastifyRequest, reply: FastifyReply) => {
      try {
        const paths = db.prepare('SELECT * FROM library_paths ORDER BY added_at ASC').all();
        return reply.send(paths);
      } catch (err) {
        console.error('[Library] Failed to retrieve paths:', err);
        return reply.code(500).send({ error: 'Failed to retrieve library paths' });
      }
    }
  );

  // POST /api/library/paths
  // Adds a new configured media directory to the SQLite database
  fastify.post(
    '/api/library/paths',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Access token required' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: { path?: string; type?: string } }>, reply: FastifyReply) => {
      const { path: folderPath, type } = request.body;

      if (!folderPath || !type) {
        return reply.code(400).send({ error: 'Parameters "path" and "type" are required' });
      }

      if (!['Movie', 'Show', 'Music'].includes(type)) {
        return reply.code(400).send({ error: 'Type must be one of: Movie, Show, Music' });
      }

      try {
        const id = 'path_' + crypto.randomBytes(8).toString('hex');
        db.prepare('INSERT INTO library_paths (id, path, type) VALUES (?, ?, ?)').run(id, folderPath, type);
        console.log(`[Library] Configured new library path: "${folderPath}" (${type})`);
        return reply.send({ success: true, id, path: folderPath, type });
      } catch (err: any) {
        if (err.message && err.message.includes('UNIQUE')) {
          return reply.code(409).send({ error: 'This folder path has already been added to your libraries' });
        }
        console.error('[Library] Failed to add path:', err);
        return reply.code(500).send({ error: 'Failed to save library path' });
      }
    }
  );

  // DELETE /api/library/paths
  // Removes a configured media directory and deletes associated media items from DB (NOT physically)
  fastify.delete(
    '/api/library/paths',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Access token required' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: { id?: string } }>, reply: FastifyReply) => {
      const { id } = request.body;

      if (!id) {
        return reply.code(400).send({ error: 'Parameter "id" is required to delete' });
      }

      try {
        // 1. Get the path and type
        const pathRecord = db.prepare('SELECT path, type FROM library_paths WHERE id = ?').all(id)[0] as { path: string; type: string } | undefined;

        if (!pathRecord) {
          return reply.code(404).send({ error: 'Library path not found' });
        }

        const { path: folderPath, type } = pathRecord;

        // 2. Start transaction
        db.exec('BEGIN TRANSACTION;');

        // Delete from library_paths
        db.prepare('DELETE FROM library_paths WHERE id = ?').run(id);

        let deletedItemsCount = 0;

        if (type === 'Movie') {
          // Delete movies starting with this path
          const result = db.prepare("DELETE FROM media_items WHERE type = 'Movie' AND file_path LIKE ?").run(folderPath + '%');
          deletedItemsCount = result.changes;
        } else if (type === 'Show') {
          // Delete episodes starting with this path
          const result = db.prepare("DELETE FROM episodes WHERE file_path LIKE ?").run(folderPath + '%');
          deletedItemsCount = result.changes;

          // Clean up shows with no episodes remaining
          db.prepare("DELETE FROM media_items WHERE type = 'Show' AND id NOT IN (SELECT DISTINCT show_id FROM episodes)").run();
        } else if (type === 'Music') {
          // Delete music tracks starting with this path
          const result = db.prepare("DELETE FROM music_tracks WHERE file_path LIKE ?").run(folderPath + '%');
          deletedItemsCount = result.changes;
        }

        db.exec('COMMIT;');

        console.log(`[Library] Removed library path: "${folderPath}". Deleted ${deletedItemsCount} items from DB.`);
        return reply.send({ 
          success: true, 
          message: 'Library path and associated items removed from database successfully!',
          deletedItemsCount
        });
      } catch (err) {
        try { db.exec('ROLLBACK;'); } catch(e){}
        console.error('[Library] Failed to delete path and associated items:', err);
        return reply.code(500).send({ error: 'Failed to delete library path and items' });
      }
    }
  );

  // PUT /api/library/paths
  // Edits a configured library path and bulk-updates all matching media file paths in the DB
  fastify.put(
    '/api/library/paths',
    {
      preValidation: [async (request, reply) => {
        try {
          await request.jwtVerify();
        } catch (err) {
          reply.code(401).send({ error: 'Unauthorized: Access token required' });
        }
      }]
    },
    async (request: FastifyRequest<{ Body: { id?: string; newPath?: string } }>, reply: FastifyReply) => {
      const { id, newPath } = request.body;

      if (!id || !newPath) {
        return reply.code(400).send({ error: 'Parameters "id" and "newPath" are required' });
      }

      try {
        const pathRecord = db.prepare('SELECT path, type FROM library_paths WHERE id = ?').all(id)[0] as { path: string; type: string } | undefined;

        if (!pathRecord) {
          return reply.code(404).send({ error: 'Library path not found' });
        }

        const oldPath = pathRecord.path;

        db.exec('BEGIN TRANSACTION;');

        // 1. Update the library path
        db.prepare('UPDATE library_paths SET path = ? WHERE id = ?').run(newPath, id);

        // 2. Bulk update all media items, episodes, or music tracks
        let updatedCount = 0;
        
        const resultMovies = db.prepare(`
          UPDATE media_items 
          SET file_path = REPLACE(file_path, ?, ?) 
          WHERE file_path LIKE ?
        `).run(oldPath, newPath, oldPath + '%');
        updatedCount += resultMovies.changes;

        const resultEpisodes = db.prepare(`
          UPDATE episodes 
          SET file_path = REPLACE(file_path, ?, ?) 
          WHERE file_path LIKE ?
        `).run(oldPath, newPath, oldPath + '%');
        updatedCount += resultEpisodes.changes;

        const resultMusic = db.prepare(`
          UPDATE music_tracks 
          SET file_path = REPLACE(file_path, ?, ?) 
          WHERE file_path LIKE ?
        `).run(oldPath, newPath, oldPath + '%');
        updatedCount += resultMusic.changes;

        db.exec('COMMIT;');

        console.log(`[Library] Updated library path ID "${id}" from "${oldPath}" to "${newPath}". Modified ${updatedCount} file paths in DB.`);
        return reply.send({ 
          success: true, 
          message: 'Library path and associated files updated successfully!',
          updatedCount
        });
      } catch (err) {
        try { db.exec('ROLLBACK;'); } catch(e){}
        console.error('[Library] Failed to update library path:', err);
        return reply.code(500).send({ error: 'Failed to update library path and items' });
      }
    }
  );
}

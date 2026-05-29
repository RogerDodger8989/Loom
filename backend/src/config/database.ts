import { DatabaseSync } from 'node:sqlite';
import * as path from 'path';
import * as fs from 'fs';
import bcrypt from 'bcryptjs';

const configDir = path.resolve(__dirname, '../../../config');
if (!fs.existsSync(configDir)) {
  fs.mkdirSync(configDir, { recursive: true });
}

const dbPath = path.join(configDir, 'loom.db');
console.log(`[Database] Initializing native SQLite database at: ${dbPath}`);

const db = new DatabaseSync(dbPath);

// Enable WAL-mode (Write-Ahead Logging) and foreign keys using standard SQLite PRAGMAs
db.exec('PRAGMA journal_mode = WAL;');
db.exec('PRAGMA foreign_keys = ON;');

// Initialize database schema
db.exec(`
  -- Användare och säkerhet
  CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      role TEXT CHECK(role IN ('Admin', 'User')) NOT NULL
  );

  CREATE TABLE IF NOT EXISTS paired_devices (
      device_id TEXT PRIMARY KEY,
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      device_name TEXT,
      paired_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS user_restrictions (
      id TEXT PRIMARY KEY,
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      restriction_type TEXT CHECK(restriction_type IN ('GENRE', 'KEYWORD', 'RATING')),
      restriction_value TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS library_paths (
      id TEXT PRIMARY KEY,
      path TEXT UNIQUE NOT NULL,
      type TEXT CHECK(type IN ('Movie', 'Show', 'Music')) NOT NULL,
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  -- Mediekärna (Film & Serie)
  CREATE TABLE IF NOT EXISTS media_items (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      type TEXT CHECK(type IN ('Movie', 'Show')) NOT NULL,
      year INTEGER,
      plot TEXT,
      genre TEXT,
      poster_path TEXT,
      fanart_path TEXT,
      tmdb_id TEXT,
      imdb_id TEXT,
      file_path TEXT,
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
  

  CREATE TABLE IF NOT EXISTS episodes (
      id TEXT PRIMARY KEY,
      show_id TEXT REFERENCES media_items(id) ON DELETE CASCADE,
      season_number INTEGER NOT NULL,
      episode_number INTEGER NOT NULL,
      title TEXT,
      file_path TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS episode_markers (
      id TEXT PRIMARY KEY,
      episode_id TEXT REFERENCES episodes(id) ON DELETE CASCADE,
      marker_type TEXT CHECK(marker_type IN ('INTRO', 'OUTRO')),
      start_time_seconds INTEGER NOT NULL,
      end_time_seconds INTEGER NOT NULL
  );

  -- Metadata och Låsfunktion
  CREATE TABLE IF NOT EXISTS media_metadata (
      id TEXT PRIMARY KEY,
      media_item_id TEXT REFERENCES media_items(id) ON DELETE CASCADE,
      metadata_key TEXT NOT NULL,
      metadata_value TEXT,
      is_locked INTEGER CHECK(is_locked IN (0, 1)) DEFAULT 0,
      UNIQUE(media_item_id, metadata_key)
  );

  -- Visningshistorik & Fortsätt titta (Scrobbling)
  CREATE TABLE IF NOT EXISTS watch_history (
      id TEXT PRIMARY KEY,
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      media_item_id TEXT REFERENCES media_items(id) ON DELETE CASCADE,
      episode_id TEXT REFERENCES episodes(id) ON DELETE CASCADE,
      last_position_seconds INTEGER NOT NULL,
      total_duration_seconds INTEGER NOT NULL,
      is_watched INTEGER CHECK(is_watched IN (0, 1)) DEFAULT 0,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  -- Musikmodul
  CREATE TABLE IF NOT EXISTS music_tracks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      artist TEXT,
      album TEXT,
      file_path TEXT NOT NULL,
      track_number INTEGER,
      duration_seconds INTEGER
  );

  CREATE TABLE IF NOT EXISTS music_history (
      id TEXT PRIMARY KEY,
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      track_id TEXT REFERENCES music_tracks(id) ON DELETE CASCADE,
      listened_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  -- Globala systeminställningar (TMDB API Key etc)
  CREATE TABLE IF NOT EXISTS system_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
  );
`);

console.log('[Database] Database tables initialized successfully.');

// Seed a default admin user if the table is empty
function seedAdmin() {
  const usersCountRow = db.prepare('SELECT COUNT(*) as count FROM users').all()[0] as { count: number } | undefined;
  if (!usersCountRow || usersCountRow.count === 0) {
    const adminId = 'admin_default_id';
    const adminUsername = 'admin';
    const adminPassword = 'adminpassword';
    const salt = bcrypt.genSaltSync(10);
    const passwordHash = bcrypt.hashSync(adminPassword, salt);
    
    db.prepare(`
      INSERT INTO users (id, username, password_hash, role) 
      VALUES (?, ?, ?, 'Admin')
    `).run(adminId, adminUsername, passwordHash);
    
    console.log('----------------------------------------------------');
    console.log('[Database Seed] Default Admin User Created!');
    console.log(`Username: ${adminUsername}`);
    console.log(`Password: ${adminPassword}`);
    console.log('Please change this password after your first login.');
    console.log('----------------------------------------------------');
  }
}

seedAdmin();

// Handle ALTER TABLE errors safely by swallowing them if columns already exist
const columnsToAdd = [
  'year INTEGER',
  'plot TEXT',
  'genre TEXT',
  'poster_path TEXT',
  'fanart_path TEXT'
];

for (const col of columnsToAdd) {
  try {
    db.exec(`ALTER TABLE media_items ADD COLUMN ${col};`);
  } catch (e) {
    // Ignorera fel om kolumnen redan finns
  }
}

export default db;

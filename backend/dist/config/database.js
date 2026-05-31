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
const node_sqlite_1 = require("node:sqlite");
const path = __importStar(require("path"));
const fs = __importStar(require("fs"));
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const configDir = path.resolve(__dirname, '../../../config');
if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true });
}
const dbPath = path.join(configDir, 'loom.db');
console.log(`[Database] Initializing native SQLite database at: ${dbPath}`);
const db = new node_sqlite_1.DatabaseSync(dbPath);
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
      collection_name TEXT,
      collection_id TEXT,
      director TEXT,
      original_title TEXT,
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

  -- Watchlist för nedladdningar och bevakning
  CREATE TABLE IF NOT EXISTS watchlist (
      id TEXT PRIMARY KEY,
      tmdb_id TEXT UNIQUE NOT NULL,
      title TEXT NOT NULL,
      type TEXT CHECK(type IN ('Movie', 'Show')) NOT NULL,
      year INTEGER,
      poster_path TEXT,
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      status TEXT CHECK(status IN ('pending', 'requested', 'downloading', 'completed')) DEFAULT 'pending'
  );

  -- Synkad användarstatus för externa titlar (ej lokalt bibliotek)
  CREATE TABLE IF NOT EXISTS external_media_state (
      tmdb_id TEXT PRIMARY KEY,
      imdb_id TEXT,
      my_rating TEXT,
      watch_status TEXT CHECK(watch_status IN ('watched', 'unwatched')),
      source TEXT,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE INDEX IF NOT EXISTS idx_external_media_state_imdb_id ON external_media_state (imdb_id);
`);
console.log('[Database] Database tables initialized successfully.');
// Seed a default admin user if the table is empty
function seedAdmin() {
    const usersCountRow = db.prepare('SELECT COUNT(*) as count FROM users').all()[0];
    if (!usersCountRow || usersCountRow.count === 0) {
        const adminId = 'admin_default_id';
        const adminUsername = 'admin';
        const adminPassword = 'adminpassword';
        const salt = bcryptjs_1.default.genSaltSync(10);
        const passwordHash = bcryptjs_1.default.hashSync(adminPassword, salt);
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
    'fanart_path TEXT',
    'collection_name TEXT',
    'collection_id TEXT',
    'director TEXT',
    'original_title TEXT'
];
for (const col of columnsToAdd) {
    try {
        db.exec(`ALTER TABLE media_items ADD COLUMN ${col};`);
    }
    catch (e) {
        // Ignorera fel om kolumnen redan finns
    }
}
exports.default = db;

import { DatabaseSync } from 'node:sqlite';
import * as path from 'path';
import * as fs from 'fs';
import bcrypt from 'bcryptjs';

const isTest = process.env.NODE_ENV === 'test';

const configDir = path.resolve(__dirname, '../../../config');
if (!isTest && !fs.existsSync(configDir)) {
  fs.mkdirSync(configDir, { recursive: true });
}

const dbPath = process.env.DB_PATH ?? (isTest ? ':memory:' : path.join(configDir, 'loom.db'));
const restorePath = path.join(configDir, 'loom.db.restore');

// If a restore file exists, swap it in before opening (skip for in-memory/test)
if (!isTest && dbPath !== ':memory:' && fs.existsSync(restorePath)) {
  try {
    fs.copyFileSync(restorePath, dbPath);
    fs.unlinkSync(restorePath);
    console.log('[Database] Restored database from loom.db.restore');
  } catch (e) {
    console.error('[Database] Failed to apply restore file:', e);
  }
}

if (!isTest) console.log(`[Database] Initializing native SQLite database at: ${dbPath}`);
const db = new DatabaseSync(dbPath);

// Enable WAL-mode only for file-based databases (not supported in :memory:)
if (dbPath !== ':memory:') db.exec('PRAGMA journal_mode = WAL;');
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
      type TEXT CHECK(type IN ('Movie', 'Show', 'Music')) NOT NULL,
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
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      deleted_at DATETIME DEFAULT NULL
  );
  

  CREATE TABLE IF NOT EXISTS episodes (
      id TEXT PRIMARY KEY,
      show_id TEXT REFERENCES media_items(id) ON DELETE CASCADE,
      season_number INTEGER NOT NULL,
      episode_number INTEGER NOT NULL,
      title TEXT,
      file_path TEXT NOT NULL,
      air_date TEXT
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
  CREATE TABLE IF NOT EXISTS music_artists (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      musicbrainz_id TEXT,
      wikidata_id TEXT,
      bio TEXT,
      image_path TEXT,
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS music_albums (
      id TEXT PRIMARY KEY,
      artist_id TEXT REFERENCES music_artists(id) ON DELETE SET NULL,
      album_artist TEXT,
      title TEXT NOT NULL,
      year INTEGER,
      genre TEXT,
      cover_path TEXT,
      discart_path TEXT,
      musicbrainz_album_id TEXT,
      disc_count INTEGER DEFAULT 1,
      local_path TEXT,
      linked_media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE TABLE IF NOT EXISTS music_tracks (
      id TEXT PRIMARY KEY,
      album_id TEXT REFERENCES music_albums(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      artist TEXT,
      album TEXT,
      file_path TEXT NOT NULL UNIQUE,
      track_number INTEGER,
      disc_number INTEGER DEFAULT 1,
      duration_seconds INTEGER,
      codec TEXT,
      bit_depth INTEGER,
      sample_rate INTEGER,
      replay_gain REAL,
      musicbrainz_id TEXT,
      soundtrack_movie_id TEXT REFERENCES media_items(id) ON DELETE SET NULL
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

  -- Personliga användarinställningar (UI, Trakt, Simkl)
  CREATE TABLE IF NOT EXISTS user_settings (
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      key TEXT NOT NULL,
      value TEXT,
      PRIMARY KEY (user_id, key)
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
        tmdb_id TEXT NOT NULL,
        user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
        imdb_id TEXT,
        my_rating TEXT,
        watch_status TEXT CHECK(watch_status IN ('watched', 'unwatched')),
        source TEXT,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (tmdb_id, user_id)
    );

  CREATE INDEX IF NOT EXISTS idx_external_media_state_imdb_id ON external_media_state (imdb_id);

  -- Betyg per användare
  CREATE TABLE IF NOT EXISTS user_ratings (
      user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      media_item_id TEXT REFERENCES media_items(id) ON DELETE CASCADE,
      rating REAL NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (user_id, media_item_id)
  );

  -- Markörer för intro/outro/kapitel (stöder både filmer och avsnitt)
  CREATE TABLE IF NOT EXISTS media_markers (
      id TEXT PRIMARY KEY,
      media_item_id TEXT REFERENCES media_items(id) ON DELETE CASCADE,
      episode_id TEXT REFERENCES episodes(id) ON DELETE CASCADE,
      marker_type TEXT NOT NULL,
      start_time_seconds REAL NOT NULL,
      end_time_seconds REAL NOT NULL,
      title TEXT,
      source TEXT DEFAULT 'manual'
  );
  CREATE INDEX IF NOT EXISTS idx_media_markers_media_item ON media_markers(media_item_id);
  CREATE INDEX IF NOT EXISTS idx_media_markers_episode ON media_markers(episode_id);

  -- Ljudfingeravtryck för auto-intro-detektion (Goertzel-baserat)
  CREATE TABLE IF NOT EXISTS audio_fingerprints (
      id TEXT PRIMARY KEY,
      episode_id TEXT REFERENCES episodes(id) ON DELETE CASCADE,
      media_item_id TEXT REFERENCES media_items(id) ON DELETE CASCADE,
      fingerprint_data TEXT NOT NULL,
      duration_seconds REAL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
  CREATE INDEX IF NOT EXISTS idx_audio_fingerprints_episode ON audio_fingerprints(episode_id);
  CREATE INDEX IF NOT EXISTS idx_audio_fingerprints_show ON audio_fingerprints(media_item_id);
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
  'fanart_path TEXT',
  'collection_name TEXT',
  'collection_id TEXT',
  'director TEXT',
  'original_title TEXT',
  'deleted_at DATETIME DEFAULT NULL'
];

for (const col of columnsToAdd) {
  try {
    db.exec(`ALTER TABLE media_items ADD COLUMN ${col};`);
  } catch (e) {
    // Ignorera fel om kolumnen redan finns
  }
}

try {
  db.exec('ALTER TABLE episodes ADD COLUMN air_date TEXT;');
} catch (e) {
  // Ignorera om kolumnen redan finns
}

try {
  db.exec('ALTER TABLE episodes ADD COLUMN overview TEXT;');
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE episodes ADD COLUMN still_path TEXT;');
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE episodes ADD COLUMN deleted_at TEXT DEFAULT NULL;');
} catch (e) {
  // Ignorera om kolumnen redan finns
}

try {
  db.exec('ALTER TABLE media_items ADD COLUMN release_date TEXT;');
} catch (e) {
  // Ignorera om kolumnen redan finns
}

try {
  db.exec('ALTER TABLE library_paths ADD COLUMN watch_for_changes INTEGER DEFAULT 0;');
} catch (e) {
  // Ignorera om kolumnen redan finns
}

try {
  db.exec('ALTER TABLE users ADD COLUMN full_name TEXT DEFAULT NULL;');
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE users ADD COLUMN pin_hash TEXT DEFAULT NULL;');
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE users ADD COLUMN avatar_path TEXT DEFAULT NULL;');
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE users ADD COLUMN pin_plain TEXT DEFAULT NULL;');
} catch (e) { /* already exists */ }

try {
  db.exec("ALTER TABLE media_items ADD COLUMN delete_source TEXT DEFAULT 'manual';");
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE media_items ADD COLUMN delete_rule TEXT DEFAULT NULL;');
} catch (e) { /* already exists */ }

try {
  db.exec("ALTER TABLE episodes ADD COLUMN delete_source TEXT DEFAULT 'manual';");
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE episodes ADD COLUMN delete_rule TEXT DEFAULT NULL;');
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE media_items ADD COLUMN is_favorite INTEGER DEFAULT 0;');
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE media_items ADD COLUMN file_size INTEGER DEFAULT NULL;');
} catch (e) { /* already exists */ }

try {
  db.exec('ALTER TABLE watch_history ADD COLUMN play_count INTEGER DEFAULT 0;');
} catch (e) { /* already exists */ }

try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS play_history (
      id                TEXT PRIMARY KEY,
      user_id           TEXT REFERENCES users(id) ON DELETE CASCADE,
      media_item_id     TEXT REFERENCES media_items(id) ON DELETE CASCADE,
      episode_id        TEXT REFERENCES episodes(id) ON DELETE CASCADE,
      watched_at        TEXT NOT NULL,
      source            TEXT DEFAULT 'local',
      trakt_history_id  INTEGER UNIQUE
    );
    CREATE INDEX IF NOT EXISTS idx_play_history_media  ON play_history(media_item_id);
    CREATE INDEX IF NOT EXISTS idx_play_history_user   ON play_history(user_id, watched_at DESC);
  `);
} catch (e) { /* already exists */ }

// Music tracks column migrations
const musicTracksColumns = [
  'musicbrainz_id TEXT',
  'soundtrack_movie_id TEXT',
  'album_id TEXT',
  'disc_number INTEGER DEFAULT 1',
  'codec TEXT',
  'bit_depth INTEGER',
  'sample_rate INTEGER',
  'replay_gain REAL',
];
for (const col of musicTracksColumns) {
  try { db.exec(`ALTER TABLE music_tracks ADD COLUMN ${col};`); } catch (e) { /* already exists */ }
}

// Ensure music_albums and music_artists tables exist (idempotent)
try {
  db.exec(`
    CREATE TABLE IF NOT EXISTS music_artists (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, musicbrainz_id TEXT, wikidata_id TEXT,
      bio TEXT, image_path TEXT, added_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE IF NOT EXISTS music_albums (
      id TEXT PRIMARY KEY, artist_id TEXT, album_artist TEXT, title TEXT NOT NULL,
      year INTEGER, genre TEXT, cover_path TEXT, discart_path TEXT,
      musicbrainz_album_id TEXT, disc_count INTEGER DEFAULT 1, local_path TEXT,
      linked_media_id TEXT, added_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  `);
} catch (e) { /* already exists */ }

// Migrera media_items CHECK-villkor för type om 'Music' saknas
try {
  // Testa om Music är tillåtet genom att kontrollera om vi kan insertera (rollback direkt)
  db.exec('SAVEPOINT check_music_type;');
  try {
    db.exec("INSERT INTO media_items (id, title, type, file_path) VALUES ('_type_test_', '_test_', 'Music', '_test_');");
    db.exec('ROLLBACK TO SAVEPOINT check_music_type;');
  } catch (e) {
    // Music inte tillåtet – återskapa tabellen med korrekt CHECK
    db.exec('ROLLBACK TO SAVEPOINT check_music_type;');
    db.exec(`
      CREATE TABLE IF NOT EXISTS media_items_new (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          type TEXT CHECK(type IN ('Movie', 'Show', 'Music')) NOT NULL,
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
          added_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          deleted_at DATETIME DEFAULT NULL,
          release_date TEXT,
          delete_source TEXT DEFAULT 'manual',
          delete_rule TEXT DEFAULT NULL,
          is_favorite INTEGER DEFAULT 0,
          file_size INTEGER DEFAULT NULL
      );
      INSERT INTO media_items_new SELECT id, title, type, year, plot, genre, poster_path, fanart_path,
          tmdb_id, imdb_id, collection_name, collection_id, director, original_title, file_path,
          added_at, deleted_at,
          NULL, 'manual', NULL, 0, NULL
      FROM media_items;
      DROP TABLE media_items;
      ALTER TABLE media_items_new RENAME TO media_items;
    `);
    console.log('[Database] Migrerade media_items CHECK-villkor för att tillåta type=Music');
  }
  db.exec('RELEASE SAVEPOINT check_music_type;');
} catch (e) {
  console.error('[Database] Failed to migrate media_items type constraint:', e);
}

// Migrera external_media_state från (tmdb_id) till (tmdb_id, user_id)
try {
  // Check if we need to migrate
  const tableInfo = db.prepare("PRAGMA table_info(external_media_state)").all() as {name: string}[];
  const hasUserId = tableInfo.some(col => col.name === 'user_id');
  if (!hasUserId) {
    db.exec(`
      CREATE TABLE external_media_state_new (
          tmdb_id TEXT NOT NULL,
          user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
          imdb_id TEXT,
          my_rating TEXT,
          watch_status TEXT CHECK(watch_status IN ('watched', 'unwatched')),
          source TEXT,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (tmdb_id, user_id)
      );
    `);
    db.exec(`
      INSERT INTO external_media_state_new (tmdb_id, user_id, imdb_id, my_rating, watch_status, source, updated_at)
      SELECT tmdb_id, (SELECT id FROM users ORDER BY rowid LIMIT 1), imdb_id, my_rating, watch_status, source, updated_at 
      FROM external_media_state;
    `);
    db.exec(`DROP TABLE external_media_state;`);
    db.exec(`ALTER TABLE external_media_state_new RENAME TO external_media_state;`);
    db.exec(`CREATE INDEX IF NOT EXISTS idx_external_media_state_imdb_id ON external_media_state (imdb_id);`);
  }
} catch (e) {
  console.error('[Database] Failed to migrate external_media_state:', e);
}

export default db;

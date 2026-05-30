# HANDOFF.md — Loom: Status & Kontext för nästa AI/IDE

> **Skapad:** 2026-05-30  
> **Senast uppdaterad:** 2026-05-30  
> **Tidigare IDE:** Google Gemini / Antigravity  
> **Nästa IDE:** VS Code + GitHub Copilot

---

## Vad är Loom?

Loom är en **lokal, Plex-inspirerad mediaserver** med premium-UI. Användaren hostar den på sin egen server (Unraid/NAS) och når den via webb eller Android TV-app. Ingen molntjänst krävs.

**Arkitektur:** Fastify (Node/TS) backend + Flutter frontend (Web + Android TV). SQLite som databas.

---

## Aktuell körningsstatus

| Tjänst | Kommando | Port |
|---|---|---|
| Backend | `cd backend && npm run dev` | 8080 |
| Frontend webb | `cd frontend && flutter run -d web-server --web-port=50645` | 50645 |

> ⚠️ Frontend kör i `flutter run` (dev-läge med hot reload). Det finns INGEN separat build-steg som krävs för utveckling.

## Viktigaste läget just nu

- Awards visas fortfarande inte i UI, trots att backend nu försöker fylla metadata både via OMDb och TMDB:s publika awards-sida.
- Verifierad datarad: filmen `A Prophet` har `tmdb_id=21575` och `imdb_id=tt1235166`, men `media_metadata` saknade `awards` innan fallbacken lades till.
- Enda säkra settingsnyckeln som faktiskt fanns i databasen var `TMDB_API_KEY`; `OMDB_API_KEY` saknades.
- Backend bygger rent efter senaste ändringarna.

### Rekommenderat nästa steg för nästa IDE

1. Öppna en riktig media-detalj i appen och kontrollera API-responsen från `GET /api/media/items/:id`.
2. Verifiera om `metadata.awards` nu sparas i SQLite efter att detaljsidan har öppnats eller efter en ny scan.
3. Om metadata finns men UI ändå är tomt, felsök `frontend/lib/screens/media_details_screen.dart` och hur awards parse:as/renderas.
4. Om metadata fortfarande saknas, kontrollera att TMDB awards-sidan verkligen hämtas i runtime från backend-processen och att ingen request blockeras.

---

## Vad som är implementerat ✅

### Backend (`backend/src/`)

#### Autentisering (`routes/auth.ts`)
- [x] PIN-parningssystem: `POST /api/auth/pair/request` → `GET /api/auth/pair/status` → `POST /api/auth/pair/confirm`
- [x] JWT-baserad autentisering för alla skyddade endpoints
- [x] Enhets-ID sparas i `localStorage` (frontend)

#### Media (`routes/media.ts`)
- [x] `GET /api/media/items` — lista alla mediafiler (med metadata)
- [x] `GET /api/media/items/:id` — hämta en films fullständiga data + all metadata
- [x] `POST /api/media/items/:id/seen` — markera som sedd/osedd
- [x] `POST /api/media/items/:id/rating` — sätt betyg (0–10)
- [x] `POST /api/media/items/:id/match` — manuell TMDB-omlänkning
- [x] `GET /api/media/search-tmdb?q=...&year=...` — TMDB-sökning
- [x] `POST /api/playlists` — skapa ny spellista (SQLite)
- [x] `POST /api/playlists/:id/items` — lägg till film i spellista

#### Inställningar (`routes/settings.ts`)
- [x] `GET/POST /api/settings` — nyckel-värde-inställningar (TMDB_API_KEY, OMDB_API_KEY etc.)

#### Scanner (`services/scanner.ts`)
- [x] Biblioteksskanning via `POST /api/scan/trigger`
- [x] NFO-filparsning (local metadata)
- [x] TMDB-metadatahämtning (poster, backdrop, cast, genres, collection)
- [x] OMDb-integration för priser (Oscars, Globes, BAFTA)
- [x] TMDB awards fallback via publika `/movie/:id/awards`-sidan när OMDb saknas
- [x] Trailer-URL sparas från TMDB (`watch/providers`, `videos`)
- [x] Skanningsprogress via WebSocket/SSE

#### Uppspelning (`routes/playback.ts`)
- [x] `GET /api/stream/:id` — direktuppspelning (HTTP range requests)
- [x] `POST /api/playback/progress` — spara uppspelningsframsteg (progress_position i sekunder)

---

### Frontend (`frontend/lib/`)

#### Skärmar

##### `dashboard_screen.dart` — Huvud-navigeringsskärm
- [x] Collapsible sidebar med 5 tabbar:
  - Tab 0: **Hem** (`_buildHomeView`) — "Fortsätt titta" + "Nyligen tillagda"
  - Tab 1: **Movies** (`_buildMoviesView`) — grid med filmkort
  - Tab 2: **TV Shows** (`_buildShowsView`)
  - Tab 3: **Library Scanner** (`_buildScannerView`) — mapphantering + skanningsprogress
  - Tab 4: **Settings** (`_buildSettingsView`) — API-nycklar, enhetsinställningar
- [x] **Loom-logotyp** klickbar → navigerar till Hem (tab 0)
- [x] **"Tillbaka"-knapp** i sidebar när `_selectedMediaId != null`
- [x] Genrefilter-chips ovanför filmgrid
- [x] Sökruta i header
- [x] Scanningsprogress-indikator (LinearProgressIndicator) under mappar
- [x] Mörkt tema, glassmorfism, lila accentfärg (`#8A5BFF`)

##### `media_details_screen.dart` — Filmdetaljvy
- [x] **Bakgrundsbild (Fanart)** med gradient-fade nedåt
- [x] **Poster** vänster med hover-play-ikon (döljs utan hover)
- [x] **"Spela"-knapp** byter namn till **"Återuppta"** om `playback_progress > 0`
- [x] **Resume Playback Modal** vid klick om film är påbörjad
- [x] **Titel (YEAR)** format
- [x] **Collection-badge** (t.ex. "Batman Collection") under år/rating-raden
- [x] **Genres** som klickbara chips (filtrerar filmgrid)
- [x] **Kvalitetsbadges** (4K, 1080p, 5.1, DTS, HDR, Atmos) parsat från filnamn
- [x] **Prisbadges** (Oscars, Golden Globes, BAFTA) parsade från OMDb-data
- [ ] **Awards-priser/nomineringar i UI** är fortfarande under felsökning; backend-fallback finns men de visas inte än
- [x] **Watch Providers** (streaming-tjänster) som loggor
- [x] **Trailer-knapp** (öppnar YouTube)
- [x] **Mitt Betyg-slider** (0–10) synkar med backend
- [x] **Betygsrader** (TMDB, IMDb, Simkl) klickbara → öppnar respektive sida i ny flik
- [x] **Kompakt ljud/undertext-rad** (DropdownButton i en rad med ikon-avgränsare)
- [x] **Skådespelar-karusell** (klickbar → PersonDetailsScreen)
- [x] **Studio-loggor-rad**
- [x] **"..." (kebab-meny)** med alternativ:
  - Fixa matchning (öppnar `_FixMatchDialog`)
  - Markera sedd/osedd
  - Se i filutforskaren
- [x] **"Sedd"-knapp** med hög-kontrast cirkulär bakgrund
- [x] **Spellistor-knapp** → öppnar `_PlaylistDialog` (skapa & lägg till)
- [x] **`_FixMatchDialog`** — sök TMDB + välj rätt film, med lila "Sök"-knapp

##### `person_details_screen.dart`
- [x] Skådespelarens bio, bild, filmografi

##### `pairing_screen.dart`
- [x] PIN-parningsgränssnitt

##### `resume_playback_modal.dart`
- [x] Modal: "Fortsätt från X" eller "Börja om"

#### `services/api.dart`
- [x] Alla API-anrop wrappade i `ApiService`-klass
- [x] JWT-autentisering i header
- [x] `createPlaylistAndAddItem(name, mediaItemId)` — skapar spellista + lägger till film

---

## Vad som SAKNAS / Återstår 🔲

### Hög prioritet (användaren har bett om detta)

- [ ] **Riktiga IMDb-betyg** — idag visas "7.8 / 10" som hårdkodat exempelvärde. Behöver hämtas via OMDb API (`i=tt1234567&r=json`) och cachas i `media_metadata`.
- [ ] **Riktiga Simkl-betyg** — Simkl API (gratis, kräver API-nyckel) eller scraping.
- [ ] **Periodisk ratings-refresh** — bakgrundsjobb (t.ex. var 24h) för att uppdatera TMDB/IMDb-betyg.
- [ ] **Faktiska undertextspår från videofil** — idag visas hårdkodade "Swedish (SRT)" etc. Behöver köra `ffprobe` på filen och returnera verkliga spår.
- [ ] **Faktiska ljudspår från videofil** — samma som undertitlar, behöver `ffprobe`-integration.
- [ ] **Uppspelning i Flutter Web** — `GET /api/stream/:id` finns men inget videoelement i UI ännu.

### Medium prioritet

- [ ] **TV-serier-vy** — `_buildShowsView` existerar men saknar seasons/episodes-struktur.
- [ ] **Musikmodul** — enligt PROJECT_VISION.md, ej påbörjad.
- [ ] **Fotoalbum-modul** — enligt PROJECT_VISION.md, ej påbörjad.
- [ ] **Radarr/Sonarr-integration** — "Ta hem"-funktion och kalendervy.
- [ ] **Simkl/Trakt-synk** — tvåvägssynk av visningshistorik.
- [ ] **Intro/Outro-skipping** — `EPISODE_MARKERS`-tabell existerar ej än.
- [ ] **Offgrid import/export** — CSV/JSON-import från IMDb/Trakt.
- [ ] **Innehållsfiltrering per användare** — genre/åldersrestriktioner.
- [ ] **Docker-konfiguration** — Dockerfile + docker-compose för Unraid.

### Låg prioritet / Nice-to-have

- [ ] **Multi-version-stöd** — samma film i 4K + 1080p grupperade.
- [ ] **OpenSubtitles/Bazarr-integration** — auto-nedladdning av undertexter.
- [ ] **MusicBrainz/Last.fm** — musikmetadata.
- [ ] **Sharp-miniatyrer** — automatisk bildresizing för foton.
- [ ] **Android TV D-pad-navigering** — fokushantering för fjärrkontroll.

---

## Kända buggar / Teknisk skuld

| # | Beskrivning | Fil | Allvar |
|---|---|---|---|
| 1 | `withOpacity()` deprecated — bör ersättas med `.withValues(alpha:)` | Alla Flutter-filer | Info |
| 2 | `dart:html` används (ej WASM-kompatibelt) — kräver `package:web` för WASM-build | `api.dart`, `media_details_screen.dart` | Info |
| 3 | IMDb/Simkl-betyg är hårdkodade mock-värden | `media_details_screen.dart` L~691 | Hög |
| 4 | Ljud- och undertextspår är hårdkodade | `media_details_screen.dart` L~633 | Hög |
| 5 | `_scanStatusText` och `_lastScanResult` i dashboard är deklarerade men oanvända | `dashboard_screen.dart` L33-34 | Varning |
| 6 | Playlist-tabeller skapas inline i route-handlern — bör migreras till `database.ts` | `media.ts` L~500+ | Medium |

---

## Databasschema (SQLite)

### Befintliga tabeller

```sql
-- Mediafiler
CREATE TABLE media_items (
  id TEXT PRIMARY KEY,
  title TEXT,
  year INTEGER,
  file_path TEXT,
  tmdb_id TEXT,
  imdb_id TEXT,
  type TEXT DEFAULT 'movie',  -- 'movie' | 'show' | 'music'
  is_seen INTEGER DEFAULT 0,
  user_rating REAL,
  added_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Nyckel-värde metadata (länkad till media_items)
CREATE TABLE media_metadata (
  id TEXT PRIMARY KEY,
  media_item_id TEXT REFERENCES media_items(id),
  key TEXT,
  value TEXT,
  UNIQUE(media_item_id, key)
);
-- Vanliga nycklar: poster_path, backdrop_path, overview, tagline,
--   runtime, release_date, genres, cast, directors, studios,
--   collection_name, collection_id, tmdb_rating, trailer_url,
--   watch_providers, awards, age_rating, resolution,
--   playback_progress, last_watched_at, logo_path

-- Inställningar
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT
);
-- Vanliga nycklar: TMDB_API_KEY, OMDB_API_KEY, JWT_SECRET, library_paths

> OBS: Den faktiska databasen som används i workspace ligger i `config/loom.db` i rotmappen, inte under `backend/config`.

-- Enheter (parkopplade)
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT,
  user_id TEXT,
  paired_at DATETIME
);

-- Spellistor (skapas on-demand)
CREATE TABLE playlists (
  id TEXT PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE playlist_items (
  id TEXT PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  media_item_id TEXT NOT NULL,
  added_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

---

## Miljövariabler

Skapa `backend/.env`:

```env
TMDB_API_KEY=<din TMDB v3 API-nyckel>
OMDB_API_KEY=<din OMDb API-nyckel>   # Gratis på omdbapi.com
JWT_SECRET=<lång slumpmässig sträng>
PORT=8080
```

---

## Designsystem (Flutter)

| Token | Värde |
|---|---|
| Primär accent | `Color(0xFF8A5BFF)` (lila) |
| Bakgrund | `Color(0xFF0A0617)` |
| Kortbakgrund | `Color(0xFF0F0B1E)` |
| Text primär | `Colors.white` |
| Text sekundär | `Colors.white54` / `Colors.white38` |
| Border | `Colors.white.withValues(alpha: 0.06)` |
| Font | System default (överväg att lägga till Google Fonts: Inter/Outfit) |
| Borderradius standard | `12px` / `16px` / `24px` |

---

## Viktiga mönster att känna till

### Metadata-läsning i Flutter
All metadata för en film returneras som en flattad `Map<String, dynamic>` där varje nyckel är ett strängnamn:

```dart
final meta = _mediaData?['metadata'] as Map<String, dynamic>? ?? {};
final posterPath = meta['poster_path'];
final genres = jsonDecode(meta['genres'] ?? '[]') as List;
final cast = jsonDecode(meta['cast'] ?? '[]') as List;
```

### State management
Inget state management-bibliotek används (ingen Riverpod/Bloc). All state hanteras med `setState()` i respektive `StatefulWidget`. Vid behov av globalt state, börja med `InheritedWidget` eller `Provider`.

### API-anrop
```dart
// Alltid via ApiService-instansen som skickas som widget-parameter
final data = await widget.apiService.getMediaItem(widget.mediaId);
```

---

## Projektets vision (kort)

Se `PROJECT_VISION.md` för fullständig vision. Sammanfattat:

- Plex-liknande upplevelse, men 100 % lokal och öppen
- Samma app på webb + Android TV (Flutter)
- Inga molnkonton krävs
- Stöd för Radarr/Sonarr-integration
- Historisk interaktiv kalender
- Musikmodul + Fotoalbum på sikt

---

*Denna fil ska hållas uppdaterad när ny funktionalitet läggs till eller buggar åtgärdas.*

# Loom 🎬

**En Plex-inspirerad, lokalt hostad mediaserver med premium UI.** Hanterar film, TV-serier, musik och foton — helt offgrid, inget moln behövs.

---

## Snabbstart

### Krav
- Node.js 18+
- Flutter 3.x (för frontend)
- FFmpeg (valfritt, för transkodning)

### Starta backend
```bash
cd backend
npm install
npm run dev          # Startar på http://localhost:8080
```

### Starta frontend (webb)
```bash
cd frontend
flutter pub get
flutter run -d web-server --web-port=50645
# Öppna http://localhost:50645
```

## Senaste status

Media-detaljsidan har redan stöd för tagline, cast, keywords, production companies, trailer, Similar och betyg. Awards/nomineringar är fortfarande under felsökning: backend har nu både OMDb- och TMDB-baserad fallback, men vissa titlar visar fortfarande inget i UI.

Om du tar över arbetet, börja i [HANDOFF.md](HANDOFF.md) och kontrollera först om `metadata.awards` faktiskt finns i `config/loom.db` efter att en film öppnats eller skannats om.

### Starta frontend (Android TV)
```bash
cd frontend
flutter run -d <android-device-id>
```

---

## Teknikstack

| Lager | Teknologi |
|---|---|
| **Backend** | Node.js + TypeScript + Fastify |
| **Databas** | SQLite (WAL-mode), fil: `backend/config/loom.db` |
| **Databas** | SQLite (WAL-mode), fil: `config/loom.db` i workspace-roten |
| **Frontend** | Flutter (Web + Android TV, gemensam kodbas) |
| **Metadata** | TMDB API + OMDb API + TMDB awards-sidan som fallback |
| **Streaming** | FFmpeg (direct play + HLS transkodning) |
| **Autentisering** | JWT + PIN-parningssystem |

---

## Projektstruktur

```
Loom/
├── backend/
│   ├── src/
│   │   ├── index.ts              # Fastify-server, plugin-registrering
│   │   ├── config/
│   │   │   └── database.ts       # SQLite-anslutning (better-sqlite3)
│   │   ├── routes/
│   │   │   ├── media.ts          # GET/POST /api/media/*, /api/playlists
│   │   │   ├── settings.ts       # GET/POST /api/settings
│   │   │   ├── auth.ts           # POST /api/auth/pair/*
│   │   │   └── playback.ts       # POST /api/playback/progress, /stream
│   │   └── services/
│   │       ├── scanner.ts        # Biblioteksskanning, NFO-parsing
│   │       └── tmdb.ts           # TMDB API-wrapper
│   └── package.json
├── frontend/
│   ├── lib/
│   │   ├── main.dart             # Startpunkt, MaterialApp
│   │   ├── screens/
│   │   │   ├── dashboard_screen.dart      # Huvudvy med sidebar + TabBarView
│   │   │   ├── media_details_screen.dart  # Filmdetaljer, skådespelare, betyg
│   │   │   ├── person_details_screen.dart # Skådespelarinfo
│   │   │   ├── pairing_screen.dart        # PIN-parning
│   │   │   └── resume_playback_modal.dart # "Fortsätt titta?"-modal
│   │   └── services/
│   │       └── api.dart          # HTTP-wrapper mot backend
│   └── pubspec.yaml
├── README.md                     # ← Du är här
├── HANDOFF.md                    # Detaljerad handover till nästa IDE/AI
└── PROJECT_VISION.md             # Fullständig produktvision (läs denna!)
```

---

## API-översikt (Backend)

### Media
| Metod | Endpoint | Beskrivning |
|---|---|---|
| `GET` | `/api/media/items` | Hämta alla mediafiler |
| `GET` | `/api/media/items/:id` | Hämta en films fullständiga data + metadata |
| `POST` | `/api/media/items/:id/seen` | Markera som sedd/osedd |
| `POST` | `/api/media/items/:id/rating` | Sätt betyg (0–10) |
| `POST` | `/api/media/items/:id/match` | Länka om till annat TMDB-ID |
| `GET` | `/api/media/search-tmdb` | Sök kandidater på TMDB |

### Spellista
| Metod | Endpoint | Beskrivning |
|---|---|---|
| `POST` | `/api/playlists` | Skapa ny spellista |
| `POST` | `/api/playlists/:id/items` | Lägg till film i spellista |

### Uppspelning & Progress
| Metod | Endpoint | Beskrivning |
|---|---|---|
| `GET` | `/api/stream/:id` | Starta direktuppspelning |
| `POST` | `/api/playback/progress` | Spara uppspelningsframsteg |

### Autentisering
| Metod | Endpoint | Beskrivning |
|---|---|---|
| `POST` | `/api/auth/pair/request` | Begär PIN-kod |
| `GET` | `/api/auth/pair/status` | Kontrollera parkopplingsstatus |
| `POST` | `/api/auth/pair/confirm` | Admin bekräftar parning |

### Inställningar
| Metod | Endpoint | Beskrivning |
|---|---|---|
| `GET` | `/api/settings` | Hämta alla inställningar |
| `POST` | `/api/settings` | Uppdatera inställningar |
| `POST` | `/api/scan/trigger` | Starta biblioteksskanning |

---

## Databasskiss (SQLite)

### `media_items`
| Kolumn | Typ | Beskrivning |
|---|---|---|
| `id` | TEXT PK | UUID |
| `title` | TEXT | Filmtitel |
| `year` | INTEGER | Utgivningsår |
| `file_path` | TEXT | Absolut sökväg till videofil |
| `tmdb_id` | TEXT | Länk till TMDB |
| `imdb_id` | TEXT | Länk till IMDb |
| `type` | TEXT | `movie` / `show` / `music` |
| `is_seen` | INTEGER | 0/1 |
| `user_rating` | REAL | 0–10 |
| `added_at` | DATETIME | Inlagd i biblioteket |

### `media_metadata`
Nyckel-värde-tabell länkad via `media_item_id`:
- `poster_path`, `backdrop_path`, `logo_path`
- `overview`, `tagline`, `runtime`, `release_date`
- `genres`, `cast`, `directors`, `studios`, `collection_name`
- `tmdb_rating`, `trailer_url`, `watch_providers`
- `awards` (OMDb), `age_rating`, `resolution`
- `playback_progress`, `last_watched_at`

### `playlists` & `playlist_items`
Skapade on-demand via `/api/playlists`-endpointerna.

---

## Miljövariabler (backend/.env)

```env
TMDB_API_KEY=din_nyckel_här
OMDB_API_KEY=din_nyckel_här   # För priser (Oscars etc.)
PORT=8080
JWT_SECRET=din_hemliga_nyckel
```

## För nästa IDE

1. Verifiera awards genom att läsa `GET /api/media/items/:id` för en titel som `A Prophet`.
2. Om `metadata.awards` finns men UI är tomt, felsök `frontend/lib/screens/media_details_screen.dart`.
3. Om metadata saknas, kontrollera runtime-hämtningen i `backend/src/routes/media.ts` och `backend/src/services/scanner.ts`.

---

## Viktiga designprinciper

1. **Headless API-first** — All logik i backend, frontend är tunna vyer.
2. **Offgrid-first** — Fungerar utan internet efter initial metadatahämtning.
3. **SQLite WAL** — Enkelt att backa upp, hög lokal prestanda.
4. **Flutter cross-platform** — Samma kod → Webb + Android TV.
5. **TMDB som primär källa** — OMDb som komplement (priser).

---

## Kända begränsningar / TODO

Se `HANDOFF.md` för fullständig lista på vad som är implementerat och vad som återstår.

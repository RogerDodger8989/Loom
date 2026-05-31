# Loom 🎬

**En Loom-inspirerad, lokalt hostad mediaserver med premium UI.** Hanterar film, TV-serier, musik och foton — helt offgrid, inget moln behövs.

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

Loom har nu fullt stöd för **premium OAuth-anslutning av Trakt.tv och Simkl** samt **äkta tvåvägs watched-status (sedd-status) synk**! 

### Watched-status Synkronisering (Trakt & Simkl)
När dina konton har parats via inställningarna synkas din "sedd"-historik automatiskt:
* **Befintligt bibliotek:** Varje gång servern startar hämtas historiken i bakgrunden och uppdaterar databasen. Likaså när du precis har parat ett nytt konto via OAuth.
* **Nytt media:** Så fort ny film eller media läggs till och skannas in av biblioteksskannern, görs en direktkontroll mot dina externa konton så att historiken matchas på en gång.
* **Tvåvägssynk:** När du tittar klart på en film i Loom synkas detta omedelbart upp till Trakt och Simkl.
* **Visualisering i UI:** I hemskärmen och filmvyn visas en snygg, lysande neongrön bock i övre vänstra hörnet på postern. I detaljvyn visas en premium grön `"Sedd"`-badge under cover-bilden (vilken dynamiskt ersätts med den lila progress-baren om du börjar se om filmen).

Vid lyckad OAuth-koppling startar även ett bakgrundsjobb som hämtar och importerar **hela användarens historiska betygshistorik** från Trakt/Simkl direkt in i Loom. Nya betyg som sätts i Loom synkas ut i realtid till Trakt, Simkl och TMDB automatiskt!

Om du tar över arbetet, börja i [HANDOFF.md](HANDOFF.md) för full status.

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
| **Databas** | SQLite (WAL-mode), fil: `config/loom.db` i workspace-roten |
| **Frontend** | Flutter (Web + Android TV, gemensam kodbas) |
| **Metadata** | TMDB API + OMDb API + TMDB awards-sidan som fallback (Svenska streamingtjänster hämtas automatiskt via region: SE) |
| **Synkning** | Äkta tvåvägs ratings-synk via OAuth (Trakt & Simkl) i realtid |
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
│   │   │   ├── oauth.ts          # OAuth authorize & callback för Trakt & Simkl
│   │   │   └── playback.ts       # POST /api/playback/progress, /stream
│   │   └── services/
│   │       ├── scanner.ts        # Biblioteksskanning, NFO-parsing
│   │       ├── tmdb.ts           # TMDB API-wrapper
│   │       └── rating_sync.ts    # Envägs & tvåvägs ratings-synk och import
│   └── package.json
├── frontend/
│   ├── lib/
│   │   ├── main.dart             # Startpunkt, MaterialApp
│   │   ├── screens/
│   │   │   ├── dashboard_screen.dart      # Huvudvy med sidebar, API-fält, OAuth
│   │   │   ├── media_details_screen.dart  # Filmdetaljer, skådespelare, betyg-slider
│   │   │   ├── person_details_screen.dart # Skådespelarinfo
│   │   │   ├── pairing_screen.dart        # PIN-parning
│   │   │   └── resume_playback_modal.dart # "Fortsätt titta?"-modal
│   │   └── services/
│   │       └── api.dart          # HTTP-wrapper mot backend (WASM-kompatibel)
│   └── pubspec.yaml
├── README.md                     # ← Du är här
├── HANDOFF.md                    # Detaljerad handover till nästa IDE/AI
└── PROJECT_VISION.md             # Fullständig produktvision (läs denna!)
```

---

## API-översikt (Backend)

### Media & Ratings
| Metod | Endpoint | Beskrivning |
|---|---|---|
| `GET` | `/api/media/items` | Hämta alla mediafiler |
| `GET` | `/api/media/items/:id` | Hämta en films fullständiga data + metadata |
| `POST` | `/api/media/items/:id/seen` | Markera som sedd/osedd |
| `POST` | `/api/media/items/:id/metadata` | Spara metadata / betyg (0–10) |
| `POST` | `/api/media/items/:id/match` | Länka om till annat TMDB-ID |
| `GET` | `/api/media/search-tmdb` | Sök kandidater på TMDB |

### OAuth Synk
| Metod | Endpoint | Beskrivning |
|---|---|---|
| `GET` | `/api/oauth/trakt/authorize` | Initiera Trakt OAuth-flöde |
| `GET` | `/api/oauth/trakt/callback` | Callback för Trakt (sparar token & startar import) |
| `GET` | `/api/oauth/simkl/authorize` | Initiera Simkl OAuth-flöde |
| `GET` | `/api/oauth/simkl/callback` | Callback för Simkl (sparar token & startar import) |

### Spellista
| Metod | Endpoint | Beskrivning |
|---|---|---|
| `POST` | `/api/playlists` | Skapa ny spellista |
| `POST` | `/api/playlists/:id/items` | Lägg till film i spellista |

---

## För nästa IDE

1. **IMDb Betyg**: Implementera äkta IMDb-betygshämtning via OMDb API i scanner-steget (`scanner.ts`) så att de sparas i `media_metadata`.
2. **ffprobe**: Ersätt hårdkodad ljud/undertextinfo genom att köra `ffprobe` på videofilen och spara de riktiga spåren i databasen under skanningen.
3. **TV-serier**: Bygg ut seriestrukturen (Säsonger och Avsnitt) i frontend.

---

## Viktiga designprinciper

1. **Headless API-first** — All logik i backend, frontend är tunna vyer.
2. **Offgrid-first** — Fungerar utan internet efter initial metadatahämtning.
3. **SQLite WAL** — Enkelt att backa upp, hög lokal prestanda.
4. **Flutter cross-platform** — Samma kod → Webb + Android TV.
5. **Realtidssynk** — Betygsätt i Loom → Synkas direkt till Trakt, Simkl och TMDB.

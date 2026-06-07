# HANDOFF.md — Loom: Kortfattad överlämning för nästa IDE/AI

Senaste uppdatering: 2026-06-01

Syfte: Ge nästa utvecklare eller AI en fokuserad, handlingsbar översikt över status, högprioriterade problem, reproducerbara buggar och exakta nästa steg.

---

## 1. Snabb status

| Tjänst | Kommando | Port |
|--------|----------|------|
| Backend | `cd backend && npm run dev` | 8080 |
| Frontend webb | `cd frontend && flutter run -d web-server --web-port=50645` | 50645 |
| Frontend Windows | `cd frontend && flutter run -d windows` | — |

- Backend: Node + TypeScript (Fastify). Databas: SQLite på `config/loom.db` (inte under `backend/`).
- Frontend: Flutter. Startar alltid om från grunden vid paketkonflikter — kör `flutter clean && flutter pub get`.

---

## 2. Vad är implementerat (aktuell kodbas)

### Backend-routes (`backend/src/routes/`)
- **auth.ts** — JWT-login med bcrypt
- **media.ts** (~1900 rader) — filmer, serier, metadata, betyg, seen-status, progress, TMDB-matchning, watchlist, playlists, kollektioner, liknande titlar, skådespelarprofiler
- **playback.ts** — Direct Play (HTTP range), FFmpeg-transcode (MP4), HLS dynamisk segmentering, subtitle burn-in, intro/outro-markörer
- **library.ts** — scanning (bakgrund), sökvägar (CRUD), Windows-mappväljare
- **settings.ts** — nyckel-värde-inställningar
- **sync.ts** — manuell Trakt/Simkl-synk
- **oauth.ts** — Trakt OAuth + Simkl OAuth med automatisk historik-import

### Backend-tjänster (`backend/src/services/`)
- **scanner.ts** — rekursiv katalogscanning, FFprobe-integration (codec/resolution/ljud/undertext), TMDB-matchning, NFO-parsning
- **tmdb.ts** — TMDB API (filmer, serier, crew, awards)
- **rating_sync.ts** — import och synk av betyg/sedda-status mot Trakt & Simkl; körs vid startup och efter scanning

### Frontend-skärmar (`frontend/lib/screens/`)
- **dashboard_screen.dart** — biblioteksvy (grid/list, zoom, sök), inställningar, OAuth-knappar, navigationshistorik
- **media_details_screen.dart** — detaljsida med ratings (5 källor), cast, crew, awards, badges, play/resume, metadata-redigering
- **video_player_screen.dart** — HLS-spelare, undertextval, ljudspårsval, mini-player, tangentbordsgenvägar, progress-heartbeat
- **person_details_screen.dart** — skådespelarprofil, sökbar/sorterbar filmografi, lazy-load
- **resume_playback_modal.dart** — "Fortsätt titta / Börja om"-dialog

### Frontend-tjänst
- **api.dart** — komplett HTTP-klient för alla endpoints ovan

---

## 3. Kritiska, reproducerbara problem

### Resume / svart skärm (Windows + media_kit)
- **Symptom**: Vid "Fortsätt titta" svart skärm eller native texture crash på Windows.
- **Filer**: `video_player_screen.dart`, `media_details_screen.dart`
- **Känd orsak**: `Media(start: ...)` i `media_kit` på Windows triggar "Callback invoked after it has been deleted".
- **Stabil workaround**: Öppna via `open(uri, play: false)`, kalla `play()`, vänta ~150 ms, kalla sedan `seek()` till sparad position.
- **Debug**: Lägg till `player!.stream.error.listen((e) => debugPrint('Player error: $e'));` och logga `open/play/seek/dispose` för tidssekvens.

### FFmpeg stderr buffer hang
- **Symptom**: Transkodning hänger sig ibland utan felmeddelande.
- **Orsak**: `stderr`-bufferten på FFmpeg-processen dräneras inte.
- **Fix**: Sätt `{ stdio: 'ignore' }` i `spawn(ffmpegInstaller.path, ffmpegArgs, { stdio: 'ignore' })` i `playback.ts`.

### TV-serier saknar säsonger/avsnitt-vy
- **Symptom**: Serier scannas in och visas i dashboard men saknar korrekt säsonger/avsnitt-hierarki.
- **Filer**: `dashboard_screen.dart` (`_buildShowsView`), `media.ts` (`GET /api/media/shows`)
- **Status**: Struktur finns i backend-responset (episodlista) men frontend visar inte säsonger korrekt.

---

## 4. Viktiga filer att granska vid nästa session

| Fil | Relevans |
|-----|----------|
| `frontend/lib/screens/video_player_screen.dart` | Resume-bug, progress-heartbeat, mini-player |
| `frontend/lib/screens/media_details_screen.dart` | Detaljsida, play/resume-logik, metadata-edit |
| `frontend/lib/screens/dashboard_screen.dart` | TV-serier-vy, inställningar, OAuth |
| `frontend/lib/services/api.dart` | Alla HTTP-anrop |
| `backend/src/routes/playback.ts` | HLS-transcode, FFmpeg stderr-fix |
| `backend/src/routes/media.ts` | Allt om media (~1900 rader — sök, rör inte onödig logik) |
| `backend/src/services/scanner.ts` | FFprobe-integration, TMDB-matchning |
| `backend/src/services/rating_sync.ts` | Trakt/Simkl-synk |

---

## 5. Reproducera lokalt

```powershell
cd backend
npm install
npm run dev

# I ett nytt terminalfönster:
cd frontend
flutter pub get
flutter run -d windows   # eller -d web-server --web-port=50645 för webben
```

---

## 6. OAuth Redirect URIs

Måste registreras exakt hos respektive leverantör:

| Tjänst | Redirect URI |
|--------|-------------|
| Trakt | `http://localhost:8080/api/oauth/trakt/callback` |
| Simkl | `http://localhost:8080/api/oauth/simkl/callback` |

---

## 7. Nästa rekommenderade steg (prio)

### Hög
1. **TV-serier säsonger/avsnitt-vy**: Implementera `_buildShowsView` i `dashboard_screen.dart` med collapsible säsonger och avsnittslista. Backend levererar redan episode-data i `GET /api/media/shows`.
2. **FFmpeg stderr-fix**: Lägg till `{ stdio: 'ignore' }` på `spawn()`-anropet i `playback.ts` för att eliminera buffer hang vid långa transkodningar.

### Medium
3. **Docker**: Skriv `Dockerfile` + `docker-compose.yml` med volym-mount för `config/` och `MEDIA_PATH`. Testa med `/dev/dri` för hårdvaruacceleration (Unraid-kompatibelt).
4. **OMDb IMDb-betyg**: Verifiera att betyg cachas korrekt i alla scenarion (scanning, match, refresh) — kontrollera i `scanner.ts` och `tmdb.ts`.

### Låg
5. **Radarr/Sonarr-integration**: Webhook → auto-scan, "ta hem"-knapp för watchlist.

---

## 8. Lösta problem (historik, för referens)

| Problem | Lösning |
|---------|---------|
| Vit skärm efter auto-login | RenderFlex-exception i `dashboard_screen.dart` — åtgärdat |
| RenderFlex overflow i dropdowns | `isExpanded: true` på `DropdownButton` i `media_details_screen.dart` |
| Backend crash "Reply already sent" | Promise-hantering i FFmpeg HLS-kod i `playback.ts` + `.on('error')`-hanterare |
| FFmpeg saknas (ENOENT) | `@ffmpeg-installer/ffmpeg` installerat — bundlar statisk binär automatiskt |
| ffprobe saknas | `@ffprobe-installer/ffprobe` installerat — automatisk installation |
| Dynamisk HLS (seek) | HLS genereras nu dynamiskt via `/api/playback/dynamic/...` — korrekt filmlängd och omedelbar seek |
| Subtitle burn-in | Implementerat: text-undertexter via `subtitles`-filter, bild-undertexter via `overlay`-filter |
| Progress-sparning | `POST /api/media/items/:id/progress` implementerat; frontend skickar heartbeat var ~10:e sekund |
| Trakt/Simkl OAuth | Fullständigt OAuth-flöde med smart polling och automatisk historik-import |

---

## 9. Tips till nästa IDE/AI

1. Bekräfta alltid att båda processerna startar utan fel innan du rör koden.
2. Databasen sitter i `config/loom.db` — inte under `backend/`.
3. `media.ts` är ~1900 rader — använd `Ctrl+F`/sök aggressivt, rör inte logik utanför din uppgift.
4. Testa alltid resume-flödet på Windows efter ändringar i `video_player_screen.dart`.
5. OAuth-flödet kräver att backend körs på port 8080 — redirect URIs är hårdkodade till det.
6. Vid tillägg av nya Flutter-paket: starta om `flutter run`-processen helt (hot reload räcker inte).

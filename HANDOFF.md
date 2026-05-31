# HANDOFF.md — Loom: Status & Kontext för nästa AI/IDE

> **Skapad:** 2026-05-30  
> **Senast uppdaterad:** 2026-05-30  
> **Tidigare IDE:** Google Gemini / Antigravity (Med premium OAuth och UI-uppdateringar)  
> **Nästa IDE:** VS Code + GitHub Copilot

---

## Vad är Loom?

Loom är en **lokal, Loom-inspirerad mediaserver** med premium-UI. Användaren hostar den på sin egen server (Unraid/NAS) och når den via webb eller Android TV-app. Ingen molntjänst krävs.

**Arkitektur:** Fastify (Node/TS) backend + Flutter frontend (Web + Android TV). SQLite som databas.

---

## Aktuell körningsstatus

| Tjänst | Kommando | Port |
|---|---|---|
| Backend | `cd backend && npm run dev` | 8080 |
| Frontend webb | `cd frontend && flutter run -d web-server --web-port=50645` | 50645 |

> ⚠️ Frontend kör i `flutter run` (dev-läge med hot reload). Det finns INGET separat build-steg som krävs för utveckling.

---

## Senaste premium-uppdateringar (2026-05-30)

*   **Premium OAuth-integration för Trakt & Simkl**: 
    *   Helt färdigt OAuth-flöde där användaren klickar på "Anslut nu" under inställningarna, omdirigeras till Trakt/Simkl, godkänner och automatiskt paras ihop utan manuell token-inmatning.
    *   **Smart Polling**: Frontend pollar inställningarna i bakgrunden varannan sekund efter att popup-fönstret öppnats och uppdaterar omedelbart till **Ansluten ✅** så fort token sparats.
    *   **Automatisk betygssynk & Watched-status-import vid anslutning**: Så fort en koppling görs, startar backend bakgrundsjobb som laddar ner **alla historiska betyg och sedda filmer (watched history)** från Trakt/Simkl och synkar in dem i Loom SQLite-databasen automatiskt!
    *   **Kompakt och samlat inställnings-UI**: Alla API-fält, client secrets, Redirect URI-instruktioner, snabblänkar för registrering, och OAuth-knappar är nu logiskt grupperade bredvid varandra i stället för att vara splittrade.

---

## Vad som är implementerat ✅

### Backend (`backend/src/`)

#### Autentisering & OAuth (`routes/auth.ts`, `routes/oauth.ts`)
- [x] PIN-parningssystem för TV-appar: `POST /api/auth/pair/request` → `GET /api/auth/pair/status` → `POST /api/auth/pair/confirm`
- [x] JWT-baserad autentisering för alla skyddade endpoints.
- [x] **Trakt OAuth**: `GET /api/oauth/trakt/authorize` och `GET /api/oauth/trakt/callback` för säkert token-utbyte i bakgrunden.
- [x] **Simkl OAuth**: `GET /api/oauth/simkl/authorize` och `GET /api/oauth/simkl/callback` för Simkl.
- [x] **Automatisk bakgrundsimport av betyg och watched-status** från Trakt/Simkl till Loom-databasen vid lyckat OAuth-utbyte (`rating_sync.ts`).

#### Media & Ratings (`routes/media.ts`, `services/rating_sync.ts`)
- [x] `GET /api/media/items` — lista alla mediafiler (med metadata och watched-status).
- [x] `GET /api/media/items/:id` — hämta en films fullständiga data + all metadata.
- [x] `POST /api/media/items/:id/seen` — markera som sedd/osedd lokalt och synka upp till externa plattformar direkt.
- [x] `POST /api/media/items/:id/metadata` — spara betyg (0–10).
- [x] **Realtids betyg- & watched-synk**: När du sätter betyg eller markerar som sedd i Loom synkas detta omedelbart till Trakt, Simkl och TMDB i realtid!
- [x] **Automatisk schemalagd/startup synk**: `syncAllExternalData()` körs vid serverns start och vid avslutad biblioteksskanning för att hålla sedd-status ständigt uppdaterad.
- [x] `POST /api/media/items/:id/match` — manuell TMDB-omlänkning.

#### Inställningar & Scanner (`routes/settings.ts`, `services/scanner.ts`, `services/tmdb.ts`)
- [x] `GET/POST /api/settings` — nyckel-värde-inställningar (stöd för `TRAKT_CLIENT_SECRET` och `SIMKL_CLIENT_SECRET`).
- [x] Biblioteksskanning via `POST /api/scan/trigger`.
- [x] NFO-filparsning (local metadata).
- [x] Fallback-trailers via TMDB om svenska trailers saknas.
- [x] Snabblänkar för att registrera gratis API-nycklar (OMDb, Trakt, Simkl) integrerade i gränssnittet.

---

### Frontend (`frontend/lib/`)

#### Inställningar (`dashboard_screen.dart`)
- [x] **Logiskt strukturerat gränssnitt**: API-credentials och omdirigeringsknappar grupperade i "Simkl Integration" och "Trakt.tv Integration".
- [x] **Redirect URI-instruktioner**: Tydlig hjälptext med exakt Redirect URI som ska registreras hos respektive leverantör.
- [x] **Snabblänkar (OMDb, Simkl, Trakt)**: Smidiga klickbara länkar direkt bredvid fälten för att skaffa nycklar.
- [x] **Reaktiva synkkort**: Visar **Ansluten ✅** eller **Koppla från**-knappar och sparar/rensar automatiskt tokens till backend.

#### Filmdetaljer (`media_details_screen.dart`)
- [x] **Kvalitetsbadges**: 4K, 1080p, 5.1, DTS, Atmos, HDR, språk parsat från filnamn.
- [x] **Märkeslogotyper**: IMDb, Simkl och TMDB logotyper rensade och sorterade i ordningen: IMDb, Simkl, TMDB.
- [x] **Prisbadges**: Oscars, Golden Globes, BAFTA parsade från OMDb.
- [x] **ClearLOGO**: Snyggt placerad i full bredd precis ovanför filmens affisch (poster).
- [x] **Watch Providers**: Visar streamingtjänster som loggor.
- [x] **Slider för betyg**: Enkel 0–10 betygssättare som omedelbart synkar i bakgrunden.

---

## Vad som återstår 🔲

### Hög prioritet
- [ ] **Riktiga IMDb-betyg**: Idag visas hårdkodade ratings. Måste hämtas via OMDb API (`i=tt1234567`) och cachas i `media_metadata` under skanningen eller öppnandet av en film.
- [x] **Faktiska ljud- och undertextspår (ffprobe-integration)**: Integrerat `@ffprobe-installer/ffprobe` i backend (`scanner.ts`) som automatiskt installerar och använder den statiska Windows-binären för att läsa av alla tillgängliga ljud- och undertextspår från videofilen, lagra dem strukturerat i SQLite, samt rendera dem i dropdownsen.
- [ ] **TV-serier-vy**: `_buildShowsView` existerar men saknar seasons/episodes-struktur.

### Medium prioritet
- [ ] **Docker-konfiguration**: `Dockerfile` och `docker-compose.yml` anpassade för Unraid (med `/dev/dri` hårdvaruacceleration).
- [ ] **Musikmodul & Fotoalbum**: Inte påbörjade.
- [ ] **Radarr/Sonarr-integration**: "Ta hem"-funktion och interaktiv kalender.

---

## Viktiga mönster att känna till

### OAuth Redirect URIs
När användaren konfigurerar sina API-appar på Trakt/Simkl, måste de ställa in följande **Redirect URIs** för att OAuth-knapparna ska fungera:
- **Trakt**: `http://localhost:8080/api/oauth/trakt/callback`
- **Simkl**: `http://localhost:8080/api/oauth/simkl/callback`

### Databas (SQLite)
* Den faktiska databasen som används under utveckling ligger i roten: `config/loom.db` (inte under backend-mappen).
* Inställningar och tokens sparas i tabellen `system_settings`.

---

## Tips till nästa IDE/AI
1. **Fungerar kompilationen?** Ja! Frontend har alla importer (`dart:html`, `dart:async`) och inga syntaxfel finns kvar.
2. **Ratings-betygen**: Börja med att implementera den faktiska OMDb-hämtningen av IMDb-betyg under scanner-steget (se `backend/src/services/scanner.ts`) så att vi får äkta IMDb ratings och röstsiffror cachade i SQLite.
3. **ffprobe**: Bygg en liten ffprobe-wrapper i `backend/src/services/scanner.ts` som körs vid analys eller skanning av en videofil och sparar ljudspåren (t.ex. `ac3`, `dts`) samt undertextspåren till databasen.

# Loom — Projektvision & Arkitektur

Senast uppdaterad: 2026-06-01

---

## Övergripande mål

Loom ska vara den bästa lokala, offline-first mediaservern för en ensam eller liten hushållsanvändare som:

- Vill ha **full kontroll** över sin mediesamling utan molntjänst.
- Uppskattar **polerat UI** och omedelbar feedback (badges, betyg, progress).
- Vill **synka sedda-status och betyg** med Trakt/Simkl för att hålla sin historia samlad.
- Kör på **Unraid/NAS** eller en vanlig Windows-PC.

Designprinciper:
1. **Lokal first** — allt ska fungera utan internet.
2. **Omedelbar respons** — uppspelning, seek, statusändringar ska kännas snabba.
3. **Minimal friktion** — inga manuella konfigfiler, inga nödvändiga externa tjänster för grundfunktioner.

---

## Teknikstack

| Del | Teknologi | Varför |
|-----|-----------|--------|
| Backend | Node.js + TypeScript + Fastify | Snabb, typsäker, bra ekosystem för media |
| Databas | SQLite (WAL) | Ingen serverprocess, enkel backup |
| Frontend | Flutter (Web + Windows + Android) | En kodbas för alla plattformar |
| Medieverktyg | FFmpeg + FFprobe (bundlat) | Industristandardkodek, ingen installation |
| Videospelaren | media_kit | Native prestanda i Flutter |

---

## Status per 2026-06-01

### Implementerat och stabilt ✅

**Backend**
- JWT-autentisering
- Mediabibliotek: scanning, FFprobe, TMDB-matchning, NFO-stöd, versions-sammanslagning
- Video: Direct Play, HLS-transkodning (dynamisk segmentering), subtitle burn-in
- Metadata: TMDB + OMDb + Simkl + Trakt + Rotten Tomatoes, prisbadges, kollektioner
- Uppspelningsprogress: heartbeat-endpoint, auto-markera sedd vid 90 %
- Watchlist och playlists
- Trakt OAuth + Simkl OAuth med automatisk historik-import
- Schemalagd/startup-synk av betyg och sedda-status
- Inställningar via gränssnitt (inga `.env`-filer krävs)
- Metadata-lås per fält, manuell omlänkning, refresh

**Frontend**
- Biblioteksvy med grid/list, zoom (10 nivåer), sök och filtrering
- Detaljsida med alla ratings, cast, crew, awards, trailer, kollektioner, liknande titlar
- Videospelare med HLS, undertextval, ljudspårsval, mini-player, tangentbordsgenvägar
- Skådespelarprofil med sökbar/sorterbar filmografi
- Resume-modal ("Fortsätt titta / Börja om")
- Inbyggd metadata-redigering med fältlåsning
- OAuth-knappar med smart polling

### Kända brister / pågående arbete 🔲

**Hög prioritet**
- **TV-serier**: `_buildShowsView` existerar men saknar säsonger/avsnitt-struktur. Serier scannas in men visar inte korrekt hierarki.
- **Resume + Windows media_kit**: "Svart skärm"-felet vid resume är känt och har en stabil workaround, men inte ett permanent fix. Se `HANDOFF.md`.
- **Riktiga IMDb-betyg**: Hämtas via OMDb men behöver verifieras att de cachas korrekt i alla scenarion under scanning.

**Medium prioritet**
- Docker + hårdvaruaccelerationskonfiguration för Unraid (med `/dev/dri`)
- FFmpeg `stderr`-buffertproblem vid långa transkodningar (kan orsaka hang — fix: `{ stdio: 'ignore' }` på spawn)

**Låg prioritet / framtid**
- Radarr/Sonarr-integration ("ta hem"-funktion, kalender)
- Musikmodul och fotoalbum
- Export/Import av biblioteksdata och delning via säker länk

---

## Produktroadmap

### Sprint 1 — Stabilitet
- Fixa TV-serier/säsonger-vyn
- Robustifiera FFmpeg stderr-hantering (förhindra buffer hang)
- Bekräfta att OMDb IMDb-betyg cachas konsekvent

### Sprint 2 — Docker & Distribution
- `Dockerfile` + `docker-compose.yml` anpassade för Unraid
- Hardware acceleration via `/dev/dri` (Intel QSV / NVIDIA NVENC)
- Dokumentation för självhostning

### Sprint 3 — Radarr/Sonarr
- Webhook-integration: ny media i Radarr → auto-scan i Loom
- "Ta hem"-knapp för watchlist-items (triggar Radarr/Sonarr)
- Kalendervy för kommande releaser

### Långsiktigt
- Musikmodul (artist/album/spår med Last.fm-integration)
- Fotoalbum
- Mobilapp (Android/iOS) med offline-cache

---

## Operativa riktlinjer för nästa IDE/AI

1. Läs `HANDOFF.md` först — den har exakta filägar-platser, reproducerbara buggar och kodsnuttar.
2. Bekräfta alltid att `npm run dev` och `flutter run` startar rent innan du rör i koden.
3. Databasen sitter i `config/loom.db` — inte under `backend/`.
4. Testa alltid resume-flödet på Windows efter ändringar i `video_player_screen.dart`.
5. Backend-routes är stora filer (media.ts ~1900 rader) — använd sökning, rör inte logik du inte behöver.

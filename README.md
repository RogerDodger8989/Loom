# Loom 🎬

> **Din egna biografupplevelse — helt lokalt, helt under din kontroll.**

Loom är en självhostad mediaserver med premium-UI som ger dig precis den upplevelse du förväntar dig av de stora streamingtjänsterna — fast med din egen filmlista, dina egna betyg och ingen månadskostnad. Du hostar den på din maskin (Windows-PC/server) och når den via Windows-appen. Inget konto. Ingen molntjänst. Inga kompromisser.

---

## Vad skiljer Loom från andra mediaservrar?

- **Upp till 5 betyg-källor** — TMDB, IMDb, Rotten Tomatoes (via OMDb), Simkl, Trakt — allt på samma sida
- **Tvåvägssynk med Trakt & Simkl** — ett klick kopplar ihop, hela din historik importeras automatiskt
- **Zero-setup FFmpeg & FFprobe** — ingen manuell installation, bundlade binärer körs direkt
- **Dynamisk HLS-transkodning** — seek direkt till vilken position som helst, inga inladdningsskärmar
- **Subtitle burn-in för textundertexter** (SRT, ASS, SSA) — on-the-fly utan förprocessering
- **Teknisk mediainformation (Info)** — högerklicka på valfri titel och se fullständig FFprobe-data för alla filer/versioner
- **Metadata-djup** du inte hittar någon annanstans: prisbadges (Oscars, BAFTA, Golden Globe), kvalitetsbadges (4K/HDR/Atmos/DTS), ClearLOGO, filmografi per skådespelare
- **Tautulli-inspirerad statistik** — spelningshistorik per media och per användare, datumintervall-filter, topplista med expanderbara spelsessioner

---

## Snabbstart

### Krav
- **Node.js** 18+
- **Flutter** 3.x + Dart SDK
- FFmpeg/FFprobe installeras **inte** manuellt — bundlas automatiskt

### Standardinloggning (första start)
- **Användarnamn:** `admin`
- **Lösenord:** `adminpassword`

### Backend
```powershell
cd backend
npm install
npm run dev   # http://localhost:8080
```

### Frontend — Windows-app
```powershell
cd frontend
flutter pub get
flutter run -d windows
```

> **OBS:** Webbläsarläget (`flutter run -d web-server`) startar appen men videouppspelning fungerar inte — `media_kit` stöder inte webb. Använd Windows-appen.

### Build release (Windows)
```powershell
cd frontend
flutter build windows
```

---

## Teknikstack

| Del | Teknologi |
|-----|-----------|
| Backend | Node.js 18+ · TypeScript · Fastify |
| Databas | SQLite (WAL-läge) |
| Frontend | Flutter 3.x — Windows (primärt), Android (experimentellt) |
| Medieverktyg | FFmpeg + FFprobe (bundlat via npm — noll setup) |
| Videospelaren | media_kit — native prestanda i Flutter |

---

## Funktioner i detalj

### Bibliotek & Scanning

- **Valfritt antal bibliotekssökvägar** — filmer, serier och musik i separata mappar
- **Inbyggd Windows-mappväljare** — klicka dig fram istället för att skriva sökvägar
- **FFprobe-analys** vid scanning: codec, upplösning, bitrate, alla ljud- och undertextspår
- **Automatisk TMDB-matchning** under scanning
- **Manuell omlänkning** om matchningen är fel: sök i TMDB, välj rätt match
- **Avlänkning och Refresh** — tvinga om-hämtning av all metadata med ett klick
- **NFO-filstöd** — lokal metadata (från t.ex. Kodi) prioriteras framför TMDB
- **Versions-sammanslagning** — 1080p + 4K av samma film grupperas automatiskt under en titel
- **Bakgrundsscanning** — appen är responsiv medan scanning pågår; realtidslogg i inställningar
- **Skanningfilter** — hoppa över filer via nyckelord eller minsta filstorlek (MB)
- **Fil-bevakare** — valfritt automatisk omskanningvid filändringar i biblioteksmappen

---

### Videouppspelning

**Direct Play**
Filen streamas direkt via HTTP range requests. Ingen CPU-last på servern. Perfekt för MP4/MKV/WebM.

**Real-time Transcode (web-stream)**
FFmpeg transkoderar filen till MP4 i realtid. Stöd för MKV, x265, AV1 och format som inte spelas nativt. Välj bitrate i spelaren.

**Dynamisk HLS-segmentering**
FFmpeg delar upp filmen i 10-sekunders segment med en riktig HLS-spellista:
- Seek direkt till vilken position som helst — ingen väntetid
- Korrekt filmlängd från start
- Segment cachas på servern för snabba omsök
- Konfigurerbart max antal simultana transkodningsströmmar (`MAX_STREAMS`, standard 3)

**Subtitle burn-in**
- **Textundertexter** (SRT, ASS, SSA) — via FFmpeg `subtitles`-filtret, välj spår i spelaren
- **Bildbaserade undertexter (PGS/VOBSUB)** — stöd under aktiv utveckling; fungerar i många fall men inte stabilt vid alla seek-positioner

**I spelargränssnittet**
- Välj mellan alla ljud- och undertextspår som FFprobe hittade i filen
- **Skip Intro / Skip Outro** — knapp dyker upp automatiskt baserat på markördata
- **Mini-player** — minimera spelaren till ett flytande fönster nere till vänster
- **Resume** — position sparas var ~10:e sekund; välj "Fortsätt titta" eller "Börja om" nästa gång
- **Auto-markera sedd** — vid 90 % av filmen markeras den automatiskt och synkas med Trakt/Simkl
- **Kö / Queue** — serier spelas upp i ordning automatiskt (alla avsnitt i säsongen köas)
- **Warmup** — första HLS-segmenten förrenderas i bakgrunden vid öppnandet av en detaljsida

**Tangentbordsgenvägar**
| Tangent | Funktion |
|---------|----------|
| Mellanslag | Play / Pause |
| ← / → | Sök 10 / 30 sekunder |
| ↑ / ↓ | Volym +5 / −5 % |
| M | Mute / Unmute |
| F | Fullskärm |
| Esc | Avsluta fullskärm |

---

### Metadata & Betyg

**Betyg från upp till 5 källor**
IMDb · Rotten Tomatoes (båda via OMDb API) · TMDB · Trakt · Simkl — allt på samma sida. Kräver respektive API-nyckel i inställningarna.

**Ditt eget betyg (0–10)**
Betygschips på detaljsidan. Synkas omedelbart till Trakt & Simkl i bakgrunden.

**Badges**
- *Pris:* Oscars · Golden Globe · BAFTA (parsade från OMDb)
- *Kvalitet:* 4K · 1080p · 720p · HDR · Dolby Vision · Dolby Atmos · DTS · 5.1 (parsade från filnamnet)

**Visuellt**
- ClearLOGO från TMDB ovanför affischen
- Fanart som bakgrundsbild
- Watch Providers — vilka streamingtjänster titeln finns på (via TMDB, kräver region-inställning)

**Redigera metadata direkt i appen**
- Ändra titel, plot, år, genre, regissör, poster-URL, fanart-URL
- **Metadata-lås per fält** — lås ett fält för att förhindra överskrivning vid Refresh

---

### Teknisk mediainformation (Info-dialog)

Högerklicka på valfri titel i biblioteket och välj **Info**. Dialogen visar live FFprobe-data direkt från filen — ingen rescanning krävs.

**Tre sektioner:**

| Sektion | Innehåll |
|---------|---------|
| **Media** | Duration, Bitrate, Width/Height, Aspect Ratio, Resolution, Container, Frame Rate |
| **Fil** | Filnamn, Storlek, Audio/Video Profile, Container |
| **Data** | Codec, Bitrate, Språk, Bit Depth, Chroma, Frame Rate, Nivå |

- **Full filsökväg** visas under filmtiteln
- **All text är markerbar** — högerklicka för Windows standardmeny
- **Multipla versioner**: dropdown väljer "Alla versioner" eller en specifik fil

---

### Kapitelmarkörer & Intro-detektion

- **Manuella markörer** — sätt intro/outro/kapitel-markörer per film eller avsnitt
- **Automatisk kapitelextraktion** — FFmpeg extraherar inbäddade kapitel direkt ur filen
- **Audio-fingeravtrycks-detektion** — Goertzel-baserad algoritm analyserar ljudet för att hitta introts start- och sluttid automatiskt
- **Batch-fingeravtryckning** — skanna hela en serie på en gång
- Markörer lagras per avsnitt och visas som "Skip Intro"-knapp i spelaren

---

### Högerklicksmeny på poster

Högerklicka på valfri film/serie i biblioteket för snabbåtgärder:

| Åtgärd | Beskrivning |
|--------|-------------|
| Ta bort från Fortsätt titta | Nollar sparad progress |
| Lägg till på spellista | Lägg till i en spellista (skapar ny vid behov) |
| Markera som visad/osedd | Toggla + synkar till Trakt/Simkl |
| Uppdatera metadata | Hämtar om all metadata från externa källor |
| Analysera | Kör FFprobe på nytt på filen |
| Redigera | Öppnar metadata-redigeraren direkt |
| Fixa matchning | Manuell TMDB-omlänkning |
| Ta bort matchning | Avlänka från TMDB |
| Ta bort | Flyttar filen till `.trash`-mappen (Admin) |
| Info | Öppnar teknisk mediainformation (FFprobe) |
| **Visa statistik** | Visar spelningshistorik för just det mediet — vem som sett det, när, och om visningen slutfördes |

---

### Statistik

En Tautulli-inspirerad statistikmodul med tre flikar, tillgänglig under Inställningar → Statistik. All data uppdateras live var 5:e sekund.

#### Överblick
- Totalt antal sedda unika titlar och tittartimmar (alla tider)
- Aktiva användare
- CPU- och RAM-användning med färgkodad mätare
- Serverns drifttid och databasstorlek
- Per-användare-sammanfattning: antal sedda titlar, totalt antal timmar, senast aktiv

#### Historik
- Scrollbar lista med senast spelade titlar (film, avsnitt, användarnamn, datum, längd)
- **Användarfilter** — filtrera på specifik användare eller alla
- **Snabbval** — Alla tider / 7 / 30 / 90 dagar
- **Datumintervall** — två kalenderväljare (Från / Till) med år-, månads- och dagsvy. Datumfiltret tar prioritet över snabbvalet; "Rensa datum" återställer till snabbval
- Klicka på affischen för att navigera direkt till titeln

#### Toppar
- **Mest sedda filmer** — top 10 rankade efter spelantal
- **Mest sedda TV-serier** — top 10 rankade efter spelantal
- **Mest aktiva användare (30 dagar)** — top 10 rangordnade efter tittartid

**Expanderbara spelsessioner:** Klicka på "X spelningar"-texten (understruken, pekare ändras) för att fälla ut en panel med vem som sett titeln:
- *Film:* ungefärlig starttid, sluttid, "Slutförd ✓" eller procentandel sedd
- *TV-serie:* användarens totala antal avsnitt, klara avsnitt, startdatum, senast sedd, total tittartid

**Navigera till användarhistorik:** Klicka på en användare i "Mest aktiva användare" för att direkt hoppa till Historik-fliken filtrerad på den användaren (pil-ikon + ledtext indikerar klickbarhet).

#### Visa statistik (högerklick)
Högerklicka på valfri titel i biblioteket → **Visa statistik**. Öppnar en dialog med komplett spelningshistorik för just det mediet — samma data som i den expanderbara panelen ovan, men åtkomlig direkt från biblioteket utan att behöva gå till Statistik-sidan.

---

### Skådespelarprofiler & Filmografi

- Biografi från TMDB (engelsk fallback)
- Filmografi med sök, avdelningsfilter (Acting / Directing / Writing / Production) och sortering
- Tre visningslägen: List / Grid / Card
- Indikerar om titeln finns i biblioteket, på watchlist eller inte alls
- Lazy-loading — 50 titlar initialt, ladda fler på klick

---

### Kollektioner & Rekommendationer

- **Kollektioner** — TMDB-filmserier (Marvel, Star Wars etc.) med indikation vilka du äger
- **Liknande titlar** — TMDB-rekommendationer filtrerade mot ditt bibliotek

---

### Watchlist & Playlists

- **Watchlist** — titlar du vill se eller bevaka; synkar med Trakt/Simkl
- **Playlists** — lägg till titlar via högerklicksmenyn. Notera: dedikerat gränssnitt för att bläddra och hantera spellistor är inte implementerat än.

---

### RSS-flöden

- Lägg till valfria RSS-flöden (t.ex. nyhetssajter för film/serie)
- Automatisk titel-parsning från kanalen
- Visa och läs de 100 senaste posterna från alla flöden
- Manuell uppdatering av alla flöden med ett klick
- Konfigureras under Inställningar → Källor & Integrationer

---

### Papperskorg

Raderade filer hamnar i en `.trash`-mapp under respektive bibliotekssökväg. Under Inställningar → Papperskorg kan du:
- Se alla borttagna titlar med filstorlek och raderingsdatum
- Filtrera och söka bland borttagna filer
- Återskapa enskilda titlar till biblioteket
- Permanent radera filer från hårddisken

---

### Kalender

En kalendervy visar kommande och nyligen tillagda avsnitt/filmer per datum. Klicka på en dag för att se vad som finns. Stöder även:
- **Trakt-kalender** (kräver OAuth-koppling)
- **Simkl-kalender** (kräver OAuth-koppling)
- **IMDb-watchlist** konverteras till kalenderhändelser
- **iCal-export** — exportera hela kalendern som `.ics`-fil för import i Outlook, Google Calendar m.fl.

---

### Inloggning & Användarprofiler

- Profilväljare vid start — klicka på ditt konto, ange lösenord
- **PIN-inloggning** — konfigurera en sifferkod för snabb inloggning (utan tangentbord)
- **Avatar** — ladda upp en profilbild under Inställningar → Konto
- Roller: **Admin** (full åtkomst) och **User** (begränsad åtkomst)

---

### Inställningar (10 kategorier)

Öppnas via profilmenyn uppe till höger. Alla inställningar sätts i gränssnittet — inga `.env`-filer.

| Kategori | Innehåll |
|----------|---------|
| **Konto** | Byt lösenord, ändra visningsnamn, sätt PIN-kod, ladda upp avatar |
| **Användare** | Skapa/redigera/ta bort användare, sätt roller (Admin-only) |
| **Bibliotek** | Lägg till/redigera/ta bort bibliotekssökvägar, starta scanning, skanningfilter |
| **Papperskorg** | Återskapa eller permanent radera borttagna filer |
| **Uppspelning** | Standardspråk för undertext och ljud, metadataspråk, titeldisplaystil |
| **Källor & Integrationer** | TMDB · OMDb · Trakt OAuth · Simkl OAuth · IMDb-ID · RSS-flöden · API-nycklar |
| **Notifieringar** | Discord Webhook-URL · E-post via SMTP (host, port, avsändare, mottagare) |
| **Statistik** | Live CPU/RAM, spelningshistorik med datumfilter, topplista med expanderbara sessioner, per-användarstatistik |
| **Loggning** | Realtidslogg från backend (polling var 3:e sekund) + logg-nedladdning |
| **Server** | Server-info, databasoptimering (VACUUM), säkerhetskopia, återställning, export/import av inställningar, serveromstart |

**OAuth Redirect URIs** — registrera dessa exakt hos respektive leverantör:

| Tjänst | Redirect URI |
|--------|-------------|
| Trakt | `http://localhost:8080/api/oauth/trakt/callback` |
| Simkl | `http://localhost:8080/api/oauth/simkl/callback` |

---

### Trakt & Simkl — tvåvägssynk

1. Klicka "Anslut nu" under Inställningar → Källor & Integrationer
2. Webbläsaren öppnar Trakt/Simkl — godkänn
3. Token tas emot automatiskt — ingen manuell kopiering

Vid anslutning importeras automatiskt all betygshistorik och sedda-historik. Sedan:
- Betygsändring i Loom → synkas direkt till Trakt & Simkl
- Markera som sedd → synkas direkt
- Manuell synk-knapp finns i inställningarna
- Automatisk synk vid serverstart och var 45:e minut (konfigurerbart via `EXTERNAL_SYNC_INTERVAL_MINUTES`)

---

## Arkitektur

```
Loom/
├── backend/
│   ├── src/
│   │   ├── config/        # Databas-setup (SQLite, schema, seed)
│   │   ├── routes/
│   │   │   ├── auth.ts        # JWT-login, PIN-login, profillistning, lösenords-/avatarbyte
│   │   │   ├── media.ts       # Core media: filmer, serier, metadata, watchlist, playlists
│   │   │   ├── playback.ts    # Streaming, HLS-transkodning, subtitle burn-in
│   │   │   ├── library.ts     # Scanning, bibliotekssökvägar, fil-bevakare, export
│   │   │   ├── markers.ts     # Kapitel- och intro/outro-markörer, fingeravtryck
│   │   │   ├── settings.ts    # Systeminställningar
│   │   │   ├── users.ts       # Användarhantering (Admin)
│   │   │   ├── stats.ts       # Realtids- och historisk statistik, per-media spelhistorik
│   │   │   ├── logs.ts        # In-memory logglagring och hämtning
│   │   │   ├── notifications.ts # Discord webhook + SMTP e-post
│   │   │   ├── rss.ts         # RSS-flöden: hämta, spara, visa
│   │   │   ├── calendar.ts    # Kalender (lokalt, Trakt, Simkl, IMDb, iCal-export)
│   │   │   ├── server.ts      # Server-info, DB-backup, DB-restore, optimering, omstart
│   │   │   ├── export.ts      # Export/import av inställningar och data (ZIP)
│   │   │   ├── sync.ts        # Manuell och schemalagd extern synk
│   │   │   └── oauth.ts       # Trakt & Simkl OAuth-flöde
│   │   ├── services/
│   │   │   ├── tmdb.ts        # TMDB API-klient
│   │   │   ├── scanner.ts     # FFprobe + biblioteksskanning (film, serie, musik)
│   │   │   ├── marker_service.ts  # Kapitelextraktion + audio-fingeravtryck
│   │   │   ├── rating_sync.ts # Trakt/Simkl import & synk
│   │   │   ├── notify.ts      # Notifieringshjälpare
│   │   │   ├── log_store.ts   # In-memory loggbuffert
│   │   │   └── scan_events.ts # Realtidshändelser under scanning
│   │   └── index.ts           # Fastify-app, exporterar buildApp()
│   ├── src/__tests__/         # Jest-enhetstester
│   └── package.json
├── frontend/
│   ├── lib/
│   │   ├── screens/
│   │   │   ├── dashboard_screen.dart        # Biblioteksvy, hem, högerklicksmeny, navigation
│   │   │   ├── media_details_screen.dart    # Film/serie-detaljsida
│   │   │   ├── video_player_screen.dart     # Spelaren (HLS, undertexter, mini-player, kö)
│   │   │   ├── person_details_screen.dart   # Skådespelarprofil & filmografi
│   │   │   ├── media_info_dialog.dart       # Teknisk mediainformation (Info)
│   │   │   ├── resume_playback_modal.dart   # "Fortsätt titta / Börja om"-dialog
│   │   │   ├── settings_screen.dart         # Inställningar (10 kategorier inkl. statistik)
│   │   │   ├── trash_screen.dart            # Papperskorg
│   │   │   ├── calendar_screen.dart         # Kalendervy
│   │   │   ├── login_screen.dart            # Inloggning med användarprofiler och PIN
│   │   │   └── user_picker_overlay.dart     # Användarval-overlay
│   │   ├── services/
│   │   │   └── api.dart                     # Alla HTTP-anrop mot backend
│   │   └── main.dart
│   ├── test/                                # Flutter-enhetstester
│   └── pubspec.yaml
└── config/
    └── loom.db    # SQLite-databasen (skapas automatiskt vid första start)
```

---

## API — komplett referens

### Autentisering & Användare

| Metod | Endpoint | Beskrivning |
|-------|----------|-------------|
| POST | `/api/auth/login` | Logga in med lösenord, returnerar JWT |
| POST | `/api/auth/login-pin` | Logga in med PIN-kod, returnerar JWT |
| POST | `/api/auth/verify-pin` | Verifiera PIN utan full inloggning |
| GET | `/api/auth/profiles` | Lista användarprofiler (utan lösenord) |
| GET | `/api/auth/me` | Hämta inloggad användares profil |
| PUT | `/api/auth/me` | Byt lösenord, visningsnamn, PIN |
| POST | `/api/auth/me/avatar` | Ladda upp profilbild |
| GET | `/api/avatars/:filename` | Hämta profilbild |
| GET | `/api/users` | Lista alla användare (Admin) |
| POST | `/api/users` | Skapa ny användare (Admin) |
| PUT | `/api/users/:id` | Uppdatera användare (Admin) |
| DELETE | `/api/users/:id` | Ta bort användare (Admin) |

### Media & Metadata

| Metod | Endpoint | Beskrivning |
|-------|----------|-------------|
| GET | `/api/media/movies` | Lista alla filmer (versions-sammanslagning som standard) |
| GET | `/api/media/shows` | Lista alla serier |
| GET | `/api/media/items/:id` | Fullständiga detaljer: metadata, betyg, cast, awards, versions |
| GET | `/api/media/items/:id/metadata-state` | Hämta metadata med lås-flaggor |
| POST | `/api/media/items/:id/metadata` | Spara/uppdatera metadata-värden |
| PUT | `/api/media/items/:id/metadata-lock` | Toggla metadata-lås per fält |
| PATCH | `/api/media/items/:id` | Uppdatera kärn-fält (titel, år, plot m.m.) |
| GET | `/api/media/items/:id/tech-info` | Live FFprobe-data för en fil |
| POST | `/api/media/items/:id/seen` | Toggla sedd/osedd (+ omedelbar extern synk) |
| POST | `/api/media/items/:id/progress` | Spara uppspelningsprogress (heartbeat) |
| DELETE | `/api/media/items/:id` | Flytta fil till `.trash`, ta bort ur databasen |
| DELETE | `/api/media/episodes/:id` | Mjukradera enstaka avsnitt |
| DELETE | `/api/media/seasons/:showId/:season` | Mjukradera hela säsongen |
| GET | `/api/media/items/:id/search-tmdb` | Sök TMDB-kandidater för omlänkning |
| GET | `/api/media/search-tmdb` | Fri TMDB-sökning |
| POST | `/api/media/items/:id/match` | Länka manuellt till TMDB-ID |
| POST | `/api/media/items/:id/unmatch` | Avlänka från TMDB |
| POST | `/api/media/items/:id/refresh` | Hämta om all metadata från externa källor |
| POST | `/api/media/items/:id/analyze` | Kör FFprobe på nytt på filen |
| GET | `/api/media/collections/:id` | Hämta kollektion (filmserier från TMDB) |
| GET | `/api/media/:id/similar` | Liknande titlar (filtrerade mot biblioteket) |
| GET | `/api/people/:id` | Skådespelarprofil + filmografi |
| GET | `/api/watchlist` | Lista watchlist |
| POST | `/api/watchlist` | Lägg till på watchlist |
| DELETE | `/api/watchlist/:tmdbId` | Ta bort från watchlist |
| POST | `/api/playlists` | Skapa spellista |
| POST | `/api/playlists/:id/items` | Lägg till media i spellista |
| GET | `/api/trash` | Lista mjukraderade objekt |
| POST | `/api/trash/:id/restore` | Återskapa från papperskorg |
| DELETE | `/api/trash/:id/permanent` | Permanent radera från disk + databas |

### Uppspelning

| Metod | Endpoint | Beskrivning |
|-------|----------|-------------|
| GET | `/api/playback/file-path/:id` | Hämta lokal filsökväg som `file://`-URL |
| GET | `/api/playback/stream/:id` | Direct play (HTTP range, MKV/MP4/WebM) |
| GET | `/api/playback/web-stream/:id` | FFmpeg real-time transcode → MP4 med subtitle-stöd |
| GET | `/api/playback/dynamic/:id/playlist.m3u8` | HLS-spellista (dynamisk segmentering) |
| GET | `/api/playback/dynamic/:id/segment/:seg` | HLS-segment (transkodas och cachas on-demand) |
| GET | `/api/playback/markers/:id` | Skip intro/outro-markörtider |
| GET | `/api/stream/warmup/:id` | Förrendera de första HLS-segmenten i bakgrunden |

### Bibliotek

| Metod | Endpoint | Beskrivning |
|-------|----------|-------------|
| POST | `/api/library/scan` | Starta bakgrundsskanning (returnerar 202 direkt) |
| GET | `/api/library/status` | Skanningsstatus: isScanning, lastScanResult |
| GET | `/api/library/paths` | Lista alla bibliotekssökvägar |
| POST | `/api/library/paths` | Lägg till ny sökväg |
| PUT | `/api/library/paths` | Redigera sökväg |
| DELETE | `/api/library/paths` | Ta bort sökväg + cascade-radera associerat media |
| PUT | `/api/library/paths/watch` | Toggla fil-bevakning för en sökväg |
| GET | `/api/library/browse-native` | Öppna Windows native mappväljare |
| GET | `/api/library/scan-events` | Hämta realtidshändelser under scanning |
| GET | `/api/library/export` | Exportera sedda-status och betyg (JSON/CSV) |

### Markörer

| Metod | Endpoint | Beskrivning |
|-------|----------|-------------|
| GET | `/api/markers/:id` | Hämta alla markörer för ett media-objekt eller avsnitt |
| POST | `/api/markers` | Skapa manuell markör |
| DELETE | `/api/markers/:markerId` | Ta bort en markör |
| GET | `/api/markers/scan-status` | Kolla status för pågående fingeravtrycksscanning |
| POST | `/api/markers/scan-chapters/:id` | Extrahera kapitel från fil (bakgrund) |
| POST | `/api/markers/scan-fingerprint/:episodeId` | Beräkna audio-fingeravtryck för avsnitt |
| POST | `/api/markers/scan-show/:showId` | Fingeravtryck för hela serien + detektera intro |
| POST | `/api/markers/detect-intro/:showId` | Kör intro-detektion på befintliga fingeravtryck |

### Statistik & Logg

| Metod | Endpoint | Beskrivning |
|-------|----------|-------------|
| GET | `/api/stats/realtime` | CPU, RAM, upptime, DB-storlek |
| GET | `/api/stats/history` | Tittarhistorik filtrerad per användare, dagar eller datumintervall (`startDate`/`endDate`) |
| GET | `/api/stats/users` | Per-användarstatistik (sedda titlar, timmar, senast aktiv) |
| GET | `/api/stats/tops` | Top 10 filmer, TV-serier och mest aktiva användare (30 dagar) |
| GET | `/api/stats/media/:mediaId/plays` | Spelningshistorik för ett specifikt medium (film: per session, TV-serie: aggregerat per användare) |
| GET | `/api/logs` | Hämta loggposter (stöder `?sinceId=` för incremental polling) |
| GET | `/api/logs/download` | Ladda ned hela loggen som fil |

### Kalender & RSS

| Metod | Endpoint | Beskrivning |
|-------|----------|-------------|
| GET | `/api/calendar` | Lokala avsnitt/filmer per datumintervall |
| GET | `/api/calendar/trakt` | Trakt-personlig kalender (kräver OAuth) |
| GET | `/api/calendar/simkl` | Simkl-personlig kalender (kräver OAuth) |
| GET | `/api/calendar/imdb` | IMDb-watchlist-baserad kalender |
| GET | `/api/calendar/export.ics` | Exportera kalender som iCal-fil |
| GET | `/api/rss/feeds` | Lista RSS-flöden |
| POST | `/api/rss/feeds` | Lägg till RSS-flöde |
| DELETE | `/api/rss/feeds/:id` | Ta bort RSS-flöde |
| GET | `/api/rss/items` | Senaste poster från alla flöden |
| POST | `/api/rss/refresh` | Hämta nytt från alla flöden |

### Inställningar, Synk, OAuth & Server

| Metod | Endpoint | Beskrivning |
|-------|----------|-------------|
| GET/PUT | `/api/settings` | Läs/spara systeminställningar |
| POST | `/api/sync/trigger` | Starta fullständig Trakt/Simkl-synk |
| GET | `/api/sync/status` | Synk-progress och sista resultat |
| GET | `/api/oauth/trakt/authorize` | Redirect till Trakts OAuth-sida |
| GET | `/api/oauth/trakt/callback` | Ta emot token, importera historik |
| GET | `/api/oauth/simkl/authorize` | Redirect till Simkls OAuth-sida |
| GET | `/api/oauth/simkl/callback` | Ta emot token, importera historik |
| GET | `/api/server/info` | Server-info: upptime, DB-storlek, antal media/användare |
| POST | `/api/server/db/optimize` | Kör SQLite VACUUM + WAL checkpoint |
| GET | `/api/server/db/backup` | Ladda ned SQLite-databasen som fil |
| POST | `/api/server/db/restore` | Ladda upp databas för återställning (startar om servern) |
| POST | `/api/server/restart` | Starta om backend-servern |
| GET | `/api/export` | Exportera inställningar/bibliotek/historik som ZIP |
| POST | `/api/import` | Importera ZIP-backup |
| POST | `/api/notifications/test/discord` | Skicka testmeddelande via Discord webhook |
| POST | `/api/notifications/test/email` | Skicka testmail via SMTP |

---

## Viktiga filer

| Fil | Beskrivning |
|-----|-------------|
| [frontend/lib/screens/dashboard_screen.dart](frontend/lib/screens/dashboard_screen.dart) | Biblioteksvy, hem, högerklicksmeny, navigation |
| [frontend/lib/screens/media_details_screen.dart](frontend/lib/screens/media_details_screen.dart) | Detaljsida: metadata, betyg, play, resume, edit |
| [frontend/lib/screens/video_player_screen.dart](frontend/lib/screens/video_player_screen.dart) | Spelaren: HLS, undertexter, mini-player, kö, progress |
| [frontend/lib/screens/person_details_screen.dart](frontend/lib/screens/person_details_screen.dart) | Skådespelarprofil med sökbar filmografi |
| [frontend/lib/screens/media_info_dialog.dart](frontend/lib/screens/media_info_dialog.dart) | Info-dialog: live FFprobe-data, versioner, selectable text |
| [frontend/lib/screens/settings_screen.dart](frontend/lib/screens/settings_screen.dart) | Inställningar med 10 kategorier inkl. statistikmodul |
| [frontend/lib/screens/trash_screen.dart](frontend/lib/screens/trash_screen.dart) | Papperskorg: återskapa eller permanent radera |
| [frontend/lib/screens/calendar_screen.dart](frontend/lib/screens/calendar_screen.dart) | Kalendervy för avsnitt/filmer (lokal + Trakt/Simkl/IMDb) |
| [frontend/lib/screens/login_screen.dart](frontend/lib/screens/login_screen.dart) | Inloggning med användarprofiler och PIN |
| [frontend/lib/services/api.dart](frontend/lib/services/api.dart) | Alla HTTP-anrop mot backend |
| [backend/src/routes/media.ts](backend/src/routes/media.ts) | Core media-endpoints |
| [backend/src/routes/playback.ts](backend/src/routes/playback.ts) | Streaming, HLS-transkodning, subtitle burn-in |
| [backend/src/routes/stats.ts](backend/src/routes/stats.ts) | Statistik: historik, toppar, per-media spelhistorik |
| [backend/src/routes/markers.ts](backend/src/routes/markers.ts) | Kapitelmarkörer och intro-detektion |
| [backend/src/services/scanner.ts](backend/src/services/scanner.ts) | Biblioteksskanning + FFprobe |
| [backend/src/services/marker_service.ts](backend/src/services/marker_service.ts) | Audio-fingeravtryck och kapitelextraktion |
| [backend/src/services/rating_sync.ts](backend/src/services/rating_sync.ts) | Trakt/Simkl import & synk |
| [config/loom.db](config/loom.db) | SQLite-databasen |

---

## Felsökning

### Backend startar inte — EADDRINUSE port 8080
En gammal Node-process håller porten. Kör i PowerShell:
```powershell
Stop-Process -Id (netstat -ano | Select-String ':8080 ' | ForEach-Object { ($_ -split '\s+')[-1] } | Select-Object -First 1) -Force
```

### Flutter bygger inte — saknade ephemeral-filer
```powershell
cd frontend
flutter clean
flutter pub get
flutter run -d windows
```

### Svart skärm vid Resume (Windows)
`Media(start: ...)` i `media_kit` kan krascha native texture-callbacks.
Workaround (redan implementerad): `open(uri, play: false)` → `play()` → delay 150 ms → `seek()`.

### Backend returnerar 200 men ingen video visas
Kontrollera CORS-headers och `Content-Type`. Lägg till `player.stream.error.listen(...)` i spelaren för att se low-level-fel.

### FFmpeg saknas / ENOENT-fel
`@ffmpeg-installer/ffmpeg` bundlar rätt binär automatiskt. Verifiera att `npm install` kördes utan fel i `backend/`.

### Glömt lösenord / Admin-lösenord
Standardlösenordet som sätts vid databasens skapande: **`adminpassword`**. Byt det under Inställningar → Konto efter inloggning.

### PGS/VOBSUB-undertexter visas inte
PGS burn-in är under aktiv utveckling och fungerar inte stabilt vid alla seek-positioner. Använd SRT/ASS-undertexter för tillförlitlig visning.

---

## Kommande funktioner

- **Musikmodul** — scanning är implementerad men bläddrings- och uppspelningsgränssnitt saknas
- **Spellisthantering** — bläddra och hantera spellistor (inte bara lägga till via högerklick)
- **Docker + hårdvaruacceleration** (`/dev/dri`) för Unraid/NAS
- **Radarr/Sonarr-integration** — "ta hem" direkt från watchlist
- **Fotoalbum**

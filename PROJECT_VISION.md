# Loom - Projektvision & Arkitektur

Detta dokument fungerar som den övergripande specifikationen och "master plan" för Loom, så att vi aldrig tappar bort grundvisionen för hur systemet ska fungera och byggas.

## 1. Övergripande Vision & Arkitektur
Loom är en helt API-driven, modulär ("headless") mediaserver byggd för att fungera 100 % "offgrid" och lokalt, men med säker åtkomst över internet. Systemet hanterar film, TV-serier, musik och fotoalbum. Ingen affärslogik eller databasåtkomst sker i klienterna; både TV-appen och skrivbordsappen kommunicerar uteslutande via ett strukturerat REST- och WebSocket-API.

**Teknikstack:**
- **Backend:** Node.js med TypeScript och ramverket Fastify (för maximal API-prestanda).
- **Databas:** SQLite med WAL-mode (Write-Ahead Logging) för optimal lokal prestanda och enkel backup (allt i en fil i `/config`).
- **Paketering:** Docker-container anpassad för Unraid-servrar (med miljövariabler för hårdvaruacceleration, t.ex. `/dev/dri`).
- **Mediehantering:** Inbäddad FFmpeg-binär i Docker-containern för strömning och transkodning.
- **Klienter (Frontend):** En gemensam kodbas i Flutter som kompilerar till en Android-TV-app (med fullt stöd för D-pad/fjärrkontroll) och en skrivbordsapp för dator (PC).

## 2. Autentisering & Enhetsparning (Plex-liknande PIN)
**Offgrid-first:** Ingen extern molntjänst krävs för inloggning.

**PIN-parningsflöde:**
1. En oautentiserad TV-app anropar `POST /api/auth/pair/request` och får en tidsbegränsad alfanumerisk kod (t.ex. X87B) samt ett unikt `Device_ID`.
2. Användaren loggar in via en datorwebbläsare (som admin eller vanlig användare) och anger koden under enhethanteringen (`POST /api/auth/pair/confirm`).
3. Backend parar ihop `Device_ID` med användarkontot i databasen.
4. TV-appen pollar backend (eller lyssnar via WebSocket) och tar emot ett giltigt JWT (JSON Web Token) för framtida krypterade API-anrop.

## 3. Användarroller, Behörigheter & Innehållsfiltrering
- **Roller:** Systemet har två grundroller: `Admin` och `User`.
- **Granulär filtrering:** Admin kan tilldela restriktioner per användare baserat på Genre, Keywords eller Age_Rating.
- **API-nivå:** När en användare begär media (t.ex. `GET /api/media/movies`) applicerar backend automatiskt filter i SQL-frågan. Otillåten media exkluderas helt i databasnivå, vilket gör att användaren aldrig kan se eller gissa att innehållet existerar.

## 4. Medieströmning & Realtidstranskodning
- **Direct Play (Prioriterat):** Om klienten stöder video- och ljudformatet skickas filen rå via HTTP för att minimera CPU/GPU-belastning på Unraid-servern.
- **Valbar transkodning:** Användaren kan i klientens spelare manuellt välja fasta bitrates (t.ex. 2 Mbps, 4 Mbps, 8 Mbps, 20 Mbps) för att anpassa sig efter nätverket över internet.
- **HLS (HTTP Live Streaming):** Backend använder FFmpeg för att koda om strömmen i realtid till H.264/H.265-video och AAC-ljud, uppdelat i sekventiella `.ts`-segment.
- **Hårdvaruacceleration:** Stöd för Intel QuickSync (QSV) och Nvidia NVENC via mappning av grafikdrivrutiner i Docker.

## 5. Hybrid Metadatahantering & Låsning
- **Biblioteksinställning:** Varje mediebibliotek har en boolean: `prefer_local_nfo`.
- **Skanningslogik:**
  - **Om true:** Skannern letar först efter lokala `.nfo`-filer och bilder (`-poster.jpg`, `-fanart.jpg`). Finns de, läses de in. Data som saknas kompletteras via TMDB (The Movie Database) API.
  - **Om false:** Skannern struntar i lokala filer och hämtar all metadata direkt från TMDB baserat på mapp-/filnamn och år.
- **Admin-editering & Metadata-lås:** Admin kan redigera metadata (titlar, beskrivningar etc.) direkt i webb-/admin-gränssnittet. Vid manuell ändring sätts flaggan `is_locked = true` på det specifika fältet i databasen. Framtida biblioteksskanningar hoppar helt över att skriva över låsta fält.
- **Multi-versioner:** Om samma film finns i flera utgåvor (t.ex. 4K HDR och 1080p SDR) ska systemet stödja två valbara visningslägen i inställningarna:
  - **Sammanslaget läge:** Filmerna grupperas till ett kort, och användaren väljer version vid uppspelning.
  - **Separerat läge:** Filmerna visas som egna kort i biblioteket, men får en visuell badge/tagg på omslaget (t.ex. "4K" eller "1080p") som genereras automatiskt baserat på filens upplösning.

## 6. Den Interaktiva Historiska Kalendern & *arr-Integration
- **Datakälla 1 (Lokal/Live):** Anropar Radarr- och Sonarr-API:er för att hämta planerad sändningsstatus, samt flagga avsnitt som "Missing" (saknade).
- **Datakälla 2 (Global/Watchlist):** Gör ett schemalagt bakgrundsjobb mot användarens synkade Simkl- eller IMDb-watchlist för att hämta premiärdatum för ej ägd media.
- **Interaktivt UI:** Kalendern kan backas och bläddras i månadsvis bakåt i tiden. Varje titel har en färgkodad status:
  - **Grön (Ägs):** Finns lokalt på servern och är spelbar.
  - **Gul (Bevakas):** Ligger i Radarr/Sonarrs kö men är ej färginedladdad.
  - **Röd (Saknas):** Finns på din externa watchlist eller har sänts, men saknas lokalt.
- **"Ta hem"-knapp:** Vid klick på en "Röd" eller saknad titel skickar Loom-backend ett API-anrop till Radarr eller Sonarr för att lägga till produktionen och trigga en omedelbar sökning på dina indexers.

## 7. Lokal Scrobbling, Spårning & Import/Export
- **Lokal Scrobbling:** Vid uppspelning skickas hjärtslag (`POST /api/playback/progress`) var 10:e sekund till backend. Framstegen sparas i tabellen `WATCH_HISTORY`. Vid 90 % av speltiden flaggas mediet automatiskt som "Sedd".
- **Visuellt framsteg (Continue Watching):** På hemskärmen ritas en visuell linje (progress bar) ut baserat på procentuell framgång `((last_position / total_duration) * 100)`.
- **Offgrid Import/Export:**
  - **Import:** Möjlighet att ladda upp en CSV/JSON-fil exporterad från IMDb, Trakt eller Simkl. Backend matchar IMDb-id och sätter rätt historisk status.
  - **Export:** Dumpa hela din lokala visningshistorik, betyg och watchlist till en JSON/CSV-fil.
- **Tvåvägssynk (Tillval):** Manuell knapp för att synka den lokala datan ut till Trakt/Simkl.

## 8. Avancerad Seriehantering & Undertexter
- **Multi-Episode-filer:** Databasen (`EPISODES`) stöder att en videofil pekar på flera unika avsnitt (t.ex. `S01E01-E02.mkv`). När filen spelats klart markeras samtliga länkade avsnitt som sedda.
- **Intro & Outro Skipping:** `EPISODE_MARKERS` lagrar tidsstämplar. Klienten visar en interaktiv "Hoppa över"-knapp när uppspelningen når dessa tidsspann.
- **Undertextmotor:** Systemet skannar efter lokala externa `.srt`-filer samt inbäddade spår. Saknas text anropar backend OpenSubtitles/Bazarr API och laddar ner till mediets mapp.

## 9. Musik- & Bildmoduler (Fotoalbum)
- **Musikmodul:** Skannern använder en inbäddad ID3-parser för metadata. Saknad info hämtas via MusicBrainz/Last.fm. All musikscrobbling sparas lokalt med stöd för export. Ljud spelas i bakgrunden vid navigering i klienten.
- **Bildmodul (Fotoalbum):** Mappbaserad struktur lagrad i databasen. Backend genererar automatiskt on-the-fly nerskalade miniatyrer (via Sharp) i cache för snabb laddning. Originalen förblir orörda.

## 10. Aktuell verklighet i kodbasen
- Media-detaljvyn visar redan tagline, director, cast, keywords, production companies, watch providers, trailer och liknande media.
- Awards är fortfarande ett aktivt felsökningsområde. Backend försöker nu fylla `awards` via OMDb först och sedan via TMDB:s publika awards-sida, men UI visar fortfarande inget för vissa titlar.
- Den praktiska databasen i workspace ligger i `config/loom.db` i rotmappen.
- Nästa IDE ska prioritera att bekräfta om `metadata.awards` faktiskt sparas i SQLite eller om felet sitter i frontend-renderingen/parsen.


---

## Implementeringsstatus (Uppdaterad 2026-05-30)

Kärnan i systemet är nu byggd och fungerande. Se **HANDOFF.md** for detaljerad status om vad som ar implementerat och vad som aterstar.

**Aktiva tjanster:**
- Backend: `http://localhost:8080`
- Frontend: `http://localhost:50645`

**Naasta steg:** Riktiga IMDb/Simkl-betyg, ffprobe for ljud/undertext, och TV-seriestruktur.

**Nuvarande fokus:** Awards-nomineringar syns fortfarande inte i UI trots backend-fallback. Felsök datavägen från `GET /api/media/items/:id` till `media_details_screen.dart`.

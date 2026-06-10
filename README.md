# Loom 🎬

> **Din egna biografupplevelse — helt lokalt, helt under din kontroll.**

Loom är en självhostad mediaserver med premium-UI som ger dig precis den upplevelse du förväntar dig av de stora streamingtjänsterna — fast med din egen filmlista, dina egna betyg och ingen månadskostnad. Du hostar den på din maskin (Windows-PC/server) och når den via Windows-appen. Inget konto. Ingen molntjänst. Inga kompromisser.

---

## Vad skiljer Loom från andra mediaservrar?

- **Upp till 5 betyg-källor** — TMDB, IMDb, Rotten Tomatoes (via OMDb), Simkl, Trakt — allt på samma sida
- **Tvåvägssynk med Trakt & Simkl** — ett klick kopplar ihop, hela din historik importeras automatiskt
- **Zero-setup FFmpeg & FFprobe** — ingen manuell installation, bundlade binärer körs direkt
- **Dynamisk HLS-transkodning** — seek direkt till vilken position som helst, inga inladdningsskärmar
- **Inbyggd Trailer-uppspelning** — streama trailers i realtid direkt i appen via YouTube/TMDB utan att lämna videospelaren
- **Teknisk mediainformation (Info)** — högerklicka på valfri titel och se fullständig FFprobe-data för alla filer/versioner
- **Tautulli-inspirerad statistik** — spelningshistorik per media och per användare, datumintervall-filter, topplista med expanderbara spelsessioner
- **Säker Papperskorg (`.trash`)** — Filer du raderar flyttas till papperskorgen där de ignoreras av skannern. Återställ dem eller töm papperskorgen för att radera dem permanent.
- **Manuella TMDB-Matchningar** — Filmen hittades inte? Högerklicka och "Fixa Matchning" låter dig söka manuellt och applicera rätt metadata direkt.

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

**Undertexter & Ljudspår (Filmer & Serier)**
Loom skannar och analyserar numera individuella ljud- och undertextspår även för **TV-serier (avsnitt)**!
- **Textundertexter** (SRT, ASS, SSA) — via FFmpeg `subtitles`-filtret, välj spår i spelaren
- **Automatisk val** — Finns det bara ett undertextspår väljer appen det automatiskt, annars styrs det av dina inställda språkpreferenser.
- **Bildbaserade undertexter (PGS/VOBSUB)** — stöd under aktiv utveckling; fungerar i många fall men inte stabilt vid alla seek-positioner

**I spelargränssnittet**
- Välj mellan alla ljud- och undertextspår som FFprobe hittade i filen
- **Skip Intro / Skip Outro** — knapp dyker upp automatiskt baserat på markördata
- **Mini-player** — minimera spelaren till ett flytande fönster nere till vänster
- **Resume** — position sparas var ~10:e sekund; välj "Fortsätt titta" eller "Börja om" nästa gång
- **Auto-markera sedd** — vid 90 % av filmen markeras den automatiskt och synkas med Trakt/Simkl
- **Kö / Queue** — serier spelas upp i ordning automatiskt (alla avsnitt i säsongen köas)

---

### Metadata & Betyg

**Betyg från upp till 5 källor**
IMDb · Rotten Tomatoes (båda via OMDb API) · TMDB · Trakt · Simkl — allt på samma sida. Kräver respektive API-nyckel i inställningarna.

**Ditt eget betyg (0–10)**
Betygschips på detaljsidan. Synkas omedelbart till Trakt & Simkl i bakgrunden.

**Badges**
- *Pris:* Oscars · Golden Globe · BAFTA (parsade från OMDb)
- *Kvalitet:* 4K · 1080p · 720p · HDR · Dolby Vision · Dolby Atmos · DTS · 5.1 (parsade från filnamnet)

**Redigera metadata direkt i appen**
- Ändra titel, plot, år, genre, regissör, poster-URL, fanart-URL
- **Metadata-lås per fält** — lås ett fält för att förhindra överskrivning vid Refresh

**Trailer Streaming**
Klicka på Trailer-knappen för att streama trailers direkt via YouTube till Looms interna media-spelare, helt sömlöst integrerat i UI:t.

---

### Teknisk mediainformation (Info-dialog)

Högerklicka på valfri titel i biblioteket och välj **Info**. Dialogen visar live FFprobe-data direkt från filen — ingen rescanning krävs.

**Tre sektioner:**

| Sektion | Innehåll |
|---------|---------|
| **Media** | Duration, Bitrate, Width/Height, Aspect Ratio, Resolution, Container, Frame Rate |
| **Fil** | Filnamn, Storlek, Audio/Video Profile, Container |
| **Data** | Codec, Bitrate, Språk, Bit Depth, Chroma, Frame Rate, Nivå |

- **Full sökväg** visas under filmtiteln
- **All text är markerbar** — högerklicka för Windows standardmeny
- **Multipla versioner**: Hanterar filmer/avsnitt i både t.ex. 1080p och 4K i samma gränssnitt!

---

### Papperskorg (Trash Bin)

Oroar du dig för att råka radera filmer? Looms papperskorg förhindrar misstag:
- Högerklicka -> **Ta bort** flyttar filen från din biblioteksmapp in till en dold `.trash`-mapp.
- Skannern har smarta ignorera-regler och letar **aldrig** i `.trash`-mappar. Raderat material dyker därmed aldrig upp i biblioteket av misstag.
- Öppna Papperskorgen i gränssnittet för att antingen **Återställa** (flyttar tillbaka filen och aktiverar den i biblioteket igen) eller **Radera Permanent** (tar bort filen helt från disken och databasen).

---

### Kapitelmarkörer & Intro-detektion

- **Manuella markörer** — sätt intro/outro/kapitel-markörer per film eller avsnitt
- **Automatisk kapitelextraktion** — FFmpeg extraherar inbäddade kapitel direkt ur filen
- **Audio-fingeravtrycks-detektion** — Goertzel-baserad algoritm analyserar ljudet för att hitta introts start- och sluttid automatiskt
- **Batch-fingeravtryckning** — skanna hela en serie på en gång

---

### Högerklicksmeny på poster

Högerklicka på valfri film/serie i biblioteket för snabbåtgärder:

| Åtgärrd | Beskrivning |
|--------|-------------|
| Ta bort från Fortsätt titta | Nollar sparad progress |
| Lägg till på spellista | Lägg till i en spellista (skapar ny vid behov) |
| Markera som visad/osedd | Toggla + synkar till Trakt/Simkl |
| Uppdatera metadata | Hämtar om all metadata från externa källor |
| Analysera | Kör FFprobe på nytt på filen |
| Redigera | Öppnar metadata-redigeraren direkt |
| **Fixa matchning** | Sök manuellt efter TMDB-matchning i en popup-dialog |
| Ta bort matchning | Avlänka från TMDB |
| **Ta bort** | Flyttar filen till `.trash`-mappen |
| Info | Öppnar teknisk mediainformation (FFprobe) |
| Visa statistik | Visar spelningshistorik för just det mediet |

---

### Statistik

En Tautulli-inspirerad statistikmodul med tre flikar, tillgänglig under Inställningar → Statistik. All data uppdateras live var 5:e sekund.

#### Överblick
- Totalt antal sedda unika titlar och tittartimmar
- Aktiva användare
- **CPU- och RAM-användning** med färgkodad live-mätare
- Serverns drifttid och databasstorlek

#### Historik
- Scrollbar lista med senast spelade titlar (film, avsnitt, användarnamn, datum, längd)
- **Användarfilter** — filtrera på specifik användare eller alla
- **Snabbval & Datumintervall** — filtrera precis som du vill

#### Toppar & Expandering
- **Mest sedda filmer & Serier** — top 10
- **Expandera Sessioner** — klicka på en användare för att expandera exakt vilka avsnitt/filmer som setts och när!
- Klicka på användare för att hoppa direkt till filtrerad användarhistorik.

---

### Kalender (Trakt, Simkl & IMDb)

Under menyn **Kalender** hittar du premiärkalendern:
- **Lokalt:** Vad finns på din server?
- **Trakt / Simkl:** Inloggade konton synkar ner avsnitt du följer så du vet när de sänds.
- **IMDb:** Hämta baserat på din IMDb-watchlist!

---

## Felsökning

### Backend startar inte — EADDRINUSE port 8080
En gammal Node-process håller porten. Kör i PowerShell:
```powershell
Stop-Process -Id (netstat -ano | Select-String ':8080 ' | ForEach-Object { ($_ -split '\s+')[-1] } | Select-Object -First 1) -Force
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

---

## Kommande funktioner

- **Musikmodul** — scanning är implementerad men bläddrings- och uppspelningsgränssnitt saknas
- **Spellisthantering** — bläddra och hantera spellistor
- **Docker + hårdvaruacceleration** (`/dev/dri`) för Unraid/NAS
- **Radarr/Sonarr-integration** — "ta hem" direkt från watchlist
- **Fotoalbum**

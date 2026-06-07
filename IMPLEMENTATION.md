# Loom — Implementationsstatus

> Uppdaterad: 2026-06-06 (session 2 — stora uppdateringar gjorda)
> Använd denna fil för att spåra vad som är gjort och vad som återstår.
> ✅ = Klar | 🔧 = Delvis klar / behöver förbättras | ❌ = Saknas / ej påbörjad

---

## INSTÄLLNINGAR

### Konto (`_buildKonto()` i settings_screen.dart)

| # | Funktion | Status | Anteckning |
|---|---|---|---|
| 1 | Visa inloggat användarnamn + roll | ✅ | JWT-payload |
| 2 | Byta lösenord (eget) | ✅ | `PUT /api/auth/me` |
| 3 | Byta fullständigt namn | ✅ | `full_name`-kolumn + UI-fält + `PUT /api/auth/me` |
| 4 | Byta användarnamn | ✅ | Unik-kontroll i backend |
| 5 | Byta profilbild | ❌ | Kräver fil-upload + avatar-lagring |
| 6 | Sätta PIN-kod | ✅ | `pin_hash`-kolumn + UI + `POST /api/auth/verify-pin` |
| 7 | Ta bort PIN-kod | ✅ | "Ta bort PIN"-knapp, sätter pin_hash=null |

---

### Användare — Admin only (`_buildAnvandare()`)

| # | Funktion | Status | Anteckning |
|---|---|---|---|
| 1 | Lista alla användare | ✅ | `GET /api/users` |
| 2 | Lägga till användare | ✅ | `POST /api/users` |
| 3 | Sätta roll (Admin/User) | ✅ | PopupMenu → `PUT /api/users/:id` |
| 4 | Byta lösenord på användare | ✅ | Dialog → `PUT /api/users/:id` |
| 5 | Ta bort användare | ✅ | `DELETE /api/users/:id` |
| 6 | Byta fullständigt namn på användare | ✅ | Dialog "Redigera" i PopupMenu |
| 7 | Byta användarnamn på användare | ✅ | Samma dialog |
| 8 | Byta profilbild på användare | ❌ | Kräver fil-upload |
| 9 | Sätta PIN-kod på användare | ✅ | PIN-fält i "Redigera"-dialog |
| 10 | Ta bort PIN-kod på användare | ✅ | Töm PIN-fält och spara |

---

### Papperskorg (`_buildPapperskorg()`)

| # | Funktion | Status | Anteckning |
|---|---|---|---|
| 1 | Visa borttagna mediefiler (lista) | ✅ | TrashScreen inbäddad |
| 2 | Visa **cover/poster** per fil | ✅ | Thumbnail 36×52 bredvid titel |
| 3 | Högerklicksmeny: Återställ | ✅ | GestureDetector onSecondaryTapDown → showMenu |
| 4 | Högerklicksmeny: Visa info | ✅ | Info-dialog med poster, genre, datum, sökväg |
| 5 | Direktuppspelning / önskad transcode | ❌ | |
| 6 | Visa statistik per fil (speltid osv) | ❌ | |
| 7 | Permanent radera (inkl. från disk) | ✅ | Varningsdialog finns |
| 8 | Återställ (soft-delete undo) | ✅ | |

---

### Statistik (`_buildStatistik()`)

| # | Funktion | Status | Anteckning |
|---|---|---|---|
| 1 | CPU/RAM realtid (5s polling) | ✅ | LinearProgressIndicator-gaugar |
| 2 | Upptime + DB-storlek | ✅ | |
| 3 | Spelningshistorik — lista (de 10 senaste) | ✅ | Grundläggande lista, ingen cover |
| 4 | Per-användare — aggregerad tabell | ✅ | Sedda titlar + seendetid |
| 5 | **Dashboard-stats** — 4 siffror överst | ✅ | Total tid, unika titlar, aktiva användare, sedda |
| 6 | **Spelningshistorik med cover** | ✅ | Thumbnail + titel + datum + seendetid |
| 7 | **Användarfilter** (dropdown) | ✅ | Välj användare → visa deras historik |
| 8 | **Datumintervall-filter** | ✅ | Alla tider / 7 / 30 / 90 dagar |
| 9 | **Toppar — Mest sedda filmer** | ✅ | Poster + spelcount + tid (topp 10) |
| 10 | **Toppar — Mest sedda TV-serier** | ✅ | Poster + avsnitt sedda (topp 10) |
| 11 | **Toppar — Mest aktiva användare** | ✅ | Avatar + seendetid (senaste 30 dagar) |
| 12 | **Heatmap** — populäraste dag/timme | ❌ | Ej implementerat |
| 13 | Backend: `GET /api/stats/tops` | ✅ | Top 10 film/TV/användare |
| 14 | Backend: historik med filter | ✅ | userId + days + limit-parametrar |

---

### Loggning (`_buildLoggning()`)

| # | Funktion | Status | Anteckning |
|---|---|---|---|
| 1 | Realtidslogg (polling 3s, sinceId) | ✅ | |
| 2 | Nivåfilter (Alla/info/warn/error) | ✅ | |
| 3 | Auto-scroll toggle | ✅ | Knapp med ikon |
| 4 | Rensa-knapp | ✅ | |
| 5 | Ladda ner loggar | ✅ | |
| 6 | **Paus-knapp** (bredvid auto-scroll) | ✅ | Orange "Pausad"-knapp, stopp fetching utan att rensa |

---

### Server (`_buildServer()`)

| # | Funktion | Status | Anteckning |
|---|---|---|---|
| 1 | Servernamn — spara/visa | ✅ | `system_settings` → `SERVER_NAME` |
| 2 | DB-optimera (WAL checkpoint) | ✅ | |
| 3 | DB-backup (ladda ner .db) | ✅ | |
| 4 | DB-återställ (upload .restore) | ✅ | |
| 5 | **Starta om servern** (Admin) | ✅ | `POST /api/server/restart` + bekräftelsedialog i inställningar |
| 6 | **Servernamn under loggan** i sidomenyn | ✅ | Hämtas via `_loadSettings`, visas under LOOM-texten med separator |
| 7 | **Klocka på/av** — visas till höger om framåtpil | ✅ | SHOW_CLOCK-toggle i Server-inställningar, Timer varje sekund |

---

## VÄNSTER-MENYN (Sidofältet)

| # | Funktion | Status | Anteckning |
|---|---|---|---|
| 1 | Animerad bredd (280 ↔ 80) | ✅ | AnimatedContainer |
| 2 | Fäll ihop/ut knapp | ✅ | chevron_left / menu-ikon |
| 3 | Menyalternativ (Hem/Filmer/TV/Kalender) | ✅ | |
| 4 | **Pil bakåt, Hem, Pil framåt — lodrätt** | ✅ | Column-layout när indragen, Row när expanderad |
| 5 | **Servernamn försvinner när indragen** | ✅ | Syns under LOOM-loggan när expanderat, döljs ihopfällt |
| 6 | **Avdelare** (rak linje) under servernamnet | ✅ | `Divider(color: white 8%)` under logo-sektion |
| 7 | **Fälla ut-knappen under nav-pilarna** | ✅ | chevron_right-knapp sist i Column när indragen |

---

## PROFIL-MENYN (uppe till höger — PopupMenuButton)

| # | Funktion | Status | Anteckning |
|---|---|---|---|
| 1 | Mitt konto → öppnar Inställningar > Konto | ✅ | |
| 2 | Inställningar | ✅ | |
| 3 | Byt användare | ✅ | |
| 4 | Logga ut | ✅ | |
| 5 | **Starta om servern** (syns bara för Admin) | ✅ | Bekräftelsedialog + anrop `POST /api/server/restart` |

---

## BACKEND — API-endpoints

| Endpoint | Status | Anteckning |
|---|---|---|
| `GET /api/stats/realtime` | ✅ | CPU, RAM, upptime, DB-storlek |
| `GET /api/stats/history?userId&days&limit` | ✅ | Filter + allTimeTotals i response |
| `GET /api/stats/users` | ✅ | Per-användare aggregat (inkl. id) |
| `GET /api/stats/tops` | ✅ | Top 10 film/TV/användare (30 dagar) |
| `POST /api/server/restart` | ✅ | Admin-only, JWT-verifiering, `process.exit(0)` |
| `PUT /api/auth/me` (fullständigt namn, användarnamn, PIN) | ✅ | Utökat med full_name, newUsername, pin |
| `PUT /api/users/:id` (fullständigt namn, PIN) | ✅ | Admin kan sätta full_name + pin på valfri användare |
| `POST /api/auth/verify-pin` | ✅ | Kontrollera PIN för profilväljaren |
| `POST /api/auth/me/avatar` | ❌ | Multipart file upload (ej implementerat) |

---

## DB — Kolumner som saknas

| Tabell | Kolumn | Status |
|---|---|---|
| `users` | `full_name TEXT` | ✅ | ALTER TABLE migration i database.ts |
| `users` | `pin_hash TEXT` | ✅ | ALTER TABLE migration i database.ts |
| `users` | `avatar_path TEXT` | ✅ | Kolumn tillagd, men upload-UI saknas |

---

## ÖVRIGT / FRAMTID

| Funktion | Status | Anteckning |
|---|---|---|
| HW-kodning (NVENC/QSV/VAAPI) | ❌ | FFmpeg-flaggor |
| Max simultana strömmar (semaphore) | ❌ | Begränsa antal FFmpeg-processer |
| RSS-feeds i Källor & Integrationer | ❌ | |
| IMDb-betyg via OMDb | ❌ | Hårdkodade just nu |
| Episoders egna subtitle/audio-tracks | 🔧 | Lagras per show, inte per episod |
| PGS i direct play — bekräftat fungerande | 🔧 | Implementerat, ej verifierat |

---

## Implementeringsordning (förslag nästa session)

1. ✅ **Vänster-menyn** — lodrätt nav-pilar + servernamn + avdelare + knapp-ordning
2. ✅ **Loggning** — paus-knapp
3. ✅ **Server** — Starta om (backend + UI + profil-meny)
4. ✅ **Server** — Klocka på/av
5. ✅ **Server** — Servernamn under loggan i sidomenyn
6. ✅ **Statistik** — Dashboard-stats + cover i historik + användarfilter + toppar
7. ✅ **Konto/Användare** — fullständigt namn, användarnamn, PIN-kod
8. ✅ **Papperskorg** — cover, högerklicksmeny, info-dialog

### Återstår (nästa session)
- ❌ **Profilbild** — fil-upload + avatar-lagring + CircleAvatar med bild
- ❌ **Papperskorg** — direktuppspelning från .trash-mappen
- ❌ **Statistik** — heatmap (dag/timme-grid)
- ❌ **IMDb-betyg** — via OMDb API (ej hårdkodat)

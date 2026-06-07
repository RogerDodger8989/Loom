# Inställningar — Omstruktureringsplan

## För ny session — läs detta först

### Orientering
1. Läs [`frontend/lib/screens/settings_screen.dart`](frontend/lib/screens/settings_screen.dart) — entry-point är `openSettings()`, all state i `_SettingsScreenState`, callback `onLibraryChanged` triggar dashboard att ladda om media
2. Läs [`frontend/lib/screens/dashboard_screen.dart`](frontend/lib/screens/dashboard_screen.dart) — `_buildUserSwitcher()` öppnar `openSettings()` via PopupMenuButton
3. Backend-routes i [`backend/src/routes/`](backend/src/routes/) — registreras i [`backend/src/index.ts`](backend/src/index.ts)
4. Nästa steg = första `- [ ]` i implementeringsordningen nedan

### Filstruktur för inställningar
| Fil | Roll |
|---|---|
| `frontend/lib/screens/settings_screen.dart` | Hela settings-UI:t — en stor StatefulWidget |
| `frontend/lib/services/api.dart` | Alla API-anrop — lägg till metoder i slutet av klassen |
| `backend/src/routes/settings.ts` | GET+PUT `/api/settings` — platt nyckel/värde-tabell i SQLite |
| `backend/src/routes/notifications.ts` | POST `/api/notifications/test/discord` + `/test/email` |
| `backend/src/routes/logs.ts` | GET `/api/logs` + `/api/logs/download` |
| `backend/src/routes/server.ts` | GET `/api/server/info`, POST `optimize`, GET `backup`, POST `restore` |
| `backend/src/services/log_store.ts` | In-memory cirkulär loggbuffer (1000 poster) |

### Mönster för att lägga till ny kategori (används för steg 7 & 8)
1. **State** — lägg till controllers/variabler i `_SettingsScreenState` under rätt `// ── X state ──`-block
2. **dispose()** — lägg till nya controllers i `for (final c in [...]) { c.dispose(); }`
3. **_applySettings / _saveSettings** — om kategorin har nyckel/värde-inställningar: lägg till i båda
4. **_buildContent()** — ersätt `_buildStub(...)` med `_buildX()` vid rätt case-index (0=Konto, 1=Användare)
5. **_buildX()** — implementera UI-metoden, se `_buildNotifieringar()` eller `_buildServer()` som mall
6. **Backend** — skapa ny route-fil, registrera i `index.ts`, lägg till API-metod i `api.dart`
7. **SETTINGS_PLAN.md** — kryssa av steget och uppdatera statustabellen

### Vad som är klart (behöver ej röras)
- `_buildBibliotek()` — kategori 2 (index 2)
- `_buildPapperskorg()` — kategori 3 (index 3)
- `_buildUppspelning()` — kategori 4 (index 4)
- `_buildKallor()` — kategori 5 (index 5)
- `_buildNotifieringar()` — kategori 6 (index 6)
- `_buildLoggning()` — kategori 8 (index 8) — startar polling i `onTap`, stoppar vid annat val
- `_buildServer()` — kategori 9 (index 9) — laddar serverinfo via `Future.microtask` vid första build

### ✅ Steg 7 & 8 är klara

**Steg 7 (Användare)** — `backend/src/routes/users.ts` + `_buildAnvandare()`:
- GET/POST/PUT/DELETE `/api/users` — Admin-only via JWT-hook
- UI: lista med roll-badge, PopupMenu (byt roll / återställ lösenord / ta bort)
- Skapa-formulär med roll-dropdown

**Steg 8 (Konto)** — `PUT /api/auth/me` i `auth.ts` + `_buildKonto()`:
- Visa inloggat användarnamn + roll från JWT-payload
- Formulär: nuvarande + nytt + bekräfta lösenord

### Nästa fas: Statistik (steg 9)
Se "Statistik — backend att-göra" längst ned.

## Arkitektur
- Inställningar öppnas via **profilikon uppe till höger** (overlay/dialog, inte tab)
- **Två-panels-layout**: vänster kategorilista (~220px) | höger scrollbart innehåll
- Scanner-tab tas **bort** från vänster sidomenyn — absorberas i Bibliotek-kategorin
- Papperskorg-skärmen absorberas in som underkategori

## Kategorier och innehåll

| # | Kategori | Innehåll | Status |
|---|---|---|---|
| 1 | **Konto** | Inloggad användare + roll, byt lösenord | ✅ klar |
| 2 | **Användare** *(Admin)* | Skapa/ta bort användare, roller (Admin/User), återställ lösenord | ✅ klar |
| 3 | **Bibliotek** | Skanningsvägar, skanningsschema, bevaka mapp, TMDB/OMDb-nyckel, metadata-språk, fallback-språk, NFO-preferens, titeldisplay, JustWatch-region | ✅ klar |
| 4 | **Papperskorg** | TrashScreen inbäddad | ✅ klar |
| 5 | **Uppspelning** | Ljud/textningsspråk, fönster (alltid överst) | ✅ klar (delvis — saknar HW-kodning, max strömmar) |
| 6 | **Källor & Integrationer** | TMDB, OMDb, Simkl OAuth + sync, Trakt OAuth + sync | ✅ klar (saknar RSS) |
| 7 | **Notifieringar** | Discord webhook-URL, SMTP e-post | ✅ klar |
| 8 | **Statistik** | CPU/RAM realtid (5s polling), spelningshistorik, per-användare | ✅ klar |
| 9 | **Loggning** | Realtidslogg, filter, nedladdning | ✅ klar |
| 10 | **Server** | Servernamn, port, DB-optimera, backup/återställ | ✅ klar |

## Implementeringsordning

- [x] 1. Struktur — profilikon-overlay, två-panels-layout, 10 kategorier (stubs)
- [x] 2. Bibliotek — Scanner-innehåll + biblioteksvägar + metadata-inställningar
- [x] 3. Papperskorg — TrashScreen inbäddad som underkategori
- [x] 4. Notifieringar — Discord webhook + SMTP (nodemailer)
- [x] 5. Loggning — realtidslogg (SSE eller polling) + nedladdning
- [x] 6. Server — DB backup/restore/optimera
- [x] 7. Användare — admin-hantering (frontend + backend)
- [x] 8. Konto — profilredigering

## Statistik — klar

- [x] `GET /api/stats/realtime` — CPU% (sampling 500ms), RAM, upptime, DB-storlek
- [x] `GET /api/stats/history` — senast sedda + totaler (antal/tid)
- [x] `GET /api/stats/users` — aggregerat per användare (sedda, tid, senast sett)
- [x] Flutter: polling var 5:e sekund, LinearProgressIndicator-gaugar, per-användare-tabell

## Noteringar

- Discord webhook: trivial — bara POST till URL med `{content: "..."}` eller embed
- E-post: `nodemailer` npm-paketet, kräver SMTP-konfiguration av användaren
- Hårdvarukodning: FFmpeg-flaggor `-hwaccel nvenc` / `-hwaccel qsv` / `-hwaccel vaapi`
- Max strömmar: semaphore i backend som begränsar antal simultana FFmpeg-processer

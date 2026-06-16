# Loom – Kodstandard

## Modulgränser (obrytbara regler)

```
Backend JSON
    ↓
ApiService        – HTTP-anrop; returnerar Map<String, dynamic>
    ↓
ApiContract       – validerar + normaliserar JSON
    ↓
Model.fromJson()  – skapar typad modell
    ↓
UI-widgets        – konsumerar endast typade modeller
```

- **UI-lagret läser aldrig rå JSON** — inga `data['key']`, inga `as Map`, inga `dynamic` i widgetar
- **ApiService** hanterar bara HTTP — ingen affärslogik eller parsing utöver `jsonDecode`
- **Modeller** äger all null-koalescering och typkonvertering
- **ApiContract** fångar inkonsistenta API-svar innan de når modellen

## Regler

1. Ny skärmkod och buggfixar måste använda typade modeller — inga `Map<String, dynamic>` direkt i `screens/`
2. Null-hantering sker i `Model.fromJson()`, inte i widgetar
3. Varje ny modell har minst ett unit-test med ett negativt fall (tom map, null-fält)
4. Auth-headers: använd alltid `_authHeaders()`, aldrig inline `'Bearer $_token'`
5. `dart format` körs av CI — formatera inte manuellt
6. Max cyklomatisk komplexitet per metod: 10

## Under migration (strangler fig)

Befintlig kod som inte rörs får behålla `Map<String, dynamic>` tills den berörs av en bugg eller feature. Ny kod och buggfixar måste använda modeller.

Temporärt tillåtet mönster — markeras alltid:
```dart
// TODO(refactor/step-N): ersätt med MediaItem när steget är klart
final Map<String, dynamic> legacyData = await api.fetchMediaDetails(id);
```

PR-reviews blockerar merge om ny `dynamic`-åtkomst läggs till i `screens/` utan TODO-markering.

## Commit-granularitet

- En commit per ny modell: `feat(models): add Episode model`
- En commit för kontraktslagret: `feat(contracts): add ApiContract`
- En commit per screen-ändring: `refactor: use MediaItem in media_details_screen`

Detta gör det möjligt att `git revert` en enskild ändring utan att kasta modellerna.

## Testmönster

```dart
// Alltid: negativt fall med tom/null-data
test('Episode.fromJson fills defaults for empty map', () {
  final ep = Episode.fromJson(const {});
  expect(ep.id, '');
  expect(ep.isWatched, false);
});

// Alltid: verifiera edge case som orsakade en känd bugg
test('Episode.fromJson accepts is_watched as bool true (not only int 1)', () {
  final ep = Episode.fromJson(const {'is_watched': true});
  expect(ep.isWatched, true);
});
```

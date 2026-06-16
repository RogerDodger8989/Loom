# Loom – Lägga till en ny feature

Följ dessa steg i ordning. Hoppa inte över modell- eller teststeget.

## 1. Definiera modellen

Skapa `frontend/lib/models/<namn>.dart` med:
- `@immutable`-klass
- Namngivna `required`-parametrar i konstruktorn
- `factory fromJson(Map<String, dynamic> json)` med null-säkra fallbacks via `?.toString()`, `int.tryParse()` etc.
- Computed getters (`isX`, `hasY`) för logik som annars skulle hamna i UI
- `copyWithX()`-metod för optimistiska uppdateringar
- `toJson()` om data skickas tillbaka till ett skärm som ännu inte migrerats (brygga)

```dart
@immutable
class MyModel {
  final String id;
  final String title;

  const MyModel({required this.id, required this.title});

  factory MyModel.fromJson(Map<String, dynamic> json) => MyModel(
    id: json['id']?.toString() ?? '',
    title: json['title']?.toString() ?? '',
  );
}
```

## 2. Validera kontraktet

I `frontend/lib/services/api_contract.dart`, lägg till ett validerings-anrop:

```dart
static Map<String, dynamic> validateMyEndpoint(dynamic raw) {
  if (raw is! Map<String, dynamic>) throw ApiContractException('...');
  _require(raw, 'id');
  _require(raw, 'title');
  return raw;
}
```

## 3. Lägg till API-metoden

I `frontend/lib/services/api.dart`:

```dart
Future<MyModel> fetchMyThing(String id) async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/my-endpoint/$id'),
    headers: _authHeaders(),   // alltid _authHeaders(), aldrig inline
  );
  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}');
  }
  final raw = ApiContract.validateMyEndpoint(jsonDecode(response.body));
  return MyModel.fromJson(raw);
}
```

## 4. Bygg UI

I `screens/` eller `widgets/`:
- Ta emot `MyModel`, inte `Map<String, dynamic>`
- Läs `.id`, `.title` — aldrig `data['id']`
- Optimistiska uppdateringar via `model.copyWithX()` + `setState`

## 5. Skriv tester

I `frontend/test/models/my_model_test.dart`:

```dart
test('fills defaults for empty map', () {
  final m = MyModel.fromJson(const {});
  expect(m.id, '');
  expect(m.title, '');
});

test('parses correctly', () {
  final m = MyModel.fromJson(const {'id': 'x', 'title': 'Test'});
  expect(m.id, 'x');
  expect(m.title, 'Test');
});
```

## 6. Kör analyzer

```bash
cd frontend
flutter analyze
```

Noll nya varningar krävs innan PR.

## 7. Öppna PR

- Branch: `feat/<kortnamn>` eller `fix/<kortnamn>`
- Max ~300 ändrade rader — dela upp om det blir mer
- CI (GitHub Actions) måste vara grön för merge
- Beskriv i PR-texten: vad ändrades och varför, inte hur

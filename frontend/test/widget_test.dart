import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loom_frontend/main.dart';
import 'package:loom_frontend/services/api.dart';
import 'package:loom_frontend/screens/login_screen.dart';
import 'package:loom_frontend/screens/dashboard_screen.dart';

void main() {
  group('LoomApp widget', () {
    testWidgets('visar LoginScreen när ingen token finns', (WidgetTester tester) async {
      final api = ApiService();

      await tester.pumpWidget(LoomApp(apiService: api, hasToken: false));
      await tester.pump();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('visar DashboardScreen när token finns', (WidgetTester tester) async {
      final api = ApiService();

      await tester.pumpWidget(LoomApp(apiService: api, hasToken: true));
      await tester.pump();

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('appen använder mörkt tema', (WidgetTester tester) async {
      final api = ApiService();

      await tester.pumpWidget(LoomApp(apiService: api, hasToken: false));
      await tester.pump();

      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
    });
  });
}

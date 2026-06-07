import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'services/api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('sv_SE');
  if (!kIsWeb) {
    await windowManager.ensureInitialized();
  }
  final apiService = ApiService();
  final hasToken = await apiService.initializeSession();
  runApp(LoomApp(apiService: apiService, hasToken: hasToken));
}

class LoomApp extends StatelessWidget {
  final ApiService apiService;
  final bool hasToken;

  const LoomApp({super.key, required this.apiService, required this.hasToken});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LOOM',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8A5BFF),
          brightness: Brightness.dark,
          primary: const Color(0xFF8A5BFF),
          surface: const Color(0xFF0A0714),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0714),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold),
          titleLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold),
        ),
      ),
      home: hasToken
          ? DashboardScreen(apiService: apiService)
          : LoginScreen(apiService: apiService),
    );
  }
}

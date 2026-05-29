import 'package:flutter/material.dart';
import 'screens/pairing_screen.dart';

void main() {
  runApp(const LoomApp());
}

class LoomApp extends StatelessWidget {
  const LoomApp({super.key});

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
          background: const Color(0xFF0A0714),
          surface: const Color(0xFF15102A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0714),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold),
          titleLarge: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.bold),
        ),
      ),
      home: const PairingScreen(),
    );
  }
}

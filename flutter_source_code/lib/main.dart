// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; //
import 'screens/splash_screen.dart'; // New import

// lib/main.dart
Future<void> main() async {
  // 1. You MUST add this line first
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Then load the environment
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("Error loading .env: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Volunteer Cleanup Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF2E7D32), //
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          primary: const Color(0xFF2E7D32),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto', //
      ),
      // Use SplashScreen as the initial route instead of AuthScreen
      home: const SplashScreen(),
    );
  }
}
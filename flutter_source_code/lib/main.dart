import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  runApp(const MyApp());
}

// Future<void> main() async {
//   // Ensure Flutter bindings are initialized
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // Load the .env file
//   await dotenv.load(fileName: ".env");
//
//   runApp(const MyApp());
// }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Community Task Force',
      // debugShowCheckedModeBanner: false,
        // darkTheme: ThemeData.dark(),
      theme: ThemeData(
        primaryColor: const Color(0xFF2E7D32),

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          primary: const Color(0xFF2E7D32),
        ),
        // darkTheme: ThemeData.dark(),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      // ⬇️ FIX: Removed 'const' here
      home: AuthScreen(),
    );
  }
}
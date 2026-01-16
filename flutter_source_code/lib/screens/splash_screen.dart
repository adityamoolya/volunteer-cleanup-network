// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import '../services/startup_service.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final StartupService _startup = StartupService();
  String _loadingText = "Connecting to environmental grid...";

  @override
  void initState() {
    super.initState();
    _handleStartup();
  }

  Future<void> _handleStartup() async {
    // 1. Wait for servers to wake up (Handling Render cold-starts)
    bool isAwake = false;
    while (!isAwake) {
      setState(() => _loadingText = "Waking up servers (this may take a minute)...");
      isAwake = await _startup.isServerAwake();
      if (!isAwake) {
        await Future.delayed(const Duration(seconds: 3)); // Wait before retrying
      }
    }

    // 2. Check if a valid session exists
    setState(() => _loadingText = "Verifying your session...");
    bool loggedIn = await _startup.validateSession();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          // Redirect based on login status
          builder: (context) => loggedIn ? const DashboardScreen() : AuthScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Replace with your app logo if you have one
            const Icon(Icons.eco, size: 80, color: Colors.white),
            const SizedBox(height: 24),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 24),
            Text(
              _loadingText,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
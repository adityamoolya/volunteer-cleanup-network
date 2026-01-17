import 'package:flutter/material.dart';
import '../services/startup_service.dart';
import 'auth_screen.dart';
import 'home_scaffold.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final StartupService _startup = StartupService();

  bool _isBackendUp = false;
  bool _isMLUp = false;

  @override
  void initState() {
    super.initState();
    _startWarmingUp();
  }

  Future<void> _startWarmingUp() async {
    // Continue polling until BOTH are up
    while (!_isBackendUp || !_isMLUp) {
      if (!_isBackendUp) {
        _isBackendUp = await _startup.checkOnlyBackend();
      }
      if (!_isMLUp) {
        _isMLUp = await _startup.checkOnlyML();
      }

      // Check if user closed the app while we were polling
      if (!mounted) return;

      setState(() {});

      if (!_isBackendUp || !_isMLUp) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    // Now that servers are up, check session persistence
    // 🔧 FIX: This should check if token exists AND is valid
    bool loggedIn = await _startup.validateSession();

    // 🔧 DEBUG: Print the result to see what's happening
    print("🔐 Session validation result: $loggedIn");

    // Final check before navigating
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => loggedIn ? const HomeScaffold() : const AuthScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.eco, size: 100, color: Color(0xFF2E7D32)),
            const SizedBox(height: 40),
            _buildStatusRow("Main Backend Server", _isBackendUp),
            const SizedBox(height: 20),
            _buildStatusRow("ML Microservice", _isMLUp),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool isUp) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: isUp
                  ? const Icon(Icons.check_circle, color: Colors.green, key: ValueKey('done'))
                  : const CircularProgressIndicator(strokeWidth: 2, key: ValueKey('loading')),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              color: isUp ? Colors.black : Colors.grey[600],
              fontWeight: isUp ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../services/startup_service.dart';
import 'auth_screen.dart';
import 'home_scaffold.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final StartupService _startup = StartupService();
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  bool _isBackendUp = false;
  bool _isMLUp = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    
    _startWarmingUp();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
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

      if (!mounted) return;

      setState(() {});

      if (!_isBackendUp || !_isMLUp) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    // Now that servers are up, check session persistence
    bool loggedIn = await _startup.validateSession();

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
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated logo
            ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF2E7D32).withOpacity(0.3),
                      const Color(0xFF4CAF50).withOpacity(0.1),
                    ],
                  ),
                ),
                child: const Icon(Icons.eco, size: 80, color: Color(0xFF4CAF50)),
              ),
            ),
            const SizedBox(height: 32),
            
            // App name
            const Text(
              "ReLeaf",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Volunteer Cleanup Network",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white54,
                letterSpacing: 1,
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Status indicators
            _buildStatusRow("Backend Server", _isBackendUp),
            const SizedBox(height: 16),
            _buildStatusRow("ML Microservice", _isMLUp),
            
            const SizedBox(height: 40),
            
            // Loading hint
            if (!_isBackendUp || !_isMLUp)
              const Text(
                "Warming up free-tier servers...\nThis may take a moment",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, bool isUp) {
    return Container(
      width: 280,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUp ? const Color(0xFF2E7D32) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: isUp
                  ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50), key: ValueKey('done'))
                  : const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                      key: ValueKey('loading'),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isUp ? Colors.white : Colors.white54,
                fontWeight: isUp ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isUp)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Ready",
                style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
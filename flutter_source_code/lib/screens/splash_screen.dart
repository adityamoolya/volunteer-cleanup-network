import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../main.dart';
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
  bool _serverUnreachable = false;
  int _retryCount = 0;
  int _tapCount = 0;

  Future<void> _showDeveloperSettings() async {
    final TextEditingController urlController = TextEditingController(
      text: AppConfig.customBackendUrl ?? dotenv.env['BACKEND_API']?.replaceAll("'", "").replaceAll('"', ""),
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Developer Mode"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Override Backend API URL:", style: TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  hintText: "http://10.0.2.2:8080",
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                const storage = FlutterSecureStorage();
                final url = urlController.text.trim();

                if (url.isEmpty) {
                  await storage.delete(key: 'custom_backend_url');
                  AppConfig.customBackendUrl = null;
                } else {
                  await storage.write(key: 'custom_backend_url', value: url);
                  AppConfig.customBackendUrl = url;
                }

                if (mounted) {
                  setState(() {
                    _tapCount = 0;
                    _retryCount = 0;
                    _serverUnreachable = false;
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text("Save & Retry"),
            )
          ],
        );
      },
    );
  }

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
    while (!_isBackendUp) {
      if (!_isBackendUp) {
        _isBackendUp = await _startup.isServerAwake();
      }

      if (!mounted) return;

      if (!_isBackendUp) {
        _retryCount++;
        if (_retryCount >= 5) {
          setState(() {
            _serverUnreachable = true;
          });
        }
        setState(() {});
        await Future.delayed(const Duration(seconds: 3));
      } else {
        setState(() {});
      }
    }

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
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated logo
            GestureDetector(
              onTap: () {
                _tapCount++;
                if (_tapCount >= 5) {
                  _showDeveloperSettings();
                  _tapCount = 0;
                }
              },
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.3),
                        AppColors.primaryLight.withOpacity(0.1),
                      ],
                    ),
                  ),
                  child: const Icon(Icons.eco, size: 80, color: AppColors.primaryLight),
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            // App name
            const Text(
              "VCN",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Volunteer Cleanup Network",
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            
            const SizedBox(height: 60),
            
            // Status indicators
            _buildStatusRow("Backend Server", _isBackendUp),
            
            const SizedBox(height: 40),
            
            if (!_isBackendUp)
              Text(
                _serverUnreachable
                    ? "Our servers are currently taking a nap.\nError Code: API_UNREACHABLE\nPlease retry closing the app."
                    : "Connecting to Server \nPowered by AWS cloud infrastructure",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _serverUnreachable ? AppColors.danger : AppColors.textTertiary,
                  fontSize: 12,
                ),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUp ? AppColors.primary : AppColors.border,
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
                  ? const Icon(Icons.check_circle, color: AppColors.primaryLight, key: ValueKey('done'))
                  : const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textSecondary,
                      key: ValueKey('loading'),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isUp ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: isUp ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isUp)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Ready",
                style: TextStyle(color: AppColors.primaryLight, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
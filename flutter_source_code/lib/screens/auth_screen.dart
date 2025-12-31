import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_scaffold.dart'; // REQUIRED: Imports the main app layout

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Service to handle API calls
  final AuthService _authService = AuthService();

  // UI State variables
  bool _isLogin = true; // Toggle between Login and Register modes
  bool _isLoading = false;
  String? _errorMessage;

  // Text Controllers
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _emailController = TextEditingController(); // Only for registration

  // App Theme Color
  final Color _primaryColor = const Color(0xFF2E7D32); // Emerald Green

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 1. Basic Validation
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = "Username and Password are required.");
      return;
    }

    if (!_isLogin && _emailController.text.isEmpty) {
      setState(() => _errorMessage = "Email is required for registration.");
      return;
    }

    // 2. Start Loading
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final email = _emailController.text.trim();

    try {
      if (_isLogin) {
        // --- LOGIN FLOW ---
        // The service throws an exception if login fails
        bool success = await _authService.login(username, password);

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Login Successful!"),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );

          // 🚀 NAVIGATION LOGIC:
          // Replaces the Auth Screen with the Home Scaffold (Dashboard + Feed)
          Navigator.pushReplacement(
              context,
              // FIX: Removed 'const' keyword here to prevent the error
              MaterialPageRoute(builder: (_) => HomeScaffold())
          );
        }
      } else {
        // --- REGISTER FLOW ---
        await _authService.register(username, email, password);

        if (mounted) {
          // If successful, switch to Login mode so they can sign in
          setState(() {
            _isLogin = true;
            _errorMessage = "Account created successfully! Please log in.";
          });
          // Clear fields
          _usernameController.clear();
          _passwordController.clear();
          _emailController.clear();
        }
      }
    } catch (e) {
      // Handle API errors (like "Incorrect password" or "Connection refused")
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      // 3. Stop Loading
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- App Logo & Title ---
              Icon(Icons.eco, size: 80, color: _primaryColor),
              const SizedBox(height: 16),
              Text(
                "ReLeaf",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin ? "Welcome Back, Hero" : "Join the Task Force",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 40),

              // --- Error Display Box ---
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade800),
                    textAlign: TextAlign.center,
                  ),
                ),

              // --- Input Fields ---
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: "Username",
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Only show Email field if Registering
              if (!_isLogin) ...[
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Email Address",
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              // --- Submit Button ---
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                )
                    : Text(
                    _isLogin ? "LOG IN" : "CREATE ACCOUNT",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                ),
              ),

              // --- Toggle Mode Button ---
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _errorMessage = null; // Clear old errors when switching
                  });
                },
                child: RichText(
                  text: TextSpan(
                    text: _isLogin ? "New here? " : "Already have an account? ",
                    style: const TextStyle(color: Colors.grey),
                    children: [
                      TextSpan(
                        text: _isLogin ? "Register now" : "Log in",
                        style: TextStyle(
                          color: _primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
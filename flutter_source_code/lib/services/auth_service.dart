// lib/services/auth_service.dart
//
// Handles all authentication flows:
//   - Email/password login  → POST /auth/login
//   - Registration           → POST /auth/register
//   - Token refresh          → POST /auth/refresh
//   - Logout                 → POST /auth/logout
//   - GitHub OAuth           → Supabase OAuth → POST /oauth/github

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService {
  static String get baseUrl => dotenv.env['BACKEND_API']?.replaceAll("'", "").replaceAll('"', "") ?? 'http://10.0.2.2:8080';
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  AuthService() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 10);

    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
    ));
  }

  // ─────────────── LOGIN (Email + Password) ───────────────
  /// Sends JSON payload to POST /auth/login.
  /// [fcmToken] is required for push notifications on APK.
  Future<bool> login(String email, String password, String? fcmToken) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
          'fcm_token': fcmToken,
        },
      );

      if (response.statusCode == 200) {
        final accessToken = response.data['access_token'];
        final refreshToken = response.data['refresh_token'];

        await _storage.write(key: 'access_token', value: accessToken);
        await _storage.write(key: 'refresh_token', value: refreshToken);

        print("✅ Login successful — tokens stored");
        return true;
      }
      return false;
    } on DioException catch (e) {
      final errorMsg = e.response?.data['detail'] ?? 'Login failed';
      throw errorMsg;
    }
  }

  // ─────────────── REGISTER ───────────────
  Future<bool> register(String username, String email, String password) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'username': username,
          'email': email,
          'password': password,
        },
      );

      return response.statusCode == 200 || response.statusCode == 201;
    } on DioException catch (e) {
      final errorMsg = e.response?.data['detail'] ?? 'Registration failed';
      throw errorMsg;
    }
  }

  // ─────────────── LOGOUT (Server-Side) ───────────────
  /// Sends the refresh token to the server to revoke it,
  /// then clears all local tokens.
  Future<void> logout() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken != null && refreshToken.isNotEmpty) {
        final accessToken = await _storage.read(key: 'access_token');
        await _dio.post(
          '/auth/logout',
          data: {'refresh_token': refreshToken},
          options: Options(
            headers: accessToken != null
                ? {'Authorization': 'Bearer $accessToken'}
                : null,
          ),
        );
        print("✅ Server-side logout successful");
      }
    } catch (e) {
      // Even if server call fails, still clear local tokens
      print("⚠️ Server logout failed (clearing locally anyway): $e");
    }

    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    print("🔓 Logged out — local tokens deleted");
  }

  // ─────────────── TOKEN REFRESH ───────────────
  /// Refreshes the access + refresh token pair.
  /// Returns true if refresh succeeded.
  Future<bool> refreshTokens() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final response = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        await _storage.write(
            key: 'access_token', value: response.data['access_token']);
        await _storage.write(
            key: 'refresh_token', value: response.data['refresh_token']);
        print("🔄 Token refresh successful");
        return true;
      }
      return false;
    } catch (e) {
      print("❌ Token refresh failed: $e");
      return false;
    }
  }

  // ─────────────── GITHUB OAUTH (via Supabase) ───────────────
  /// Opens Supabase's GitHub OAuth flow, then exchanges the Supabase JWT
  /// for our backend's access + refresh tokens via POST /oauth/github.
  Future<bool> loginWithGitHub() async {
    try {
      final supabase = Supabase.instance.client;

      // Trigger Supabase GitHub OAuth
      await supabase.auth.signInWithOAuth(
        OAuthProvider.github,
        redirectTo: 'com.vcn.app://login-callback',
      );

      // Wait for the auth state to change (user completes OAuth in browser)
      final completer = _SupabaseAuthCompleter(supabase);
      final session = await completer.waitForSession();

      if (session == null) {
        throw 'GitHub login was cancelled or failed';
      }

      // Send the Supabase access token to our backend
      final supabaseJwt = session.accessToken;

      final response = await _dio.post(
        '/oauth/github',
        data: {
          'firebase_token': supabaseJwt, // schema field name from backend
        },
      );

      if (response.statusCode == 200) {
        final accessToken = response.data['access_token'];
        final refreshToken = response.data['refresh_token'];

        await _storage.write(key: 'access_token', value: accessToken);
        await _storage.write(key: 'refresh_token', value: refreshToken);

        // Sign out of Supabase client (we use our own JWT system)
        await supabase.auth.signOut();

        print("✅ GitHub OAuth login successful");
        return true;
      }
      return false;
    } catch (e) {
      print("❌ GitHub OAuth error: $e");
      rethrow;
    }
  }

  // ─────────────── HELPERS ───────────────

  Future<String?> getAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: 'refresh_token');
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'access_token');
    final hasToken = token != null && token.isNotEmpty;
    print("🔐 isLoggedIn check: $hasToken");
    return hasToken;
  }
}

/// Helper to wait for Supabase auth state change after OAuth redirect.
class _SupabaseAuthCompleter {
  final SupabaseClient _client;

  _SupabaseAuthCompleter(this._client);

  Future<Session?> waitForSession() async {
    // If there's already a session, return it
    final existing = _client.auth.currentSession;
    if (existing != null) return existing;

    // Otherwise wait for the auth state to change
    try {
      final event = await _client.auth.onAuthStateChange
          .firstWhere((data) =>
              data.event == AuthChangeEvent.signedIn &&
              data.session != null)
          .timeout(const Duration(minutes: 2));
      return event.session;
    } catch (e) {
      print("⚠️ Timed out waiting for GitHub OAuth callback");
      return null;
    }
  }
}
// lib/services/startup_service.dart
//
// Handles server health checks and session validation on app start.
// Uses the new JWT token system with auto-refresh on 401.

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../main.dart';

class StartupService {
  final Dio _dio = Dio();
  final _storage = const FlutterSecureStorage();

  static String get backendUrl =>
      AppConfig.customBackendUrl ??
      dotenv.env['BACKEND_API']
          ?.replaceAll("'", "")
          .replaceAll('"', "")
          .trim() ??
      'https://adityamoolya.duckdns.org';
  // Polls the root endpoint to check if the server is up
  Future<bool> isServerAwake() async {
    try {
      final resp =
          await _dio.get(backendUrl).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (e) {
      print("Server awake check failed: $e, url: $backendUrl");
      return false;
    }
  }

  /// Validates the stored session by checking the access token against /users/me.
  /// If the access token is expired (401), attempts a refresh before giving up.
  Future<bool> validateSession() async {
    try {
      // 1. Check if access token exists
      String? accessToken = await _storage.read(key: 'access_token');

      if (accessToken == null || accessToken.isEmpty) {
        print("🔐 No access token found in storage");
        return false;
      }

      print("🔐 Access token found, validating with backend...");

      // 2. Validate token with backend
      final response = await _dio.get(
        '$backendUrl/users/me',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          validateStatus: (status) => status! < 500,
        ),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print("✅ Access token is valid! User: ${response.data['username']}");
        return true;
      } else if (response.statusCode == 401) {
        // Access token expired — try to refresh
        print("⚠️ Access token expired (401), attempting refresh...");
        return await _tryRefresh();
      } else {
        print("⚠️ Unexpected status code: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      // Network error or timeout — assume offline, keep token
      print("⚠️ Session validation error (might be offline): $e");

      // If we have a token but can't validate due to network issues,
      // still consider it valid. Only delete on explicit 401.
      String? token = await _storage.read(key: 'access_token');
      if (token != null && token.isNotEmpty) {
        print("⚠️ Keeping existing token despite validation error (offline mode)");
        return true;
      }

      return false;
    }
  }

  /// Attempts to refresh the token pair using the stored refresh token.
  Future<bool> _tryRefresh() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null || refreshToken.isEmpty) {
        print("❌ No refresh token — must re-login");
        await _clearTokens();
        return false;
      }

      final response = await _dio.post(
        '$backendUrl/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        await _storage.write(
            key: 'access_token', value: response.data['access_token']);
        await _storage.write(
            key: 'refresh_token', value: response.data['refresh_token']);
        print("🔄 Token refresh successful during startup");
        return true;
      } else {
        print("❌ Refresh failed with status: ${response.statusCode}");
        await _clearTokens();
        return false;
      }
    } catch (e) {
      print("❌ Refresh error: $e");
      await _clearTokens();
      return false;
    }
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}
// lib/services/startup_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StartupService {
  final Dio _dio = Dio();
  final _storage = const FlutterSecureStorage();

  final String backendUrl = dotenv.env['BACKEND_URL'] ?? '';
  final String mlUrl = dotenv.env['ML_SERVICE_URL'] ?? '';

  // Polls the root endpoints
  Future<bool> isServerAwake() async {
    try {
      final resp = await _dio.get(backendUrl).timeout(const Duration(seconds: 5));
      final mlResp = await _dio.get(mlUrl).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200 && mlResp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkOnlyBackend() async {
    try {
      final resp = await _dio.get(backendUrl).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkOnlyML() async {
    try {
      final resp = await _dio.get(mlUrl).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 🔧 FIXED: Validates the long-lived token against the user endpoint
  Future<bool> validateSession() async {
    try {
      // 1. Check if token exists
      String? token = await _storage.read(key: 'jwt_token');

      if (token == null || token.isEmpty) {
        print("🔐 No token found in storage");
        return false;
      }

      print("🔐 Token found, validating with backend...");

      // 2. Validate token with backend
      final response = await _dio.get(
        '$backendUrl/users/me',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (status) => status! < 500, // Don't throw on 401
        ),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print("✅ Token is valid! User: ${response.data['username']}");
        return true;
      } else if (response.statusCode == 401) {
        // Token expired or invalid - delete it
        print("❌ Token expired (401), deleting...");
        await _storage.delete(key: 'jwt_token');
        return false;
      } else {
        print("⚠️ Unexpected status code: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      // Network error or timeout - assume offline, keep token
      print("⚠️ Session validation error (might be offline): $e");

      // 🔧 CRITICAL FIX: If we have a token but can't validate due to network issues,
      // still consider it valid. Only delete on explicit 401.
      String? token = await _storage.read(key: 'jwt_token');
      if (token != null && token.isNotEmpty) {
        print("⚠️ Keeping existing token despite validation error (offline mode)");
        return true; // Trust the token exists
      }

      return false;
    }
  }
}
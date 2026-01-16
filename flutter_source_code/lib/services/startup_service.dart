// lib/services/startup_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StartupService {
  final Dio _dio = Dio();
  final _storage = const FlutterSecureStorage();

  // Use the established production URL
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

  // Validates the long-lived token against the user endpoint
  Future<bool> validateSession() async {
    String? token = await _storage.read(key: 'jwt_token');
    if (token == null) return false;

    try {
      final response = await _dio.get(
        '$backendUrl/users/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.statusCode == 200;
    } catch (e) {
      // If 401, the 30-day token has finally expired
      await _storage.delete(key: 'jwt_token');
      return false;
    }
  }
}
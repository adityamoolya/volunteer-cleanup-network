// lib/services/auth_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AuthService {
  static final String baseUrl = dotenv.env['BACKEND_URL'] ?? 'http://10.0.2.2:8000';

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

  // --- LOGIN ---
  Future<bool> login(String username, String password) async {
    try {
      final response = await _dio.post(
        '/auth/token',
        data: FormData.fromMap({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final token = response.data['access_token'];

        // 🔧 CRITICAL: Store the token
        await _storage.write(key: 'jwt_token', value: token);

        // 🔧 DEBUG: Verify it was stored
        final storedToken = await _storage.read(key: 'jwt_token');
        print("✅ Token stored successfully: ${storedToken?.substring(0, 20)}...");

        return true;
      }
      return false;
    } on DioException catch (e) {
      final errorMsg = e.response?.data['detail'] ?? 'Login failed';
      throw errorMsg;
    }
  }

  // --- REGISTER ---
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

  // --- LOGOUT ---
  Future<void> logout() async {
    await _storage.delete(key: 'jwt_token');
    print("🔓 Logged out - token deleted");
  }

  // --- CHECK LOGIN STATUS ---
  Future<bool> isLoggedIn() async {
    String? token = await _storage.read(key: 'jwt_token');
    final hasToken = token != null && token.isNotEmpty;
    print("🔐 isLoggedIn check: $hasToken");
    return hasToken;
  }
}
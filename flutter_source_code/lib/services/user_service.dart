import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/profile_model.dart';

class UserService {
  static const String baseUrl = 'https://env-el-rvce-production.up.railway.app';

  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  UserService() {
    _dio.options.baseUrl = baseUrl;
    // 🟢 CRITICAL: This interceptor adds the token to every request.
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'jwt_token'); // Reads token from secure storage
        if (token != null) {
          // This must match the FastAPI expectation (Bearer <token>)
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  Future<ProfileStats> getMyStats() async {
    try {
      // Endpoint requires authentication (JWT Bearer token)
      final response = await _dio.get('/users/profile/stats');
      if (response.statusCode == 200) {
        return ProfileStats.fromJson(response.data);
      }
      throw "Failed to load profile";

    } catch (e) {
      throw "Error fetching stats: $e";
    }
  }
}
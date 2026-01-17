import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/profile_model.dart';

class UserService {
  static final String baseUrl = dotenv.env['BACKEND_URL'] ?? 'http://10.0.2.2:8000';

  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  UserService() {
    _dio.options.baseUrl = baseUrl;
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'jwt_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  Future<ProfileStats> getMyStats() async {
    try {
      final response = await _dio.get('/users/profile/stats');
      if (response.statusCode == 200) {
        return ProfileStats.fromJson(response.data);
      }
      throw "Failed to load profile";

    } catch (e) {
      throw "Error fetching stats: $e";
    }
  }

  // NEW: Approve mission request
  Future<bool> approveMissionRequest(int postId) async {
    try {
      final response = await _dio.post(
        '/posts/$postId/approve',
        data: {'final_points': 50}, // Can be made dynamic
      );
      return response.statusCode == 200;
    } catch (e) {
      throw "Failed to approve: $e";
    }
  }
}
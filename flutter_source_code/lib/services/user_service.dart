import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/profile_model.dart';
import 'auth_interceptor.dart';

class UserService {
  static String get baseUrl => dotenv.env['BACKEND_API']?.replaceAll("'", "").replaceAll('"', "") ?? 'http://10.0.2.2:8080';
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  UserService() {
    _dio.options.baseUrl = baseUrl;

    // Use centralized auth interceptor for automatic token attachment + refresh
    _dio.interceptors.add(AuthInterceptor(_dio));
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

  // Approve mission request
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
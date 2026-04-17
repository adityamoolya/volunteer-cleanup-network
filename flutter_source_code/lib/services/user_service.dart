import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/profile_model.dart';
import '../models/post_model.dart';
import '../main.dart';
import 'auth_interceptor.dart';

class UserService {
  static String get baseUrl => AppConfig.customBackendUrl ?? dotenv.env['BACKEND_API']?.replaceAll("'", "").replaceAll('"', "").trim() ?? 'http://10.0.2.2:8080';
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  UserService() {
    _dio.options.baseUrl = baseUrl;
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

  /// GET /users/me — returns full user details including 'id' field
  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final response = await _dio.get('/users/me');
      if (response.statusCode == 200) {
        return response.data;
      }
      throw "Failed to load user";
    } catch (e) {
      throw "Error fetching user: $e";
    }
  }

  /// GET /users/leaderboard — returns top 10 users by points
  Future<List<UserPublic>> getLeaderboard() async {
    try {
      final response = await _dio.get('/users/leaderboard');
      if (response.statusCode == 200) {
        return (response.data as List)
            .map((x) => UserPublic.fromJson(x))
            .toList();
      }
      return [];
    } catch (e) {
      throw "Error fetching leaderboard: $e";
    }
  }

  /// DELETE /users/delete/{user_id} — deletes the user's own account
  Future<bool> deleteAccount(String userId) async {
    try {
      final response = await _dio.delete('/users/delete/$userId');
      return response.statusCode == 200;
    } on DioException catch (e) {
      if (e.response != null && e.response!.data is Map && e.response!.data['detail'] != null) {
        throw e.response!.data['detail'];
      }
      throw "Failed to delete account: ${e.message}";
    } catch (e) {
      throw "Failed to delete account: $e";
    }
  }

  /// POST /users/test-notification — sends a test push to your own device
  Future<String> testNotification() async {
    try {
      final response = await _dio.post('/users/test-notification');
      if (response.statusCode == 200) {
        return response.data['message'] ?? 'Notification sent!';
      }
      throw "Unexpected response";
    } on DioException catch (e) {
      if (e.response != null && e.response!.data is Map && e.response!.data['detail'] != null) {
        throw e.response!.data['detail'];
      }
      throw "Failed: ${e.message}";
    } catch (e) {
      throw "$e";
    }
  }
}
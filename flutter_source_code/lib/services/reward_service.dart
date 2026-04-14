// lib/services/reward_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/reward_model.dart';
import 'auth_interceptor.dart';

class RewardService {
  static String get baseUrl => dotenv.env['BACKEND_API']?.replaceAll("'", "").replaceAll('"', "") ?? 'http://10.0.2.2:8080';
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  RewardService() {
    _dio.options.baseUrl = baseUrl;
    _dio.interceptors.add(AuthInterceptor(_dio));
  }

  Future<List<Reward>> getAvailableRewards() async {
    try {
      final response = await _dio.get('/rewards/available');
      if (response.statusCode == 200) {
        return (response.data as List).map((x) => Reward.fromJson(x)).toList();
      }
      return [];
    } catch (e) {
      throw "Error fetching rewards: $e";
    }
  }

  Future<bool> redeemReward(String rewardId) async {
    try {
      final response = await _dio.post('/rewards/$rewardId/request');
      return response.statusCode == 200;
    } on DioException catch (e) {
      if (e.response != null && e.response!.data is Map && e.response!.data['detail'] != null) {
        throw e.response!.data['detail'];
      }
      throw "Failed to redeem: ${e.message}";
    } catch (e) {
      throw "Failed to redeem: $e";
    }
  }
}

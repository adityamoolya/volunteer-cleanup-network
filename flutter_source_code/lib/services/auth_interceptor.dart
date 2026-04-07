// lib/services/auth_interceptor.dart
//
// Centralized Dio interceptor that:
//  1. Attaches the stored access_token to every outgoing request
//  2. On a 401 response, automatically tries to refresh via /auth/refresh
//  3. If refresh succeeds  → retries the original request with the new token
//  4. If refresh fails     → clears tokens and broadcasts a "force logout" event

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthInterceptor extends QueuedInterceptor {
  final Dio _dio; // original Dio instance (for retrying)
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Stream that any screen can listen to for forced-logout events.
  /// When a value lands here, the user should be sent back to AuthScreen.
  static final StreamController<void> onForceLogout =
      StreamController<void>.broadcast();

  AuthInterceptor(this._dio);

  // ─── Attach bearer token to every request ───
  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: 'access_token');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  // ─── Intercept 401 → try refresh → retry or force-logout ───
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Only handle 401 Unauthorized
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Don't try to refresh if the failing request was itself a refresh/login
    final path = err.requestOptions.path;
    if (path.contains('/auth/refresh') ||
        path.contains('/auth/login') ||
        path.contains('/auth/register') ||
        path.contains('/oauth/')) {
      return handler.next(err);
    }

    // Attempt to refresh
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) {
      await _clearAndLogout();
      return handler.next(err);
    }

    try {
      // Use a fresh Dio to avoid interceptor loops
      final freshDio = Dio(BaseOptions(baseUrl: _dio.options.baseUrl));
      final response = await freshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final newAccess = response.data['access_token'];
        final newRefresh = response.data['refresh_token'];

        await _storage.write(key: 'access_token', value: newAccess);
        await _storage.write(key: 'refresh_token', value: newRefresh);

        // print("🔄 Token refreshed successfully!");

        // Retry the original request with the new token
        final retryOptions = err.requestOptions;
        retryOptions.headers['Authorization'] = 'Bearer $newAccess';

        final retryResponse = await _dio.fetch(retryOptions);
        return handler.resolve(retryResponse);
      } else {
        await _clearAndLogout();
        return handler.next(err);
      }
    } catch (e) {
      // print("❌ Token refresh failed: $e");
      await _clearAndLogout();
      return handler.next(err);
    }
  }

  Future<void> _clearAndLogout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
    onForceLogout.add(null); // broadcast to listeners
    // print("🔒 Force logout — tokens cleared");
  }
}

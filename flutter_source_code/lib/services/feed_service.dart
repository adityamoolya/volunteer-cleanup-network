import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/post_model.dart';

class FeedService {
  // 🔧 UPDATED TO MATCH DEPLOYED BACKEND
  static const String baseUrl = 'https://env-el-backend-api.onrender.com';
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  FeedService() {
    _dio.options.baseUrl = baseUrl;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'jwt_token');
          print("🔍 [${options.path}] Token exists: ${token != null}");
          if (token != null) {
            print("🔑 Adding token: ${token.substring(0, 30)}...");
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            print("❌ NO TOKEN FOUND IN STORAGE!");
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          print("❌ Request failed:");
          print("   Path: ${error.requestOptions.path}");
          print("   Status: ${error.response?.statusCode}");
          print("   Headers sent: ${error.requestOptions.headers}");
          return handler.next(error);
        },
      ),
    );
  }

  // --- 1. GET FEED ---
  Future<List<Post>> getFeed({int skip = 0, int limit = 10}) async {
    try {
      final response = await _dio.get(
        '/posts/',
        queryParameters: {'skip': skip, 'limit': limit},
      );

      if (response.statusCode == 200) {
        return (response.data as List)
            .map((x) => Post.fromJson(x))
            .toList();
      }
      return [];
    } catch (e) {
      print("Feed error: $e");
      return [];
    }
  }

  // --- 2. UPLOAD IMAGE ---
  Future<Map<String, String>?> uploadImage(File file) async {
    try {
      String fileName = file.path.split('/').last;

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(
          file.path,
          filename: fileName,
        ),
      });

      final response = await _dio.post('/images/upload/', data: formData);

      if (response.statusCode == 200) {
        return {
          "url": response.data['url'],
          "public_id": response.data['public_id'],
        };
      }
      return null;
    } catch (e) {
      print("Upload error: $e");
      throw "Image upload failed";
    }
  }

  // --- 3. CREATE POST ---
  Future<bool> createPost(
      String imageUrl,
      String publicId,
      String caption,
      double lat,
      double lng,
      ) async {
    try {
      final response = await _dio.post(
        '/posts/',
        data: {
          "image_url": imageUrl,
          "image_public_id": publicId,  // Backend schema requires this
          "caption": caption,
          "latitude": lat,
          "longitude": lng,
        },
      );
      return response.statusCode == 201;
    } catch (e) {
      print("Create post error: $e");
      throw "Failed to create report";
    }
  }

  // --- 4. START WORK (Clock In) ---
  Future<bool> startWork(int postId, String startImageUrl) async {
    try {
      final response = await _dio.post(
        '/posts/$postId/start_work',
        data: {'start_image_url': startImageUrl},
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Start work error: $e");
      throw "Failed to clock in";
    }
  }

  // --- 5. SUBMIT PROOF (Clock Out) ---
  Future<bool> submitCleanupProof(int postId, String endImageUrl) async {
    try {
      final response = await _dio.post(
        '/posts/$postId/submit_proof',
        data: {'end_image_url': endImageUrl},
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Submit proof error: $e");
      throw "Failed to submit completion proof";
    }
  }

  // --- 6. APPROVE REQUEST ---
  Future<bool> approveRequest(int postId) async {
    try {
      final response = await _dio.post(
        '/posts/$postId/approve',
        data: {'final_points': 50}, // You can make this dynamic
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Approve error: $e");
      throw "Failed to approve request";
    }
  }

  // --- 7. ADD COMMENT ---
  Future<bool> postComment(int postId, String content) async {
    try {
      final response = await _dio.post(
        '/comments/',
        queryParameters: {'post_id': postId},
        data: {'content': content},
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Comment error: $e");
      throw "Failed to post comment";
    }
  }
}
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/post_model.dart';

class FeedService {
  static final String baseUrl = dotenv.env['BACKEND_URL'] ?? 'http://10.0.2.2:8000';
  final Dio _dio = Dio();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  FeedService() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 15);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: 'jwt_token');
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
            print("🔑 [${options.path}] Token attached");
          } else {
            print("⚠️ [${options.path}] No token found!");
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          print("❌ API Error:");
          print("   Path: ${error.requestOptions.path}");
          print("   Status: ${error.response?.statusCode}");
          print("   Data: ${error.response?.data}");
          return handler.next(error);
        },
      ),
    );
  }

  // ==================== PHASE 0: IMAGE UPLOAD ====================

  Future<Map<String, String>?> uploadImage(File file) async {
    try {
      print("📤 Uploading image to Cloudinary...");
      String fileName = file.path.split('/').last;

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(
          file.path,
          filename: fileName,
        ),
      });

      final response = await _dio.post('/images/upload/', data: formData);

      if (response.statusCode == 200) {
        print("✅ Image uploaded successfully!");
        print("   URL: ${response.data['url']}");
        print("   Public ID: ${response.data['public_id']}");

        return {
          "url": response.data['url'],
          "public_id": response.data['public_id'],
        };
      }
      return null;
    } catch (e) {
      print("❌ Upload error: $e");
      throw "Image upload failed: $e";
    }
  }

  // ==================== PHASE 1: CREATE POST (AUTHOR) ====================

  Future<bool> createPost(
      String imageUrl,
      String publicId,
      String caption,
      double lat,
      double lng,
      ) async {
    try {
      print("📝 Creating post...");
      print("   Image URL: $imageUrl");
      print("   Public ID: $publicId");
      print("   Caption: $caption");
      print("   Location: ($lat, $lng)");

      final response = await _dio.post(
        '/posts/',
        data: {
          "image_url": imageUrl,
          "image_public_id": publicId,
          "caption": caption,
          "latitude": lat,
          "longitude": lng,
        },
      );

      if (response.statusCode == 201) {
        print("✅ Post created successfully!");
        return true;
      }

      print("⚠️ Unexpected status: ${response.statusCode}");
      return false;
    } on DioException catch (e) {
      print("❌ Create post error:");
      print("   Status: ${e.response?.statusCode}");
      print("   Response: ${e.response?.data}");

      if (e.response?.statusCode == 422) {
        final errors = e.response?.data;
        print("   Validation errors: $errors");
        throw "Validation failed: ${errors['detail'] ?? 'Check all required fields'}";
      }

      throw "Failed to create post: ${e.message}";
    } catch (e) {
      print("❌ Unexpected error: $e");
      throw "Failed to create post: $e";
    }
  }

  // ==================== GET FEED (DISCOVERY REEL) ====================

  Future<List<Post>> getFeed({int skip = 0, int limit = 20}) async {
    try {
      print("🔄 Fetching feed (skip: $skip, limit: $limit)...");

      final response = await _dio.get(
        '/posts/',
        queryParameters: {'skip': skip, 'limit': limit},
      );

      if (response.statusCode == 200) {
        final List<Post> posts = (response.data as List)
            .map((x) => Post.fromJson(x))
            .toList();

        print("✅ Fetched ${posts.length} posts");
        return posts;
      }

      print("⚠️ Feed fetch returned status: ${response.statusCode}");
      return [];
    } catch (e) {
      print("❌ Feed error: $e");
      return [];
    }
  }

  // ==================== PHASE 2: START WORK (VOLUNTEER CLOCK IN) ====================

  Future<bool> startWork(int postId, String startImageUrl) async {
    try {
      print("⏰ Clocking in to post $postId...");
      print("   Start image: $startImageUrl");

      final response = await _dio.post(
        '/posts/$postId/start_work',
        data: {'start_image_url': startImageUrl},
      );

      if (response.statusCode == 200) {
        print("✅ Successfully clocked in!");
        return true;
      }

      print("⚠️ Clock in returned status: ${response.statusCode}");
      return false;
    } on DioException catch (e) {
      print("❌ Clock in error:");
      print("   Status: ${e.response?.statusCode}");
      print("   Message: ${e.response?.data}");

      if (e.response?.statusCode == 400) {
        throw e.response?.data['detail'] ?? "Task is not available";
      }

      throw "Failed to clock in: ${e.message}";
    } catch (e) {
      print("❌ Unexpected clock in error: $e");
      throw "Failed to clock in: $e";
    }
  }

  // ==================== PHASE 3: SUBMIT PROOF (VOLUNTEER CLOCK OUT) ====================

  Future<bool> submitCleanupProof(int postId, String endImageUrl) async {
    try {
      print("✅ Submitting cleanup proof for post $postId...");
      print("   End image: $endImageUrl");

      final response = await _dio.post(
        '/posts/$postId/submit_proof',
        data: {'end_image_url': endImageUrl},
      );

      if (response.statusCode == 200) {
        print("✅ Proof submitted successfully!");
        return true;
      }

      print("⚠️ Submit proof returned status: ${response.statusCode}");
      return false;
    } on DioException catch (e) {
      print("❌ Submit proof error:");
      print("   Status: ${e.response?.statusCode}");
      print("   Message: ${e.response?.data}");

      if (e.response?.statusCode == 403) {
        throw "You are not the volunteer for this task";
      } else if (e.response?.statusCode == 400) {
        throw e.response?.data['detail'] ?? "Task is not in progress";
      }

      throw "Failed to submit proof: ${e.message}";
    } catch (e) {
      print("❌ Unexpected submit proof error: $e");
      throw "Failed to submit completion proof: $e";
    }
  }

  // ==================== PHASE 4: APPROVE REQUEST (AUTHOR CLOSES MISSION) ====================

  Future<bool> approveRequest(int postId, {int finalPoints = 50}) async {
    try {
      print("👍 Approving post $postId with $finalPoints points...");

      final response = await _dio.post(
        '/posts/$postId/approve',
        data: {'final_points': finalPoints},
      );

      if (response.statusCode == 200) {
        print("✅ Request approved and closed!");
        return true;
      }

      print("⚠️ Approve returned status: ${response.statusCode}");
      return false;
    } on DioException catch (e) {
      print("❌ Approve error:");
      print("   Status: ${e.response?.statusCode}");
      print("   Message: ${e.response?.data}");

      if (e.response?.statusCode == 403) {
        throw "Only the author can approve this request";
      } else if (e.response?.statusCode == 400) {
        throw e.response?.data['detail'] ?? "Task is not pending approval";
      }

      throw "Failed to approve: ${e.message}";
    } catch (e) {
      print("❌ Unexpected approve error: $e");
      throw "Failed to approve request: $e";
    }
  }

  // ==================== COMMENTS ====================

  Future<bool> postComment(int postId, String content) async {
    try {
      print("💬 Posting comment to post $postId...");

      final response = await _dio.post(
        '/comments/',
        queryParameters: {'post_id': postId},
        data: {'content': content},
      );

      if (response.statusCode == 200) {
        print("✅ Comment posted!");
        return true;
      }

      print("⚠️ Comment post returned status: ${response.statusCode}");
      return false;
    } catch (e) {
      print("❌ Comment error: $e");
      throw "Failed to post comment: $e";
    }
  }

  // ==================== AUTHOR POST UPDATE ====================

  Future<bool> updatePost(
      int postId, {
        String? predictedClass,
        int? points,
        String? caption,
      }) async {
    try {
      print("✏️ Updating post $postId...");

      final Map<String, dynamic> data = {};
      if (predictedClass != null) data['predicted_class'] = predictedClass;
      if (points != null) data['points'] = points;
      if (caption != null) data['caption'] = caption;

      final response = await _dio.patch('/posts/$postId', data: data);

      if (response.statusCode == 200) {
        print("✅ Post updated!");
        return true;
      }

      print("⚠️ Update returned status: ${response.statusCode}");
      return false;
    } on DioException catch (e) {
      print("❌ Update error:");
      print("   Status: ${e.response?.statusCode}");
      print("   Message: ${e.response?.data}");

      if (e.response?.statusCode == 403) {
        throw "Not authorized to edit this post";
      } else if (e.response?.statusCode == 400) {
        throw e.response?.data['detail'] ?? "Cannot edit this post";
      }

      throw "Failed to update: ${e.message}";
    } catch (e) {
      print("❌ Unexpected update error: $e");
      throw "Failed to update post: $e";
    }
  }
}
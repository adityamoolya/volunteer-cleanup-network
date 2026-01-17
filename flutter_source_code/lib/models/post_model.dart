import 'package:flutter/material.dart';

// ==================== USER PUBLIC ====================

class UserPublic {
  final String username;
  final int points;

  UserPublic({required this.username, required this.points});

  factory UserPublic.fromJson(Map<String, dynamic> json) {
    return UserPublic(
      username: json['username'] ?? 'Unknown',
      points: json['points'] ?? 0,
    );
  }
}

// ==================== COMMENT MODEL ====================

class Comment {
  final int id;
  final String content;
  final UserPublic? author;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.content,
    this.author,
    required this.createdAt,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'],
      content: json['content'],
      author: json['author'] != null
          ? UserPublic.fromJson(json['author'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}

// ==================== POST MODEL (COMPLETE MISSION) ====================

class Post {
  // Basic Info (Phase 1: Author Creates)
  final int id;
  final String imageUrl;
  final String imagePublicId;
  final String? caption;
  final double latitude;
  final double longitude;
  final String status;
  final UserPublic? author;
  final DateTime createdAt;

  // ML Classification Results
  final String? predictedClass;
  final int points;
  final int? verifiedPoints; // ML verification of volunteer's "before" photo

  // Phase 2: Volunteer Clock In
  final int? volunteerId;
  final UserPublic? volunteer;
  final String? startImageUrl; // "Before" photo
  final DateTime? volunteerStartTimestamp;

  // Phase 3: Volunteer Clock Out
  final String? endImageUrl; // "After" photo
  final DateTime? volunteerEndTimestamp;
  final int? cleanupDurationMinutes;

  // Phase 4: Author Approval (Legacy field)
  final String? proofImageUrl;
  final int? resolvedById;
  final UserPublic? resolvedBy;

  // Social Features
  final List<Comment> comments;
  final List<dynamic> likes;

  Post({
    required this.id,
    required this.imageUrl,
    required this.imagePublicId,
    this.caption,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.author,
    required this.createdAt,
    this.predictedClass,
    required this.points,
    this.verifiedPoints,
    this.volunteerId,
    this.volunteer,
    this.startImageUrl,
    this.volunteerStartTimestamp,
    this.endImageUrl,
    this.volunteerEndTimestamp,
    this.cleanupDurationMinutes,
    this.proofImageUrl,
    this.resolvedById,
    this.resolvedBy,
    required this.comments,
    required this.likes,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      // Basic Info
      id: json['id'],
      imageUrl: json['image_url'] ?? '',
      imagePublicId: json['image_public_id'] ?? '',
      caption: json['caption'],
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      status: json['status'] ?? 'open',
      author: json['author'] != null
          ? UserPublic.fromJson(json['author'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),

      // ML Results
      predictedClass: json['predicted_class'],
      points: json['points'] ?? 0,
      verifiedPoints: json['verified_points'],

      // Volunteer Info (Phase 2-3)
      volunteerId: json['volunteer_id'],
      volunteer: json['volunteer'] != null
          ? UserPublic.fromJson(json['volunteer'])
          : null,
      startImageUrl: json['start_image_url'],
      volunteerStartTimestamp: json['volunteer_start_timestamp'] != null
          ? DateTime.parse(json['volunteer_start_timestamp'])
          : null,
      endImageUrl: json['end_image_url'],
      volunteerEndTimestamp: json['volunteer_end_timestamp'] != null
          ? DateTime.parse(json['volunteer_end_timestamp'])
          : null,
      cleanupDurationMinutes: json['cleanup_duration_minutes'],

      // Legacy fields
      proofImageUrl: json['proof_image_url'],
      resolvedById: json['resolved_by_id'],
      resolvedBy: json['resolved_by'] != null
          ? UserPublic.fromJson(json['resolved_by'])
          : null,

      // Social
      comments: (json['comments'] as List?)
          ?.map((x) => Comment.fromJson(x))
          .toList() ??
          [],
      likes: (json['likes'] as List?) ?? [],
    );
  }

  // ==================== HELPER METHODS ====================

  bool get isOpen => status.toLowerCase() == 'open';
  bool get isInProgress => status.toLowerCase() == 'in_progress';
  bool get isPendingApproval => status.toLowerCase() == 'pending_approval' || status.toLowerCase() == 'pending';
  bool get isCompleted => status.toLowerCase() == 'completed';
  bool get isCancelled => status.toLowerCase() == 'cancelled';

  bool get isAnalysing => predictedClass?.toLowerCase() == 'analysing';
  bool get hasMLError => predictedClass?.toLowerCase() == 'error';

  String get statusDisplayName {
    switch (status.toLowerCase()) {
      case 'open':
        return 'Available';
      case 'in_progress':
        return 'In Progress';
      case 'pending_approval':
      case 'pending':
        return 'Pending Review';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'pending_approval':
      case 'pending':
        return Colors.amber;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData get statusIcon {
    switch (status.toLowerCase()) {
      case 'open':
        return Icons.error_outline;
      case 'in_progress':
        return Icons.construction;
      case 'pending_approval':
      case 'pending':
        return Icons.hourglass_top;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  String get formattedDuration {
    if (cleanupDurationMinutes == null) return 'N/A';

    final hours = cleanupDurationMinutes! ~/ 60;
    final mins = cleanupDurationMinutes! % 60;

    if (hours > 0) {
      return '${hours}h ${mins}m';
    } else {
      return '${mins}m';
    }
  }

  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
    }
  }

  // Check if current user can perform actions
  bool canClockIn(String? currentUsername) {
    return isOpen && author?.username != currentUsername;
  }

  bool canClockOut(String? currentUsername) {
    return isInProgress && volunteer?.username == currentUsername;
  }

  bool canApprove(String? currentUsername) {
    return isPendingApproval && author?.username == currentUsername;
  }

  bool canEdit(String? currentUsername) {
    return isOpen && author?.username == currentUsername;
  }
}
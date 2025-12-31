import 'package:flutter/material.dart';

// ------------------ USER PUBLIC ------------------

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

// ------------------ COMMENT MODEL ------------------

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

// ------------------ POST MODEL ------------------

class Post {
  final int id;
  final String imageUrl;
  final String? caption;
  final double latitude;
  final double longitude;
  final String status;
  final UserPublic? author;
  final String? proofImageUrl;
  final UserPublic? resolvedBy;
  final DateTime createdAt;

  // Comment list
  final List<Comment> comments;

  Post({
    required this.id,
    required this.imageUrl,
    this.caption,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.author,
    this.proofImageUrl,
    this.resolvedBy,
    required this.createdAt,
    required this.comments,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'],
      imageUrl: json['image_url'] ?? '',
      caption: json['caption'],
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      status: json['status'] ?? 'open',
      author: json['author'] != null
          ? UserPublic.fromJson(json['author'])
          : null,
      proofImageUrl: json['proof_image_url'],
      resolvedBy: json['resolved_by'] != null
          ? UserPublic.fromJson(json['resolved_by'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),

      // map list of comments
      comments: (json['comments'] as List?)
          ?.map((x) => Comment.fromJson(x))
          .toList() ??
          [],
    );
  }
}

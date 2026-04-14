// lib/models/reward_model.dart
class Reward {
  final String id;
  final String name;
  final String description;
  final int costInPoints;
  final int stock;
  // Future-proof: backend can send image URL when ready
  // For now, we generate a placeholder based on the reward name
  final String? imageUrl;

  Reward({
    required this.id,
    required this.name,
    required this.description,
    required this.costInPoints,
    required this.stock,
    this.imageUrl,
  });

  factory Reward.fromJson(Map<String, dynamic> json) {
    return Reward(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      costInPoints: json['cost_in_points'],
      stock: json['stock'],
      imageUrl: json['image_url'], // null until backend supports it
    );
  }

  /// Returns a coupon emoji/icon identifier based on the reward name
  String get couponIcon {
    final lower = name.toLowerCase();
    if (lower.contains('coffee') || lower.contains('cafe')) return '☕';
    if (lower.contains('food') || lower.contains('meal') || lower.contains('restaurant')) return '🍽️';
    if (lower.contains('movie') || lower.contains('cinema') || lower.contains('film')) return '🎬';
    if (lower.contains('book') || lower.contains('read')) return '📚';
    if (lower.contains('shirt') || lower.contains('merch') || lower.contains('cloth')) return '👕';
    if (lower.contains('plant') || lower.contains('tree') || lower.contains('seed')) return '🌱';
    if (lower.contains('gift') || lower.contains('voucher') || lower.contains('card')) return '🎁';
    if (lower.contains('water') || lower.contains('bottle')) return '💧';
    if (lower.contains('bag') || lower.contains('tote')) return '👜';
    return '🏆';
  }
}

class RedemptionRequest {
  final String id;
  final String status;
  final DateTime createdAt;
  final Reward? reward;

  RedemptionRequest({
    required this.id,
    required this.status,
    required this.createdAt,
    this.reward,
  });

  factory RedemptionRequest.fromJson(Map<String, dynamic> json) {
    return RedemptionRequest(
      id: json['id'],
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
      reward: json['reward'] != null ? Reward.fromJson(json['reward']) : null,
    );
  }
}

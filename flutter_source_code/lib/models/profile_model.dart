import 'post_model.dart';
import 'reward_model.dart';

class ProfileStats {
  final String username;
  final int points;
  final int createdCount;
  final int solvedCount;
  final List<Post> myRequests;
  final List<Post> myContributions;
  final List<RedemptionRequest> myRewards;

  ProfileStats({
    required this.username,
    required this.points,
    required this.createdCount,
    required this.solvedCount,
    required this.myRequests,
    required this.myContributions,
    required this.myRewards,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) {
    return ProfileStats(
      username: json['user']['username'] ?? 'Unknown',
      points: json['user']['points'] ?? 0,
      createdCount: json['counts']['created'] ?? 0,
      solvedCount: json['counts']['solved'] ?? 0,
      myRequests: (json['my_requests'] as List?)
          ?.map((x) => Post.fromJson(x))
          .toList() ?? [],
      myContributions: (json['my_contributions'] as List?)
          ?.map((x) => Post.fromJson(x))
          .toList() ?? [],
      myRewards: (json['my_rewards'] as List?)
          ?.map((x) => RedemptionRequest.fromJson(x))
          .toList() ?? [],
    );
  }
}
// lib/screens/leaderboard_screen.dart
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/post_model.dart';
import '../services/user_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final UserService _userService = UserService();
  List<UserPublic> _leaders = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUsername;

  // ─── In-memory cache ───
  static List<UserPublic>? _cachedLeaders;
  static String? _cachedUsername;
  static DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool get _isCacheValid =>
      _cachedLeaders != null &&
      _lastFetchTime != null &&
      DateTime.now().difference(_lastFetchTime!) < _cacheDuration;

  Future<void> _loadData({bool forceRefresh = false}) async {
    // Use cache if valid
    if (!forceRefresh && _isCacheValid) {
      setState(() {
        _leaders = _cachedLeaders!;
        _currentUsername = _cachedUsername;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = _leaders.isEmpty;
      _errorMessage = null;
    });
    try {
      final leaders = await _userService.getLeaderboard();
      final stats = await _userService.getMyStats();
      if (mounted) {
        setState(() {
          _leaders = leaders;
          _currentUsername = stats.username;
          _cachedLeaders = leaders;
          _cachedUsername = stats.username;
          _lastFetchTime = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "$e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.leaderboard, color: AppColors.primaryLight),
            SizedBox(width: 12),
            Text("Leaderboard", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(forceRefresh: true),
            tooltip: "Refresh",
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primaryLight),
                  const SizedBox(height: 16),
                  Text("Loading leaderboard...", style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: AppColors.textTertiary, size: 60),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadData,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text("Retry", style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadData(forceRefresh: true),
                  color: AppColors.primaryLight,
                  backgroundColor: AppColors.surface,
                  child: _leaders.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.6,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.emoji_events_outlined, size: 80, color: AppColors.textTertiary),
                                    SizedBox(height: 24),
                                    Text("No leaders yet", style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 8),
                                    Text("Be the first to earn points!", style: TextStyle(color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : CustomScrollView(
                          slivers: [
                            // Top 3 podium
                            if (_leaders.length >= 3)
                              SliverToBoxAdapter(
                                child: _buildPodium(),
                              ),

                            // Remaining entries
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final startIndex = _leaders.length >= 3 ? 3 : 0;
                                    final actualIndex = startIndex + index;
                                    if (actualIndex >= _leaders.length) return null;
                                    return _buildLeaderRow(actualIndex);
                                  },
                                  childCount: _leaders.length >= 3 ? _leaders.length - 3 : _leaders.length,
                                ),
                              ),
                            ),

                            const SliverToBoxAdapter(child: SizedBox(height: 100)),
                          ],
                        ),
                ),
    );
  }

  Widget _buildPodium() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.surface,
            AppColors.background,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd place
          if (_leaders.length > 1)
            _buildPodiumEntry(_leaders[1], 2, 90),
          const SizedBox(width: 12),
          // 1st place
          _buildPodiumEntry(_leaders[0], 1, 120),
          const SizedBox(width: 12),
          // 3rd place
          if (_leaders.length > 2)
            _buildPodiumEntry(_leaders[2], 3, 70),
        ],
      ),
    );
  }

  Widget _buildPodiumEntry(UserPublic user, int rank, double height) {
    final isMe = user.username == _currentUsername;
    final rankColors = {
      1: const Color(0xFFFFD700), // Gold
      2: const Color(0xFFC0C0C0), // Silver
      3: const Color(0xFFCD7F32), // Bronze
    };
    final rankEmojis = {1: '👑', 2: '🥈', 3: '🥉'};
    final color = rankColors[rank]!;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rankEmojis[rank]!, style: TextStyle(fontSize: rank == 1 ? 32 : 24)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: rank == 1 ? 16 : 8,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: rank == 1 ? 32 : 24,
              backgroundColor: isMe ? AppColors.primary.withOpacity(0.3) : AppColors.surfaceLight,
              child: Text(
                user.username[0].toUpperCase(),
                style: TextStyle(
                  fontSize: rank == 1 ? 24 : 18,
                  fontWeight: FontWeight.bold,
                  color: isMe ? AppColors.primaryLight : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isMe ? "You" : "@${user.username}",
            style: TextStyle(
              color: isMe ? AppColors.primaryLight : AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Podium bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            height: height,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withOpacity(0.3),
                  color.withOpacity(0.1),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "#$rank",
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: rank == 1 ? 24 : 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "${user.points} pts",
                      style: const TextStyle(
                        color: AppColors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderRow(int index) {
    final user = _leaders[index];
    final isMe = user.username == _currentUsername;
    final rank = index + 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMe ? AppColors.primary.withOpacity(0.1) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? AppColors.primary.withOpacity(0.4) : AppColors.border.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // Rank number
          SizedBox(
            width: 36,
            child: Text(
              "#$rank",
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: isMe ? AppColors.primary.withOpacity(0.3) : AppColors.surfaceLight,
            child: Text(
              user.username[0].toUpperCase(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isMe ? AppColors.primaryLight : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Text(
              isMe ? "You (@${user.username})" : "@${user.username}",
              style: TextStyle(
                color: isMe ? AppColors.primaryLight : AppColors.textPrimary,
                fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Points
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "${user.points} pts",
              style: const TextStyle(
                color: AppColors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

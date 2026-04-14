// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../services/reward_service.dart';
import '../models/profile_model.dart';
import '../models/reward_model.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  bool _isLoading = true;
  ProfileStats? _stats;
  String? _errorMessage;
  List<Reward> _availableRewards = [];
  bool _loadingRewards = false;
  bool _showRedemptionBanner = false;

  // ─── In-memory cache ───
  static ProfileStats? _cachedStats;
  static List<Reward>? _cachedRewards;
  static DateTime? _lastFetchTime;
  static const _cacheDuration = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  bool get _isCacheValid =>
      _cachedStats != null &&
      _lastFetchTime != null &&
      DateTime.now().difference(_lastFetchTime!) < _cacheDuration;

  Future<void> _loadProfile({bool forceRefresh = false}) async {
    // Use cache if valid and not forced
    if (!forceRefresh && _isCacheValid) {
      setState(() {
        _stats = _cachedStats;
        _availableRewards = _cachedRewards ?? [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = _stats == null;
      _errorMessage = null;
    });
    try {
      final stats = await _userService.getMyStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _cachedStats = stats;
          _isLoading = false;
        });
      }
      // Load available rewards in background
      _loadAvailableRewards();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "$e";
        });
      }
    }
  }

  Future<void> _loadAvailableRewards() async {
    setState(() => _loadingRewards = true);
    try {
      final rewards = await RewardService().getAvailableRewards();
      if (mounted) {
        setState(() {
          _availableRewards = rewards;
          _cachedRewards = rewards;
          _lastFetchTime = DateTime.now();
          _loadingRewards = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingRewards = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Logout", style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          "Are you sure you want to logout?",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService().logout();
      if (mounted) {
        // Clear cache on logout
        _cachedStats = null;
        _cachedRewards = null;
        _lastFetchTime = null;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            SizedBox(width: 12),
            Text("Delete Account", style: TextStyle(color: AppColors.danger)),
          ],
        ),
        content: const Text(
          "This action is permanent and cannot be undone. All your data, posts, and points will be lost.",
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Delete Forever", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Double confirm
    final reallyConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Are you absolutely sure?", style: TextStyle(color: AppColors.textPrimary)),
        content: const Text("Type in your mind: this cannot be reversed.", style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Go Back"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Yes, Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (reallyConfirmed != true) return;

    try {
      final user = await _userService.getCurrentUser();
      final userId = user['id'];
      await _userService.deleteAccount(userId);
      _cachedStats = null;
      _cachedRewards = null;
      _lastFetchTime = null;
      await AuthService().logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e"), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primaryLight),
              SizedBox(height: 16),
              Text("Loading profile...", style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null || _stats == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: AppColors.textTertiary),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? "Failed to load profile",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _loadProfile(forceRefresh: true),
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text("Retry", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final completedMissions = _stats!.myContributions
        .where((p) => p.status.toUpperCase() == 'COMPLETED')
        .toList();
    final myReportsSolved = _stats!.myRequests
        .where((p) => p.status.toUpperCase() == 'COMPLETED')
        .toList();

    int verifiedImpactPoints = _stats!.points;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => _loadProfile(forceRefresh: true),
        color: AppColors.primaryLight,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
          slivers: [
            // ═══════════ PROFILE HEADER ═══════════
            SliverToBoxAdapter(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 60, bottom: 30, left: 20, right: 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.surface, AppColors.background],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  children: [
                    // Settings row
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.logout, color: AppColors.textSecondary),
                          onPressed: _handleLogout,
                          tooltip: "Logout",
                        ),
                      ),
                    ),
                    
                    // Avatar
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: AppColors.background,
                        child: Text(
                          _stats!.username[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 40,
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Username
                    Text(
                      "@${_stats!.username}",
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Verified Points Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "$verifiedImpactPoints POINTS",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ═══════════ REDEMPTION SUCCESS BANNER ═══════════
            if (_showRedemptionBanner)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryLight.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mark_email_read, color: AppColors.primaryLight, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Coupon will be sent to your email after admin approval",
                          style: TextStyle(color: AppColors.primaryLight, fontSize: 13),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showRedemptionBanner = false),
                        child: const Icon(Icons.close, color: AppColors.textTertiary, size: 18),
                      ),
                    ],
                  ),
                ),
              ),

            // ═══════════ IMPACT STATS ═══════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "ENVIRONMENTAL IMPACT",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textTertiary,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _impactCard(Icons.cleaning_services, "Cleanups", completedMissions.length.toString(), AppColors.primaryLight),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _impactCard(Icons.report, "Reports", _stats!.createdCount.toString(), AppColors.info),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _impactCard(Icons.check_circle, "Resolved", myReportsSolved.length.toString(), Colors.orange),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ═══════════ AVAILABLE COUPONS (only from backend) ═══════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_offer, color: AppColors.amber, size: 20),
                        const SizedBox(width: 10),
                        const Text(
                          "AVAILABLE COUPONS",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        if (_loadingRewards)
                          const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.amber),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Redeem your points for rewards",
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Available rewards — ONLY shows backend-sourced rewards
            SliverToBoxAdapter(
              child: _loadingRewards
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(color: AppColors.primaryLight),
                        ),
                      ),
                    )
                  : _availableRewards.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border.withOpacity(0.3)),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.redeem, size: 40, color: AppColors.textTertiary),
                                SizedBox(height: 12),
                                Text(
                                  "No rewards available right now",
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Earn more points or check back later!",
                                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : SizedBox(
                          height: 210,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _availableRewards.length,
                            itemBuilder: (context, index) {
                              final reward = _availableRewards[index];
                              return _buildCouponCard(reward);
                            },
                          ),
                        ),
            ),

            // ═══════════ MY COUPONS (Redemption History) ═══════════
            if (_stats!.myRewards.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                  child: Row(
                    children: [
                      const Icon(Icons.confirmation_number, color: AppColors.primaryLight, size: 20),
                      const SizedBox(width: 10),
                      const Text(
                        "MY COUPONS",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "${_stats!.myRewards.length} requested",
                          style: const TextStyle(color: AppColors.primaryLight, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final req = _stats!.myRewards[index];
                    return _buildMyCouponTile(req);
                  },
                  childCount: _stats!.myRewards.length,
                ),
              ),
            ],

            // ═══════════ COMPLETED MISSIONS ═══════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                child: Row(
                  children: [
                    const Icon(Icons.history, color: AppColors.primaryLight, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      "COMPLETED MISSIONS",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${completedMissions.length} total",
                        style: const TextStyle(color: AppColors.primaryLight, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            completedMissions.isEmpty
                ? SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: const BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.inbox, size: 48, color: AppColors.textTertiary),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              "No missions completed yet",
                              style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Start volunteering to build\nyour environmental impact!",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final mission = completedMissions[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check_circle, color: AppColors.primaryLight, size: 20),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      mission.caption ?? "Cleanup Mission #${mission.id.substring(0, 6)}",
                                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Completed ${mission.formattedDate}",
                                      style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.amber.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  "+${mission.points}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.amber),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: completedMissions.length,
                    ),
                  ),

            // ═══════════ DANGER ZONE ═══════════
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 1, color: AppColors.border.withOpacity(0.3)),
                    const SizedBox(height: 24),
                    const Text(
                      "DANGER ZONE",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _handleDeleteAccount,
                        icon: const Icon(Icons.delete_forever, color: AppColors.danger),
                        label: const Text("Delete My Account", style: TextStyle(color: AppColors.danger)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.danger.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ═══════════ COUPON CARD (Available Rewards from backend ONLY) ═══════════
  Widget _buildCouponCard(Reward reward) {
    return Container(
      width: 165,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand logo / coupon image area
          Container(
            height: 85,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: reward.imageUrl != null && reward.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: reward.imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 85,
                      placeholder: (ctx, url) => const Center(
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight)),
                      ),
                      errorWidget: (ctx, url, err) => Center(
                        child: Text(reward.couponIcon, style: const TextStyle(fontSize: 36)),
                      ),
                    )
                  : Center(
                      child: Text(reward.couponIcon, style: const TextStyle(fontSize: 36)),
                    ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reward.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reward.description,
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "${reward.costInPoints} pts",
                          style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.bold, fontSize: 10),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _requestRedemption(reward),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text("Redeem", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════ MY COUPON TILE (Redemption History) ═══════════
  Widget _buildMyCouponTile(RedemptionRequest req) {
    Color statusColor;
    IconData statusIcon;
    switch (req.status.toLowerCase()) {
      case 'approved':
        statusColor = AppColors.primaryLight;
        statusIcon = Icons.check_circle;
        break;
      case 'rejected':
        statusColor = AppColors.danger;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = AppColors.amber;
        statusIcon = Icons.hourglass_top;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          // Brand logo or coupon icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: req.reward?.imageUrl != null && req.reward!.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: req.reward!.imageUrl!,
                      fit: BoxFit.cover,
                      width: 48,
                      height: 48,
                      errorWidget: (ctx, url, err) => Center(
                        child: req.reward != null
                            ? Text(req.reward!.couponIcon, style: const TextStyle(fontSize: 24))
                            : Icon(Icons.card_giftcard, color: statusColor),
                      ),
                    )
                  : Center(
                      child: req.reward != null
                          ? Text(req.reward!.couponIcon, style: const TextStyle(fontSize: 24))
                          : Icon(Icons.card_giftcard, color: statusColor),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  req.reward?.name ?? "Unknown Reward",
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      req.status.toUpperCase(),
                      style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold),
                    ),
                    if (req.status.toLowerCase() == 'pending') ...[
                      const SizedBox(width: 8),
                      const Text("• Awaiting admin", style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    ],
                    if (req.status.toLowerCase() == 'approved') ...[
                      const SizedBox(width: 8),
                      const Text("• Sent to email", style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestRedemption(Reward reward) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Redeem Reward", style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Brand logo or emoji icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: reward.imageUrl != null && reward.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: reward.imageUrl!,
                        fit: BoxFit.cover,
                        width: 80,
                        height: 80,
                        errorWidget: (ctx, url, err) => Center(
                          child: Text(reward.couponIcon, style: const TextStyle(fontSize: 48)),
                        ),
                      )
                    : Center(
                        child: Text(reward.couponIcon, style: const TextStyle(fontSize: 48)),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Text(reward.name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Text(reward.description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.remove_circle_outline, color: AppColors.amber, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text("${reward.costInPoints} points will be deducted", style: const TextStyle(color: AppColors.amber, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text("${reward.stock} left in stock", style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mail_outline, color: AppColors.info, size: 14),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text("Coupon sent to your email after approval", style: TextStyle(color: AppColors.info, fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Confirm Redeem", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
    );

    try {
      await RewardService().redeemReward(reward.id);
      if (mounted) Navigator.pop(context);

      // Show the "sent to email" banner
      setState(() => _showRedemptionBanner = true);

      // Auto-dismiss banner after 8 seconds
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) setState(() => _showRedemptionBanner = false);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text("Redemption requested! Coupon will be sent to your email.")),
              ],
            ),
            backgroundColor: AppColors.primary,
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Invalidate cache and refresh
      _cachedStats = null;
      _cachedRewards = null;
      _lastFetchTime = null;
      _loadProfile(forceRefresh: true);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$e"), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Widget _impactCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28, color: color),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../models/profile_model.dart';
import '../models/post_model.dart';
import '../services/feed_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final FeedService _feedService = FeedService();
  Future<ProfileStats>? _statsFuture;

  // 0 = My Requests, 1 = Contributions
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    setState(() {
      _statsFuture = _userService.getMyStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: FutureBuilder<ProfileStats>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final stats = snapshot.data!;
          final activeList = _selectedTab == 0 ? stats.myRequests : stats.myContributions;

          return Column(
            children: [
              // --- TOP 25% SECTION: STATS HEADER ---
              Container(
                height: MediaQuery.of(context).size.height * 0.30, // Slightly more than 25% for breathing room
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Avatar & Name
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.white,
                        child: Text(
                          stats.username[0].toUpperCase(),
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        stats.username,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "${stats.points} Points",
                        style: const TextStyle(color: Colors.yellowAccent, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 20),

                      // Stat Counters
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatItem("Requests", stats.createdCount.toString()),
                          Container(width: 1, height: 30, color: Colors.white24),
                          _buildStatItem("Contributions", stats.solvedCount.toString()),
                        ],
                      )
                    ],
                  ),
                ),
              ),

              // --- TOGGLE BUTTONS ---
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildToggleButton("My Requests", 0),
                      _buildToggleButton("Contributions", 1),
                    ],
                  ),
                ),
              ),

              // --- THE LIST ---
              Expanded(
                child: activeList.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 10),
                      Text("No posts found here yet.", style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: activeList.length,
                  itemBuilder: (context, index) {
                    return _buildPostCard(activeList[index]);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _buildToggleButton(String text, int index) {
    final bool isActive = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isActive ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, spreadRadius: 1)] : null,
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isActive ? const Color(0xFF2E7D32) : Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPostCard(Post post) {
    bool isPending = post.status.toLowerCase() == 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- EXISTING IMAGE & STATUS ---
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Stack(
              children: [
                Image.network(
                  post.imageUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(height: 200, color: Colors.grey[300], child: const Icon(Icons.broken_image)),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _getStatusIcon(post.status),
                        const SizedBox(width: 4),
                        Text(post.status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),

          // --- CONTENT ---
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.caption ?? "No description provided.", style: const TextStyle(fontSize: 16, height: 1.4)),
                const SizedBox(height: 12),

                // Existing Metadata Row
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                        "${post.createdAt.day}/${post.createdAt.month}",
                        style: const TextStyle(color: Colors.grey, fontSize: 12)
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- NEW: PROOF SECTION (Only if Pending) ---
          if (isPending && post.proofImageUrl != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50, // Different background color
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Submission by ${post.resolvedBy?.username ?? 'Volunteer'}",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                      ),

                      // THE ACTION BUTTON
                      InkWell(
                        onTap: () => _showApproveDialog(post.id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Text("PENDING", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              SizedBox(width: 4),
                              Icon(Icons.touch_app, size: 14, color: Colors.white)
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Proof Image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      post.proofImageUrl!,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- CONFIRMATION DIALOG ---
  void _showApproveDialog(int postId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Close Request?"),
        content: const Text("This will mark the task as COMPLETED and award points to the volunteer."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              await _handleApprove(postId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text("Approve & Close", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprove(int postId) async {
    try {
      bool success = await _feedService.approveRequest(postId);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request Closed!"), backgroundColor: Colors.green));
          _loadStats(); // Refresh the list
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    }
  }
  Widget _getStatusIcon(String status) {
    switch(status.toLowerCase()) {
      case 'completed': return const Icon(Icons.check_circle, color: Colors.greenAccent, size: 14);
      case 'pending': return const Icon(Icons.hourglass_top, color: Colors.orangeAccent, size: 14);
      default: return const Icon(Icons.error_outline, color: Colors.redAccent, size: 14);
    }
  }
}
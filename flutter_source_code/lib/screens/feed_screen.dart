// lib/screens/feed_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import '../services/feed_service.dart';
import '../models/post_model.dart';
import 'post_detail_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => FeedScreenState();
}

class FeedScreenState extends State<FeedScreen> {
  final FeedService _feedService = FeedService();
  final PageController _pageController = PageController();
  List<Post> _posts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  int? _showingStatsIndex;

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    try {
      setState(() {
        _isLoading = _posts.isEmpty;
        _isRefreshing = _posts.isNotEmpty;
        _errorMessage = null;
      });

      final posts = await _feedService.getFeed();
      
      if (mounted) {
        setState(() {
          _posts = posts.where((p) => p.isOpen).toList();
          _isLoading = false;
          _isRefreshing = false;
        });

        for (final post in _posts) {
          precacheImage(CachedNetworkImageProvider(post.imageUrl), context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _errorMessage = "Failed to load feed: $e";
        });
      }
    }
  }

  void refreshFeed() => _loadFeed();

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.eco, size: 60, color: AppColors.primary),
              SizedBox(height: 24),
              CircularProgressIndicator(color: AppColors.primaryLight),
              SizedBox(height: 16),
              Text("Loading...", style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, color: AppColors.textTertiary, size: 80),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadFeed,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text("Retry", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      );
    }

    if (_posts.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.eco_outlined, color: AppColors.textTertiary, size: 100),
              const SizedBox(height: 24),
              const Text("The area is clean!", style: TextStyle(color: AppColors.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("No cleanup reports nearby.", style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _loadFeed,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text("Refresh", style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _posts.length,
            onPageChanged: (index) {
              setState(() {
                _showingStatsIndex = null;
              });
              if (index + 1 < _posts.length) {
                precacheImage(CachedNetworkImageProvider(_posts[index + 1].imageUrl), context);
              }
            },
            itemBuilder: (context, index) => _buildPostCard(_posts[index], index),
          ),

          // Top Bar
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 16, right: 16, bottom: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withAlpha(180), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.eco, color: AppColors.primaryLight, size: 28),
                  const SizedBox(width: 8),
                  const Text("VCN", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _isRefreshing
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : IconButton(onPressed: _loadFeed, icon: const Icon(Icons.refresh, color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCard(Post post, int index) {
    final bool showStats = _showingStatsIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _showingStatsIndex = showStats ? null : index;
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: post.imageUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: AppColors.surface, child: const Center(child: CircularProgressIndicator(color: AppColors.primary))),
            errorWidget: (_, __, ___) => Container(color: AppColors.surface, child: const Icon(Icons.broken_image, color: AppColors.textSecondary, size: 60)),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withAlpha(75), Colors.black.withAlpha(200)],
                stops: const [0.4, 0.7, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 20, right: 20, bottom: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(post.predictedClass ?? "Analyzing...", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  post.caption ?? "Environmental cleanup needed",
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withAlpha(50),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.amber),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.emoji_events, color: AppColors.amber, size: 18),
                          const SizedBox(width: 6),
                          Text("${post.points} Points", style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text("by @${post.author?.username ?? 'unknown'}", style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 16),
                if (showStats && post.allProbabilities != null && post.allProbabilities!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Trash Verification Metrics", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ...post.allProbabilities!.entries.map((e) {
                          double percent = 0.0;
                          if (e.value is String) {
                             percent = double.tryParse(e.value.toString().replaceAll('%', '')) ?? 0.0;
                          } else if (e.value is num) {
                             percent = (e.value as num).toDouble();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(e.key, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                    Text("${percent.toStringAsFixed(1)}%", style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                  value: percent / 100.0,
                                  backgroundColor: Colors.white24,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
                    if (result == true) _loadFeed();
                  },
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.volunteer_activism, color: Colors.white),
                          SizedBox(width: 8),
                          Text("TAP TO VOLUNTEER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
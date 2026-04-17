// lib/screens/post_detail_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/post_model.dart';
import '../services/feed_service.dart';
import '../services/user_service.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;
  const PostDetailScreen({super.key, required this.post});
  
  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final FeedService _feedService = FeedService();
  final UserService _userService = UserService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _commentController = TextEditingController();
  
  double _distance = 999.0;
  bool _isChecking = true;
  bool _isProcessing = false;
  String _processingStatus = "";
  String? _currentUsername;
  Post? _latestPost;
  List<Comment> _comments = [];
  bool _isPostingComment = false;

  static const double geofenceRadius = 200.0;

  @override
  void initState() {
    super.initState();
    _latestPost = widget.post;
    _comments = List.from(widget.post.comments);
    _loadCurrentUser();
    _loadComments();
    if (widget.post.isOpen) {
      _calculateDistance();
    } else {
      _isChecking = false;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final stats = await _userService.getMyStats();
      if (mounted) {
        setState(() => _currentUsername = stats.username);
      }
    } catch (e) {
      print("Error loading user: $e");
    }
  }

  Future<void> _loadComments() async {
    try {
      final rawComments = await _feedService.getComments(_latestPost!.id);
      if (mounted) {
        setState(() {
          _comments = rawComments.map((c) => Comment.fromJson(c)).toList();
        });
      }
    } catch (e) {
      print("Error loading comments: $e");
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPostingComment = true);
    try {
      await _feedService.postComment(_latestPost!.id, text);
      _commentController.clear();
      await _loadComments();
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await _feedService.deleteComment(commentId);
      await _loadComments();
      _showSuccess("Comment deleted");
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _calculateDistance() async {
    setState(() => _isChecking = true);
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError("Location services disabled. Enable GPS.");
        if (mounted) setState(() => _isChecking = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError("Location permission denied");
          if (mounted) setState(() => _isChecking = false);
          return;
        }
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 30),
      );
      
      double dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, 
        _latestPost!.latitude, _latestPost!.longitude
      );
      
      if (mounted) {
        setState(() {
          _distance = dist;
          _isChecking = false;
        });
      }
    } catch (e) {
      print("GPS error: $e");
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _openGoogleMapsNavigation() async {
    final lat = _latestPost!.latitude;
    final lon = _latestPost!.longitude;
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=walking');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _showError("Could not open maps");
    }
  }

  Future<void> _handleClockIn() async {
    if (_distance > geofenceRadius) {
      _showError("Move closer (within ${geofenceRadius.toInt()}m). Current: ${_distance.toInt()}m");
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = "Opening camera...";
    });

    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo == null) {
        setState(() => _isProcessing = false);
        return;
      }

      setState(() => _processingStatus = "Uploading photo...");
      final uploadResult = await _feedService.uploadImage(File(photo.path));
      if (uploadResult == null) throw "Upload failed";

      setState(() => _processingStatus = "AI verifying...");
      await _feedService.startWork(_latestPost!.id, uploadResult['url']!);

      _showSuccess("Clocked In! Check Active Work in Missions.");
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() { _isProcessing = false; _processingStatus = ""; });
    }
  }

  Future<void> _handleClockOut() async {
    setState(() {
      _isProcessing = true;
      _processingStatus = "Opening camera...";
    });

    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (photo == null) {
        setState(() => _isProcessing = false);
        return;
      }

      setState(() => _processingStatus = "Uploading proof...");
      final uploadResult = await _feedService.uploadImage(File(photo.path));
      if (uploadResult == null) throw "Upload failed";

      setState(() => _processingStatus = "Submitting...");
      await _feedService.submitCleanupProof(_latestPost!.id, uploadResult['url']!);

      _showSuccess("Proof submitted! Waiting for approval.");
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() { _isProcessing = false; _processingStatus = ""; });
    }
  }

  Future<void> _handleApprove() async {
    final post = _latestPost!;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Row(
          children: [
            Icon(Icons.verified, color: AppColors.primaryLight),
            SizedBox(width: 12),
            Text("Approve Work", style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Review before & after:", style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildImagePreview("BEFORE", post.startImageUrl, Colors.orange)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildImagePreview("AFTER", post.endImageUrl, AppColors.primaryLight)),
                ],
              ),
              const SizedBox(height: 16),
              
              if (post.cleanupDurationMinutes != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.info.withAlpha(75)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer, color: AppColors.info, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "Time: ${post.formattedDuration}",
                        style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(50),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.emoji_events, color: AppColors.amber, size: 28),
                    const SizedBox(width: 12),
                    Text("${post.points} Points", style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.bold, fontSize: 22)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text("To: @${post.volunteer?.username ?? 'volunteer'}", style: const TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text("Approve", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() { _isProcessing = true; _processingStatus = "Awarding points..."; });

    try {
      await _feedService.approveRequest(_latestPost!.id, finalPoints: _latestPost!.points);
      _showSuccess("Mission completed! ${_latestPost!.points} pts awarded.");
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() { _isProcessing = false; _processingStatus = ""; });
    }
  }

  Future<void> _handleDeletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Delete Mission", style: TextStyle(color: AppColors.textPrimary)),
        content: const Text("Are you sure you want to permanently delete this mission?", style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() { _isProcessing = true; _processingStatus = "Deleting post..."; });
    try {
      await _feedService.deletePost(_latestPost!.id);
      _showSuccess("Post deleted.");
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() { _isProcessing = false; _processingStatus = ""; });
    }
  }

  Future<void> _handleCancelPost(String actionName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text("$actionName Mission", style: const TextStyle(color: AppColors.textPrimary)),
        content: Text("Are you sure you want to $actionName this mission?", style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Back")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(actionName, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() { _isProcessing = true; _processingStatus = "Updating mission..."; });
    try {
      await _feedService.cancelPost(_latestPost!.id);
      _showSuccess("Mission updated.");
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() { _isProcessing = false; _processingStatus = ""; });
    }
  }

  Widget _buildImagePreview(String label, String? url, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withAlpha(50), borderRadius: BorderRadius.circular(4)),
          child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url != null
            ? Image.network(
                url,
                height: 90,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(height: 90, color: AppColors.surfaceLight, child: const Center(child: CircularProgressIndicator()));
                },
                errorBuilder: (context, error, stackTrace) => Container(height: 90, color: AppColors.surfaceLight, child: const Icon(Icons.broken_image)),
              )
            : Container(height: 90, color: AppColors.surfaceLight, child: const Center(child: Text("N/A", style: TextStyle(color: AppColors.textTertiary)))),
        ),
      ],
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error, color: Colors.white), const SizedBox(width: 12), Expanded(child: Text(msg))]),
      backgroundColor: AppColors.danger,
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 12), Expanded(child: Text(msg))]),
      backgroundColor: AppColors.primary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final post = _latestPost!;
    final isClose = _distance <= geofenceRadius;
    final canClockIn = post.canClockIn(_currentUsername);
    final canClockOut = post.canClockOut(_currentUsername);
    final canApprove = post.canApprove(_currentUsername);
    final canDelete = post.author?.username == _currentUsername;
    final canCancel = post.author?.username == _currentUsername && post.isOpen;
    final canDrop = post.volunteer?.username == _currentUsername && post.isInProgress;

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.directions), onPressed: _openGoogleMapsNavigation, tooltip: "Navigate"),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Image
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Image.network(
                        post.imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 300,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(color: AppColors.surface, child: const Center(child: CircularProgressIndicator()));
                        },
                        errorBuilder: (context, error, stackTrace) => Container(color: AppColors.surface, child: const Icon(Icons.broken_image)),
                      ),
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                              colors: [Colors.transparent, AppColors.background],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status & Points Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: post.statusColor.withAlpha(50),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: post.statusColor),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(post.statusIcon, color: post.statusColor, size: 14),
                                const SizedBox(width: 4),
                                Text(post.statusDisplayName, style: TextStyle(color: post.statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text("${post.points} pts", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Caption
                      Text(post.caption ?? "Cleanup Mission", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 16),

                      // Info Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            _infoRow("Reported by", "@${post.author?.username ?? 'Unknown'}", Icons.person),
                            _infoRow("Category", post.predictedClass ?? "Analyzing...", Icons.category),
                            if (post.volunteer != null) _infoRow("Volunteer", "@${post.volunteer!.username}", Icons.volunteer_activism),
                            if (post.cleanupDurationMinutes != null) _infoRow("Duration", post.formattedDuration, Icons.timer),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Evidence Photos
                      if ((post.isPendingApproval || post.isInProgress) && (post.startImageUrl != null || post.endImageUrl != null))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Evidence Photos", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _buildImagePreview("BEFORE", post.startImageUrl, Colors.orange)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildImagePreview("AFTER", post.endImageUrl, AppColors.primaryLight)),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),

                      // Distance indicator for clock-in
                      if (post.isOpen && canClockIn)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isClose ? AppColors.primary.withAlpha(30) : Colors.orange.withAlpha(30),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isClose ? AppColors.primary : Colors.orange),
                          ),
                          child: Row(
                            children: [
                              Icon(isClose ? Icons.check_circle : Icons.location_searching, color: isClose ? AppColors.primaryLight : Colors.orange),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _isChecking ? "Checking location..." : (isClose ? "Ready! (${_distance.toInt()}m away)" : "${_distance.toInt()}m away (need <${geofenceRadius.toInt()}m)"),
                                  style: TextStyle(color: isClose ? AppColors.primaryLight : Colors.orange),
                                ),
                              ),
                              IconButton(icon: Icon(Icons.refresh, color: isClose ? AppColors.primaryLight : Colors.orange), onPressed: _calculateDistance),
                            ],
                          ),
                        ),

                      // Navigate button if far
                      if (canClockIn && !isClose)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _openGoogleMapsNavigation,
                              icon: const Icon(Icons.navigation, color: Colors.white),
                              label: const Text("NAVIGATE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.info, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                        ),

                      // Action Buttons
                      if (canClockIn)
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton.icon(
                            onPressed: (isClose && !_isChecking) ? _handleClockIn : null,
                            icon: const Icon(Icons.login, color: Colors.white),
                            label: Text(isClose ? "CLOCK IN" : "Get closer", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: isClose ? AppColors.primary : Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          ),
                        ),

                      if (canClockOut)
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _handleClockOut,
                            icon: const Icon(Icons.logout, color: Colors.white),
                            label: const Text("CLOCK OUT - Submit Proof", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          ),
                        ),

                      if (canApprove)
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _handleApprove,
                            icon: const Icon(Icons.verified, color: Colors.white),
                            label: const Text("APPROVE & AWARD", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          ),
                        ),

                      if (canCancel)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SizedBox(
                            width: double.infinity, height: 50,
                            child: ElevatedButton.icon(
                              onPressed: () => _handleCancelPost("Cancel"),
                              icon: const Icon(Icons.cancel, color: Colors.white),
                              label: const Text("CANCEL MISSION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                        ),

                      if (canDrop)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SizedBox(
                            width: double.infinity, height: 50,
                            child: ElevatedButton.icon(
                              onPressed: () => _handleCancelPost("Drop"),
                              icon: const Icon(Icons.close, color: Colors.white),
                              label: const Text("DROP MISSION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                        ),

                      if (canDelete)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: SizedBox(
                            width: double.infinity, height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _handleDeletePost,
                              icon: const Icon(Icons.delete, color: Colors.white),
                              label: const Text("DELETE POST", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            ),
                          ),
                        ),

                      if (!canClockIn && !canClockOut && !canApprove && !canCancel && !canDrop && !canDelete)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: AppColors.textSecondary),
                              const SizedBox(width: 12),
                              Expanded(child: Text(_getInfoMessage(post), style: const TextStyle(color: AppColors.textSecondary))),
                            ],
                          ),
                        ),

                      // ═══════════════ COMMENTS SECTION ═══════════════
                      const SizedBox(height: 32),
                      Container(
                        height: 1,
                        color: AppColors.border.withOpacity(0.3),
                      ),
                      const SizedBox(height: 24),
                      
                      Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline, color: AppColors.primaryLight, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            "Comments (${_comments.length})",
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Comment input
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.primary.withOpacity(0.2),
                              child: Text(
                                (_currentUsername ?? "?")[0].toUpperCase(),
                                style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _commentController,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: "Add a comment...",
                                  hintStyle: TextStyle(color: AppColors.textTertiary),
                                  border: InputBorder.none,
                                  filled: false,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                                ),
                                maxLines: null,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _postComment(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            _isPostingComment
                                ? const SizedBox(
                                    width: 32, height: 32,
                                    child: Padding(
                                      padding: EdgeInsets.all(6),
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.send_rounded, color: AppColors.primaryLight),
                                    onPressed: _postComment,
                                    iconSize: 20,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Comments list
                      if (_comments.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          child: const Center(
                            child: Text(
                              "No comments yet. Be the first!",
                              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                            ),
                          ),
                        )
                      else
                        ..._comments.map((comment) => _buildCommentTile(comment)),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.primaryLight),
                    const SizedBox(height: 20),
                    Text(_processingStatus, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentTile(Comment comment) {
    final isOwn = comment.author?.username == _currentUsername;
    final timeAgo = _formatTimeAgo(comment.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: isOwn ? AppColors.primary.withOpacity(0.2) : AppColors.surfaceLight,
            child: Text(
              (comment.author?.username ?? "?")[0].toUpperCase(),
              style: TextStyle(
                color: isOwn ? AppColors.primaryLight : AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "@${comment.author?.username ?? 'Unknown'}",
                      style: TextStyle(
                        color: isOwn ? AppColors.primaryLight : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(timeAgo, style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
                    if (isOwn) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _confirmDeleteComment(comment.id),
                        child: const Icon(Icons.close, size: 16, color: AppColors.textTertiary),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteComment(String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Delete Comment?", style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed == true) {
      _deleteComment(commentId);
    }
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primaryLight, size: 18),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Flexible(child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  String _getInfoMessage(Post post) {
    if (post.isCompleted) return "Mission completed!";
    if (post.isInProgress && post.volunteer?.username != _currentUsername) return "Being handled by @${post.volunteer?.username}";
    if (post.isPendingApproval) return "Awaiting author approval";
    if (post.isOpen && post.author?.username == _currentUsername) return "Your report - waiting for volunteers";
    return "No actions available";
  }
}
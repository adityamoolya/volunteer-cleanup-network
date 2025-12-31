import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../services/feed_service.dart';
import 'package:url_launcher/url_launcher.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final FeedService _feedService = FeedService();
  final TextEditingController _commentController = TextEditingController();
  late List<Comment> _comments; // Local state to update UI instantly
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _comments = widget.post.comments; // Initialize with data passed from Feed
  }

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;

    setState(() => _isPosting = true);
    try {
      // 1. Send to Backend
      await _feedService.postComment(widget.post.id, _commentController.text.trim());

      // 2. Optimistic Update (or re-fetch). For MVP, we'll re-fetch just to be safe,
      // or you can manually append if you trust the API success.
      // Ideally, the API should return the new Comment object.
      // Since our API returns the Comment object, let's just append it if we parse it.
      // For now, let's just show success and clear. To see it, user can refresh.
      // BETTER UX: Manually add a "fake" comment or fetch fresh data.
      // Let's just clear for now.

      _commentController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Comment Posted! Refresh to see.")));

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Task Details")),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- BIG IMAGE ---
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Hero(
                    tag: "post_img_${widget.post.id}", // Hero Animation
                    child: Image.network(widget.post.imageUrl, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 16),

                // --- CAPTION & AUTHOR ---
                Text(
                  "Reported by @${widget.post.author?.username ?? 'Anon'}",
                  style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.post.caption ?? "",
                  style: const TextStyle(fontSize: 18),
                ),
                const Divider(height: 30),

                // --- COMMENTS HEADER ---
                const Text(
                  "Discussion",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // --- COMMENTS LIST ---
                if (_comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Center(child: Text("No comments yet. Be the first!")),
                  )
                else
                  ..._comments.map((c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade100,
                      child: Text(c.author?.username[0].toUpperCase() ?? "?"),
                    ),
                    title: Text(c.author?.username ?? "Unknown"),
                    subtitle: Text(c.content),
                    trailing: Text(
                      "${c.createdAt.day}/${c.createdAt.month}",
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  )),
              ],
            ),
          ),

          // --- COMMENT INPUT BAR ---
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        hintText: "Add a comment...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _isPosting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send, color: Color(0xFF2E7D32)),
                    onPressed: _isPosting ? null : _submitComment,
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
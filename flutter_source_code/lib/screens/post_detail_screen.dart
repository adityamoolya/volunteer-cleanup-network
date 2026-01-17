// lib/screens/post_detail_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
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
  
  double _distance = 999.0;
  bool _isChecking = true;
  bool _isProcessing = false;
  String _processingStatus = "";
  String? _currentUsername;
  Post? _latestPost;
  Position? _currentPosition;

  // Increased threshold for GPS accuracy issues - 200 meters instead of 100
  static const double GEOFENCE_RADIUS_METERS = 200.0;

  @override
  void initState() {
    super.initState();
    _latestPost = widget.post;
    _loadCurrentUser();
    _calculateDistance();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final stats = await _userService.getMyStats();
      if (mounted) {
        setState(() {
          _currentUsername = stats.username;
        });
      }
    } catch (e) {
      print("Error loading user: $e");
    }
  }

  Future<void> _calculateDistance() async {
    setState(() => _isChecking = true);
    
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError("Location services are disabled. Please enable GPS.");
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

      // Use high accuracy for better GPS results
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 30),
      );
      
      _currentPosition = pos;
      
      double dist = Geolocator.distanceBetween(
        pos.latitude, 
        pos.longitude, 
        _latestPost!.latitude, 
        _latestPost!.longitude
      );
      
      print("DEBUG: Current pos: ${pos.latitude}, ${pos.longitude}");
      print("DEBUG: Post pos: ${_latestPost!.latitude}, ${_latestPost!.longitude}");
      print("DEBUG: Distance: $dist meters, GPS accuracy: ${pos.accuracy}m");
      
      if (mounted) {
        setState(() {
          _distance = dist;
          _isChecking = false;
        });
      }
    } catch (e) {
      print("Error calculating distance: $e");
      _showError("GPS error: $e");
      if (mounted) setState(() => _isChecking = false);
    }
  }

  // Open Google Maps for navigation
  Future<void> _openGoogleMapsNavigation() async {
    final lat = _latestPost!.latitude;
    final lon = _latestPost!.longitude;
    
    // Google Maps URL for navigation
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=walking'
    );
    
    // Alternative: geo URI for default maps app
    final geoUri = Uri.parse('geo:$lat,$lon?q=$lat,$lon');
    
    try {
      // Try Google Maps first
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else {
        _showError("Could not open maps application");
      }
    } catch (e) {
      _showError("Failed to open maps: $e");
    }
  }

  Future<void> _handleClockIn() async {
    // Use the increased geofence radius
    if (_distance > GEOFENCE_RADIUS_METERS) {
      _showError("You must be within ${GEOFENCE_RADIUS_METERS.toInt()} meters of the location to clock in. Current distance: ${_distance.toInt()}m");
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = "Opening camera...";
    });

    try {
      // Capture "Before" photo
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) {
        setState(() => _isProcessing = false);
        return;
      }

      setState(() => _processingStatus = "Uploading photo...");

      // Upload to Cloudinary
      final uploadResult = await _feedService.uploadImage(File(photo.path));
      if (uploadResult == null) {
        throw "Failed to upload image";
      }

      setState(() => _processingStatus = "Starting mission...");

      // Clock in with the before photo - ML will verify trash exists
      await _feedService.startWork(_latestPost!.id, uploadResult['url']!);

      _showSuccess("Mission started! The AI has verified the trash at this location.");
      Navigator.pop(context, true);
      
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingStatus = "";
        });
      }
    }
  }

  Future<void> _handleClockOut() async {
    setState(() {
      _isProcessing = true;
      _processingStatus = "Opening camera...";
    });

    try {
      // Capture "After" photo (proof of completion)
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) {
        setState(() => _isProcessing = false);
        return;
      }

      setState(() => _processingStatus = "Uploading proof...");

      // Upload to Cloudinary
      final uploadResult = await _feedService.uploadImage(File(photo.path));
      if (uploadResult == null) {
        throw "Failed to upload proof image";
      }

      setState(() => _processingStatus = "Submitting proof...");

      // Submit completion proof
      await _feedService.submitCleanupProof(_latestPost!.id, uploadResult['url']!);

      _showSuccess("Proof submitted! Waiting for author to review and approve.");
      Navigator.pop(context, true);
      
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingStatus = "";
        });
      }
    }
  }

  Future<void> _handleApprove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Approve Cleanup", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Award ${_latestPost!.points} points to ${_latestPost!.volunteer?.username ?? 'volunteer'}?",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events, color: Colors.amber),
                  const SizedBox(width: 12),
                  Text(
                    "${_latestPost!.points} Points",
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            child: const Text("Approve", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _processingStatus = "Awarding points...";
    });

    try {
      await _feedService.approveRequest(_latestPost!.id, finalPoints: _latestPost!.points);
      _showSuccess("Mission completed! ${_latestPost!.points} points awarded to volunteer.");
      Navigator.pop(context, true);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingStatus = "";
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF2E7D32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _latestPost!;
    final isClose = _distance <= GEOFENCE_RADIUS_METERS;
    
    // Permission checks
    final canClockIn = post.canClockIn(_currentUsername);
    final canClockOut = post.canClockOut(_currentUsername);
    final canApprove = post.canApprove(_currentUsername);
    
    // Show navigate button for volunteers who can clock in but aren't close enough
    final showNavigateButton = canClockIn && !isClose;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Navigate to location button
          IconButton(
            icon: const Icon(Icons.directions, color: Colors.white),
            onPressed: _openGoogleMapsNavigation,
            tooltip: "Get Directions",
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main Content
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Image
                _buildHeroImage(post),

                // Mission Details
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Badge Row
                      Row(
                        children: [
                          _buildStatusBadge(post),
                          const Spacer(),
                          // Points Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.eco, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  "${post.points} pts",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Caption
                      Text(
                        post.caption ?? "Environmental Cleanup Mission",
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Mission Info Grid
                      _buildInfoGrid(post),
                      const SizedBox(height: 24),

                      // Evidence Bundle (for pending approval)
                      if (post.isPendingApproval && canApprove)
                        _buildEvidenceBundle(post),

                      // Distance Indicator & Navigate Button (for open tasks)
                      if (post.isOpen && canClockIn)
                        _buildDistanceIndicator(isClose),

                      // Navigate to Location Button (prominent when far away)
                      if (showNavigateButton)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _buildNavigateButton(),
                        ),

                      const SizedBox(height: 24),

                      // Action Buttons
                      _buildActionButtons(post, isClose, canClockIn, canClockOut, canApprove),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Loading Overlay
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF4CAF50)),
                    const SizedBox(height: 24),
                    Text(
                      _processingStatus,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavigateButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1976D2), Color(0xFF42A5F5)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _openGoogleMapsNavigation,
        icon: const Icon(Icons.navigation, color: Colors.white),
        label: const Text(
          "NAVIGATE TO LOCATION",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildHeroImage(Post post) {
    return SizedBox(
      height: 350,
      width: double.infinity,
      child: Stack(
        children: [
          CachedNetworkImage(
            imageUrl: post.imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 350,
            placeholder: (context, url) => Container(
              color: const Color(0xFF1E1E1E),
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32))),
            ),
            errorWidget: (context, url, error) => Container(
              color: const Color(0xFF1E1E1E),
              child: const Icon(Icons.broken_image, color: Colors.white54, size: 60),
            ),
          ),
          // Gradient overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF121212),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Post post) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: post.statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: post.statusColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(post.statusIcon, color: post.statusColor, size: 16),
          const SizedBox(width: 6),
          Text(
            post.statusDisplayName,
            style: TextStyle(
              color: post.statusColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(Post post) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildInfoRow("Reported by", "@${post.author?.username ?? 'Unknown'}", Icons.person),
          const Divider(color: Colors.white12, height: 24),
          _buildInfoRow("Category", post.predictedClass ?? "Analyzing...", Icons.category),
          const Divider(color: Colors.white12, height: 24),
          _buildInfoRow(
            "Coordinates", 
            "${post.latitude.toStringAsFixed(4)}, ${post.longitude.toStringAsFixed(4)}", 
            Icons.location_on
          ),
          if (post.volunteer != null) ...[
            const Divider(color: Colors.white12, height: 24),
            _buildInfoRow("Volunteer", "@${post.volunteer!.username}", Icons.volunteer_activism),
          ],
          if (post.cleanupDurationMinutes != null) ...[
            const Divider(color: Colors.white12, height: 24),
            _buildInfoRow("Duration", post.formattedDuration, Icons.timer),
          ],
          if (post.verifiedPoints != null && post.verifiedPoints! > 0) ...[
            const Divider(color: Colors.white12, height: 24),
            _buildInfoRow("Verified Points", "${post.verifiedPoints}", Icons.verified),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32).withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF4CAF50), size: 18),
        ),
        const SizedBox(width: 16),
        Text(label, style: const TextStyle(color: Colors.white54)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEvidenceBundle(Post post) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.compare, color: Color(0xFF4CAF50)),
            SizedBox(width: 12),
            Text(
              "Evidence Bundle",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "BEFORE",
                      style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (post.startImageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: post.startImageUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text("No image", style: TextStyle(color: Colors.white38)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "AFTER",
                      style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (post.endImageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: post.endImageUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text("No image", style: TextStyle(color: Colors.white38)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDistanceIndicator(bool isClose) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isClose 
          ? const Color(0xFF2E7D32).withOpacity(0.1)
          : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isClose ? const Color(0xFF2E7D32) : Colors.orange,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isClose
                  ? const Color(0xFF2E7D32).withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isClose ? Icons.location_on : Icons.location_searching,
              color: isClose ? const Color(0xFF4CAF50) : Colors.orange,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isClose 
                    ? "You're at the location!" 
                    : "Move closer to start",
                  style: TextStyle(
                    color: isClose ? const Color(0xFF4CAF50) : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _isChecking
                    ? "Checking GPS..."
                    : isClose
                      ? "Ready to clock in (${_distance.toInt()}m away)"
                      : "Distance: ${_distance.toInt()}m (need < ${GEOFENCE_RADIUS_METERS.toInt()}m)",
                  style: TextStyle(
                    color: isClose ? Colors.white54 : Colors.orange.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                if (_currentPosition != null)
                  Text(
                    "GPS accuracy: ±${_currentPosition!.accuracy.toInt()}m",
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _calculateDistance,
            icon: Icon(
              Icons.refresh,
              color: isClose ? const Color(0xFF4CAF50) : Colors.orange,
            ),
            tooltip: "Refresh location",
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Post post, bool isClose, bool canClockIn, bool canClockOut, bool canApprove) {
    return Column(
      children: [
        // Clock In Button
        if (canClockIn)
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: isClose
                  ? const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)])
                  : null,
              color: isClose ? null : Colors.grey[700],
              borderRadius: BorderRadius.circular(16),
              boxShadow: isClose
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2E7D32).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: ElevatedButton.icon(
              onPressed: (_isChecking || !isClose) ? null : _handleClockIn,
              icon: Icon(
                _isChecking ? Icons.hourglass_top : Icons.login,
                color: Colors.white,
              ),
              label: Text(
                _isChecking 
                  ? "Checking location..." 
                  : isClose 
                    ? "CLOCK IN - Start Mission"
                    : "Get closer to clock in (${_distance.toInt()}m)",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

        // Clock Out Button
        if (canClockOut)
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFE65100), Color(0xFFFF9800)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _handleClockOut,
              icon: const Icon(Icons.camera_alt, color: Colors.white),
              label: const Text(
                "SUBMIT PROOF - Take Photo",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

        // Approve Button
        if (canApprove)
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2E7D32).withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _handleApprove,
              icon: const Icon(Icons.check_circle, color: Colors.white),
              label: const Text(
                "APPROVE & AWARD POINTS",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),

        // Info for other states
        if (!canClockIn && !canClockOut && !canApprove)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white54),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _getInfoMessage(post),
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _getInfoMessage(Post post) {
    if (post.isCompleted) {
      return "This mission has been completed successfully! ✅";
    } else if (post.isInProgress && post.volunteer?.username != _currentUsername) {
      return "This mission is currently being handled by @${post.volunteer?.username}.";
    } else if (post.isPendingApproval && post.author?.username != _currentUsername) {
      return "Waiting for the author to review and approve the cleanup proof.";
    } else if (post.isOpen && post.author?.username == _currentUsername) {
      return "This is your report. Waiting for volunteers to claim it.";
    }
    return "No actions available for this mission.";
  }
}
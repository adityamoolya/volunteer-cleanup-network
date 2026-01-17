// lib/widgets/contribute_dialog.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../services/feed_service.dart';

class ContributeDialog extends StatefulWidget {
  final int postId;
  final double postLatitude;
  final double postLongitude;
  final VoidCallback onSuccess;

  const ContributeDialog({
    super.key,
    required this.postId,
    required this.postLatitude,
    required this.postLongitude,
    required this.onSuccess,
  });

  @override
  State<ContributeDialog> createState() => _ContributeDialogState();
}

class _ContributeDialogState extends State<ContributeDialog> {
  final FeedService _feedService = FeedService();
  final ImagePicker _picker = ImagePicker();

  File? _startImage;
  bool _isUploading = false;
  String? _errorMessage;

  // Geofencing state
  bool _isCheckingLocation = true;
  bool _isWithinRange = false;
  double? _currentDistance;
  Position? _currentPosition;

  static const double REQUIRED_PROXIMITY_METERS = 100.0;

  @override
  void initState() {
    super.initState();
    _checkProximity();
  }

  // --- GEOFENCING CHECK ---
  Future<void> _checkProximity() async {
    setState(() {
      _isCheckingLocation = true;
      _errorMessage = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _errorMessage = "Location services are disabled. Please enable GPS.";
          _isCheckingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = "Location permission denied.";
            _isCheckingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = "Location permission permanently denied.";
          _isCheckingLocation = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        widget.postLatitude,
        widget.postLongitude,
      );

      setState(() {
        _currentPosition = position;
        _currentDistance = distance;
        _isWithinRange = distance <= REQUIRED_PROXIMITY_METERS;
        _isCheckingLocation = false;

        if (!_isWithinRange) {
          _errorMessage = "You must be within ${REQUIRED_PROXIMITY_METERS.toInt()}m of the site to start. Current distance: ${distance.toInt()}m";
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to get location: $e";
        _isCheckingLocation = false;
      });
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        setState(() {
          _startImage = File(photo.path);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = "Camera error: $e");
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _startImage = File(image.path);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = "Gallery error: $e");
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Choose Photo Source",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF2E7D32)),
                title: const Text("Take Photo"),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromCamera();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF2E7D32)),
                title: const Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  _pickFromGallery();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitClockIn() async {
    if (_startImage == null) {
      setState(() => _errorMessage = "Please select a 'before' photo.");
      return;
    }

    if (!_isWithinRange) {
      setState(() => _errorMessage = "You must be within range to start work.");
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    try {
      // 1. Upload image to Cloudinary
      final uploadResult = await _feedService.uploadImage(_startImage!);

      if (uploadResult == null) {
        throw "Image upload failed";
      }

      // 2. Start work (Clock In)
      bool success = await _feedService.startWork(
        widget.postId,
        uploadResult['url']!,
      );

      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Clocked in! You can now start the cleanup."),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSuccess();
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Start Cleanup",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Location Status
            if (_isCheckingLocation)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text("Checking your location..."),
                  ],
                ),
              )
            else if (_isWithinRange)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "You're within range! (${_currentDistance?.toInt()}m away)",
                        style: TextStyle(color: Colors.green.shade800),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_off, color: Colors.orange.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "You're ${_currentDistance?.toInt() ?? '?'}m away",
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Please move within ${REQUIRED_PROXIMITY_METERS.toInt()}m of the site to start.",
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _checkProximity,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text("Refresh Location"),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Error Message
            if (_errorMessage != null && !_errorMessage!.contains("within"))
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade800, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            const Text(
              "Upload a 'before' photo at the site",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 12),

            // Image Picker
            GestureDetector(
              onTap: _isWithinRange ? _showImageSourceDialog : null,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: _isWithinRange ? Colors.grey[200] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isWithinRange ? Colors.grey[400]! : Colors.grey[500]!,
                  ),
                ),
                child: _startImage == null
                    ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo,
                      size: 50,
                      color: _isWithinRange ? Colors.grey[600] : Colors.grey[500],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isWithinRange
                          ? "Tap to add 'before' photo"
                          : "Move closer to unlock",
                      style: TextStyle(
                        color: _isWithinRange ? Colors.grey[600] : Colors.grey[500],
                      ),
                    ),
                  ],
                )
                    : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _startImage!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Submit Button
            ElevatedButton(
              onPressed: (_isUploading || !_isWithinRange) ? null : _submitClockIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isUploading
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
                  : Text(
                _isWithinRange ? "CLOCK IN" : "OUT OF RANGE",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../services/env_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final EnvService _envService = EnvService();

  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData(); // default load (may use cache)
  }

  // Load data, with optional forced refresh (no cache)
  Future<void> _loadData({bool forceRefresh = false}) async {
    try {
      final data = await _envService.fetchEnvData(refresh: forceRefresh);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  // Color logic for AQI (EPA index 1–6)
  Color _getAqiColor(int aqi) {
    if (aqi <= 50) return Colors.green;           // Good
    if (aqi <= 100) return Colors.lightGreen;     // Satisfactory
    if (aqi <= 200) return Colors.yellow.shade700;// Moderate
    if (aqi <= 300) return Colors.orange;         // Poor
    if (aqi <= 400) return Colors.red;            // Very Poor
    return Colors.red.shade900;                   // Severe
  }

  // 🇮🇳 Update Labels for Indian Scale
  String _getAqiLabel(int aqi) {
    if (aqi <= 50) return "Good";
    if (aqi <= 100) return "Moderate";
    // if (aqi <= 140) return "Moderate";
    if (aqi <= 140) return "Poor";
    // if (aqi <= 400) return "Very Poor";
    return "bad";
  }

  @override
  Widget build(BuildContext context) {
    final bgGradient = _data != null
        ? LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _getAqiColor(_data!['aqi']).withOpacity(0.8),
        const Color(0xFF1B5E20),
      ],
    )
        : const LinearGradient(
      colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _error != null
            ? Center(
          child: Text(
            "Error: $_error",
            style: const TextStyle(color: Colors.white),
          ),
        )
            : SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- HEADER ----
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Your Location",
                          style: TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _data!['location'],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: () {
                        setState(() => _loading = true);
                        _loadData(forceRefresh: true); // 🔥 bypass cache
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // ---- BIG TEMP DISPLAY ----
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.cloud, size: 80, color: Colors.white),
                      Text(
                        "${_data!['temp'].round()}°",
                        style: const TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.w200,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _data!['description'],
                        style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white70,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // ---- GRID ----
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    childAspectRatio: 1.4,
                    children: [
                      _buildInfoTile(
                        "Air Quality",
                        "${_data!['aqi']} • ${_getAqiLabel(_data!['aqi'])}",
                        Icons.air_sharp, // Changed icon as you requested
                        Colors.white,              // 🟢 FIX: Use White instead of _getAqiColor
                      ),
                      _buildInfoTile(
                        "Humidity",
                        "${_data!['humidity']}%",
                        Icons.water_drop,
                        Colors.blue.shade800,
                      ),
                      _buildInfoTile(
                        "Wind",
                        "${_data!['wind']} m/s",
                        Icons.wind_power_outlined,
                        Colors.white,
                      ),
                      _buildInfoTile(
                        "CO2 (Est)",
                        "412 ppm",
                        Icons.co2_rounded,
                        Colors.greenAccent,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(
      String title,
      String value,
      IconData icon,
      Color color,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

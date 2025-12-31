import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvService {
  // 🔑 Your Real Key
  // static final String apiKey = dotenv.env['WEATHER_API_KEY'] ?? '';
  static final String apiKey = "d06e18aa825748f5862110439252711";
  static const bool useDemoMode = false;

  final Dio _dio = Dio();
  static Map<String, dynamic>? _cachedData;

  // ... determinePosition() remains the same ...
  Future<Position> determinePosition() async {
    // (Keep your existing code here)
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return Future.error('Location permissions are denied');
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<Map<String, dynamic>> fetchEnvData({bool refresh = false}) async {
    if (_cachedData != null && !refresh) return _cachedData!;

    if (useDemoMode) {
      // ... demo data ...
      return {};
    }

    try {
      final pos = await determinePosition();

      final response = await _dio.get(
        'http://api.weatherapi.com/v1/current.json',
        queryParameters: {
          'key': apiKey,
          'q': '${pos.latitude},${pos.longitude}',
          'aqi': 'yes',
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final current = data['current'];

        // 1. Get Raw PM2.5
        double pm2_5 = (current['air_quality']['pm2_5'] as num).toDouble();

        // 2. Calculate Indian AQI
        int indianAqi = _calculateIndianAQI(pm2_5);

        // 3. Convert Wind
        double windKph = (current['wind_kph'] as num).toDouble();
        double windMs = windKph / 3.6;

        _cachedData = {
          'temp': current['temp_c'],
          'location': data['location']['name'],
          'aqi': indianAqi, // Now storing 0-500+ value
          'humidity': current['humidity'],
          'wind': double.parse(windMs.toStringAsFixed(1)),
          'description': current['condition']['text'],
        };

        return _cachedData!;
      } else {
        throw "Weather API Error: ${response.statusCode}";
      }
    } catch (e) {
      throw "Failed to get environment data: $e";
    }
  }

  // 🇮🇳 INDIAN CPCB AQI CALCULATOR (Based on PM2.5)
  // Formula: Linear interpolation between breakpoints
  int _calculateIndianAQI(double pm25) {
    if (pm25 <= 30) return _linear(50, 0, 30, 0, pm25);
    if (pm25 <= 60) return _linear(100, 51, 60, 31, pm25);
    if (pm25 <= 90) return _linear(200, 101, 90, 61, pm25);
    if (pm25 <= 120) return _linear(300, 201, 120, 91, pm25);
    if (pm25 <= 250) return _linear(400, 301, 250, 121, pm25);
    return _linear(500, 401, 400, 251, pm25); // >250 is Severe
  }

  int _linear(int Ihi, int Ilo, int Bhi, int Blo, double C) {
    return (((Ihi - Ilo) / (Bhi - Blo)) * (C - Blo) + Ilo).round();
  }
}
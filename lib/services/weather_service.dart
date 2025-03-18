import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_model.dart';
import '../utils/weather_translator.dart';

class WeatherService {
  static const String _baseUrl = 'https://aviationweather.gov/api/data/metar';
  static const Duration _cacheExpiration = Duration(minutes: 15);

  Future<WeatherData?> getAirportWeather(String icao) async {
    // 先检查缓存
    final cachedData = await _getCachedWeather(icao);
    if (cachedData != null) {
      final cacheAge = DateTime.now().difference(cachedData.cacheTime);
      if (cacheAge < _cacheExpiration) {
        return cachedData;
      }
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl?ids=$icao&format=json&taf=true'),
        headers: {'accept': '*/*'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final weatherData = WeatherData.fromJson(data[0]);
          await _cacheWeather(icao, weatherData);
          return weatherData;
        }
      }
    } catch (e) {
      print('获取天气数据失败: $e');
    }
    return null;
  }

  Future<WeatherData?> _getCachedWeather(String icao) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('weather_$icao');
    if (cached != null) {
      return WeatherData.fromJson(json.decode(cached));
    }
    return null;
  }

  Future<void> _cacheWeather(String icao, WeatherData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weather_$icao', json.encode(data.toJson()));
  }

  String getTranslatedMetar(WeatherData data) {
    return WeatherTranslator.translateMetar(data);
  }

  String getTranslatedTaf(String rawTaf) {
    return WeatherTranslator.translateTaf(rawTaf);
  }
}

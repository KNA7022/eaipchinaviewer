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
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('weather_$icao');
      if (cached != null) {
        final weatherData = WeatherData.fromJson(json.decode(cached));
        // 检查缓存是否过期
        final cacheAge = DateTime.now().difference(weatherData.cacheTime);
        if (cacheAge > _cacheExpiration) {
          // 如果缓存过期，删除缓存数据
          await prefs.remove('weather_$icao');
          return null;
        }
        return weatherData;
      }
    } catch (e) {
      print('读取天气缓存失败: $e');
      // 如果读取缓存出错，清除这条缓存
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('weather_$icao');
    }
    return null;
  }

  Future<void> _cacheWeather(String icao, WeatherData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weather_$icao', json.encode(data.toJson()));
    } catch (e) {
      print('保存天气缓存失败: $e');
    }
  }

  // 添加手动清理缓存的方法
  Future<void> clearCache(String icao) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('weather_$icao');
    } catch (e) {
      print('清理天气缓存失败: $e');
    }
  }

  // 添加清理所有过期缓存的方法
  Future<void> clearExpiredCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final weatherKeys = allKeys.where((key) => key.startsWith('weather_'));
      
      for (final key in weatherKeys) {
        final cached = prefs.getString(key);
        if (cached != null) {
          try {
            final weatherData = WeatherData.fromJson(json.decode(cached));
            final cacheAge = DateTime.now().difference(weatherData.cacheTime);
            if (cacheAge > _cacheExpiration) {
              await prefs.remove(key);
            }
          } catch (e) {
            // 如果解析失败，直接删除这条缓存
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      print('清理过期缓存失败: $e');
    }
  }

  String getTranslatedMetar(WeatherData data) {
    return WeatherTranslator.translateMetar(data);
  }

  String getTranslatedTaf(String rawTaf) {
    return WeatherTranslator.translateTaf(rawTaf);
  }
}

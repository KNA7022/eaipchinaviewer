import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weather_model.dart';
import '../utils/weather_translator.dart';

class WeatherService {
  static const String _baseUrl = 'https://aviationweather.gov/api/data/metar';
  static const Duration _cacheExpiration = Duration(minutes: 30);

  // 单例模式实现
  static final WeatherService _instance = WeatherService._internal();
  factory WeatherService() => _instance;
  WeatherService._internal();

  Future<WeatherData?> getAirportWeather(String icao, {bool forceRefresh = false}) async {
    if (icao.isEmpty) return null;
    
    // 标准化ICAO代码（转换为大写）
    icao = icao.trim().toUpperCase();
    
    // 如果不强制刷新，则先检查缓存
    if (!forceRefresh) {
      final cachedData = await _getCachedWeather(icao);
      if (cachedData != null) {
        final cacheAge = DateTime.now().difference(cachedData.cacheTime);
        if (cacheAge < _cacheExpiration) {
          return cachedData;
        }
      }
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl?ids=$icao&format=json&taf=true'),
        headers: {'accept': '*/*'},
      ).timeout(const Duration(seconds: 15)); // 添加超时处理

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final weatherData = WeatherData.fromJson(data[0]);
          await _cacheWeather(icao, weatherData);
          return weatherData;
        } else {
          // API 返回空数据，可能是机场代码无效
          print('未找到机场代码 $icao 的天气数据');
          return null;
        }
      } else {
        // API 返回错误状态码
        print('获取天气API返回错误: ${response.statusCode}');
        // 如果缓存数据存在但已过期，在API请求失败的情况下仍返回过期数据
        final cachedData = await _getCachedWeather(icao, includeExpired: true);
        if (cachedData != null) {
          return cachedData; // 返回过期数据并标记
        }
        return null;
      }
    } catch (e) {
      print('获取天气数据失败: $e');
      // 网络请求失败时，尝试使用过期的缓存数据
      final cachedData = await _getCachedWeather(icao, includeExpired: true);
      if (cachedData != null) {
        return cachedData; // 返回过期数据作为备用
      }
      return null;
    }
  }

  Future<WeatherData?> _getCachedWeather(String icao, {bool includeExpired = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('weather_$icao');
      if (cached != null) {
        final weatherData = WeatherData.fromJson(json.decode(cached));
        
        // 检查缓存是否过期
        final cacheAge = DateTime.now().difference(weatherData.cacheTime);
        if (includeExpired || cacheAge <= _cacheExpiration) {
          return weatherData;
        } else {
          // 不自动删除过期缓存，只在定期清理时删除
          print('缓存已过期：$icao');
        }
      }
    } catch (e) {
      print('读取天气缓存失败: $e');
      try {
        // 如果读取缓存出错，清除这条缓存
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('weather_$icao');
      } catch (e2) {
        print('清除损坏的缓存失败: $e2');
      }
    }
    return null;
  }

  Future<void> _cacheWeather(String icao, WeatherData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = data.toJson();
      await prefs.setString('weather_$icao', json.encode(jsonData));
      print('缓存天气数据: $icao');
    } catch (e) {
      print('保存天气缓存失败: $e');
    }
  }

  Future<void> clearCache(String icao) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('weather_$icao');
      print('已清除 $icao 的天气缓存');
    } catch (e) {
      print('清理天气缓存失败: $e');
    }
  }

  Future<void> clearExpiredCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final weatherKeys = allKeys.where((key) => key.startsWith('weather_')).toList();
      
      int clearedCount = 0;
      for (final key in weatherKeys) {
        final cached = prefs.getString(key);
        if (cached != null) {
          try {
            final weatherData = WeatherData.fromJson(json.decode(cached));
            final cacheAge = DateTime.now().difference(weatherData.cacheTime);
            if (cacheAge > _cacheExpiration) {
              await prefs.remove(key);
              clearedCount++;
            }
          } catch (e) {
            // 如果解析失败，直接删除这条缓存
            await prefs.remove(key);
            clearedCount++;
          }
        }
      }
      print('已清理 $clearedCount 条过期天气缓存');
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
  
  // 针对ICAO代码进行简单验证
  bool isValidIcaoCode(String code) {
    if (code.isEmpty) return false;
    
    // ICAO代码通常为4个字母
    final trimmedCode = code.trim();
    if (trimmedCode.length != 4) return false;
    
    // ICAO代码应该只包含字母
    return RegExp(r'^[A-Za-z]{4}$').hasMatch(trimmedCode);
  }
}

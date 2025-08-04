import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AirportService {
  static const String _baseUrl = 'https://api.api-ninjas.com/v1/airports';
  static const String _apiKey = 'h9tvT16uBAbGBve/hHifSQ==2V8XNxpsw6KGafiQ'; // 需要替换为实际的API密钥
  static const String _cachePrefix = 'airport_';
  static const Duration _cacheExpiry = Duration(days: 30); // 机场信息缓存30天

  /// 根据ICAO代码获取机场信息
  Future<AirportInfo?> getAirportInfo(String icaoCode) async {
    if (icaoCode.isEmpty || icaoCode.length != 4) {
      return null;
    }

    // 先尝试从缓存获取
    final cachedInfo = await _getCachedAirportInfo(icaoCode);
    if (cachedInfo != null) {
      return cachedInfo;
    }

    // 从API获取
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl?icao=$icaoCode'),
        headers: {
          'X-Api-Key': _apiKey,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final airportInfo = AirportInfo.fromJson(data[0]);
          // 缓存结果
          await _cacheAirportInfo(icaoCode, airportInfo);
          return airportInfo;
        }
      }
    } catch (e) {
      print('获取机场信息失败: $e');
    }

    return null;
  }

  /// 从缓存获取机场信息
  Future<AirportInfo?> _getCachedAirportInfo(String icaoCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$icaoCode';
      final cachedData = prefs.getString(cacheKey);
      
      if (cachedData != null) {
        final Map<String, dynamic> data = json.decode(cachedData);
        final cacheTime = DateTime.parse(data['cacheTime']);
        
        // 检查缓存是否过期
        if (DateTime.now().difference(cacheTime) < _cacheExpiry) {
          return AirportInfo.fromJson(data['airportInfo']);
        } else {
          // 删除过期缓存
          await prefs.remove(cacheKey);
        }
      }
    } catch (e) {
      print('读取机场缓存失败: $e');
    }
    
    return null;
  }

  /// 缓存机场信息
  Future<void> _cacheAirportInfo(String icaoCode, AirportInfo airportInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$icaoCode';
      final cacheData = {
        'airportInfo': airportInfo.toJson(),
        'cacheTime': DateTime.now().toIso8601String(),
      };
      
      await prefs.setString(cacheKey, json.encode(cacheData));
    } catch (e) {
      print('缓存机场信息失败: $e');
    }
  }

  /// 清理过期缓存
  Future<void> clearExpiredCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_cachePrefix));
      
      for (final key in keys) {
        final cachedData = prefs.getString(key);
        if (cachedData != null) {
          final Map<String, dynamic> data = json.decode(cachedData);
          final cacheTime = DateTime.parse(data['cacheTime']);
          
          if (DateTime.now().difference(cacheTime) >= _cacheExpiry) {
            await prefs.remove(key);
          }
        }
      }
    } catch (e) {
      print('清理机场缓存失败: $e');
    }
  }
}

class AirportInfo {
  final String icao;
  final String? iata;
  final String name;
  final String? city;
  final String? region;
  final String? country;
  final String? timezone;
  final double? latitude;
  final double? longitude;
  final int? elevationFt;

  AirportInfo({
    required this.icao,
    this.iata,
    required this.name,
    this.city,
    this.region,
    this.country,
    this.timezone,
    this.latitude,
    this.longitude,
    this.elevationFt,
  });

  factory AirportInfo.fromJson(Map<String, dynamic> json) {
    return AirportInfo(
      icao: json['icao'] ?? '',
      iata: json['iata'],
      name: json['name'] ?? '',
      city: json['city'],
      region: json['region'],
      country: json['country'],
      timezone: json['timezone'],
      latitude: _parseDouble(json['latitude']),
      longitude: _parseDouble(json['longitude']),
      elevationFt: _parseInt(json['elevation_ft']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'icao': icao,
      'iata': iata,
      'name': name,
      'city': city,
      'region': region,
      'country': country,
      'timezone': timezone,
      'latitude': latitude,
      'longitude': longitude,
      'elevation_ft': elevationFt,
    };
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  /// 获取显示名称（优先显示城市+机场名，否则只显示机场名）
  String get displayName {
    if (city != null && city!.isNotEmpty) {
      return '$city - $name';
    }
    return name;
  }

  /// 获取简短显示名称（机场名 + IATA代码）
  String get shortDisplayName {
    if (iata != null && iata!.isNotEmpty) {
      return '$name ($iata)';
    }
    return name;
  }
}
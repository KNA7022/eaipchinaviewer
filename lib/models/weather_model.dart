import 'dart:convert';

class WeatherData {
  final String icaoId;
  final DateTime reportTime;
  final double? temperature;
  final double? dewpoint;
  final int? windDirection;
  final int? windSpeed;
  final String visibility;
  final List<Cloud> clouds;
  final String rawMetar;
  final String? rawTaf;
  final DateTime cacheTime;

  WeatherData({
    required this.icaoId,
    required this.reportTime,
    this.temperature,
    this.dewpoint,
    this.windDirection,
    this.windSpeed,
    required this.visibility,
    required this.clouds,
    required this.rawMetar,
    this.rawTaf,
    required this.cacheTime,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      icaoId: json['icaoId'] ?? '',
      reportTime: DateTime.parse(json['reportTime'] ?? DateTime.now().toIso8601String()),
      temperature: _parseDouble(json['temp']),
      dewpoint: _parseDouble(json['dewp']),
      windDirection: _parseInt(json['wdir']),
      windSpeed: _parseInt(json['wspd']),
      visibility: (json['visib'] ?? 'NA').toString(),
      clouds: (json['clouds'] as List?)
          ?.map((e) => Cloud.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      rawMetar: json['rawOb']?.toString() ?? '',
      rawTaf: json['rawTaf']?.toString(),
      cacheTime: json['cacheTime'] != null 
          ? DateTime.parse(json['cacheTime'])
          : DateTime.now(),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) return value.round();
    return null;
  }

  Map<String, dynamic> toJson() => {
    'icaoId': icaoId,
    'reportTime': reportTime.toIso8601String(),
    'temp': temperature,
    'dewp': dewpoint,
    'wdir': windDirection,
    'wspd': windSpeed,
    'visib': visibility,
    'clouds': clouds.map((e) => e.toJson()).toList(),
    'rawOb': rawMetar,
    'rawTaf': rawTaf,
    'cacheTime': cacheTime.toIso8601String(),
  };
}

class Cloud {
  final String cover;
  final int base;

  Cloud({required this.cover, required this.base});

  factory Cloud.fromJson(Map<String, dynamic> json) {
    return Cloud(
      cover: json['cover']?.toString() ?? '',
      base: _parseInt(json['base']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'cover': cover,
    'base': base,
  };

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.round();
    return 0;
  }
}

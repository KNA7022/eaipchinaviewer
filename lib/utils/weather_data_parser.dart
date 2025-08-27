import '../models/weather_model.dart';

/// 增强的气象数据解析器，专门为可视化功能提供结构化数据
class WeatherDataParser {
  /// 解析风向风速数据
  static WindVisualizationData parseWindData(WeatherData weatherData) {
    final metar = weatherData.rawMetar ?? '';
    final windPattern = RegExp(r'(VRB|\d{3})(\d{2,3})(?:G(\d{2,3}))?(KT|MPS)(?:\s+(\d{3})V(\d{3}))?');
    
    // 调试输出
    print('METAR数据: $metar');
    print('风向风速匹配结果: ${windPattern.allMatches(metar).map((m) => m.group(0)).toList()}');
    final match = windPattern.firstMatch(metar);
    
    if (match != null) {
      final directionStr = match.group(1)!;
      final speedStr = match.group(2)!;
      final gustStr = match.group(3);
      final unit = match.group(4)!;
      
      double direction = 0;
      bool isVariable = false;
      bool isCalm = false;
      
      if (directionStr == 'VRB') {
        isVariable = true;
        // VRB表示不定风向，不是风向为0
        // 为了可视化效果，可以设置一个特殊值或使用当前时间的角度来显示旋转效果
        direction = DateTime.now().second * 6.0; // 根据当前秒数设置一个0-360的角度
      } else {
        final dirValue = int.parse(directionStr);
        if (dirValue == 0) {
          isCalm = true;
        }
        direction = dirValue.toDouble();
      }
      
      double speed = double.parse(speedStr);
      double? gust = gustStr != null ? double.parse(gustStr) : null;
      
      // 转换单位到节
      if (unit == 'MPS') {
        speed = speed * 1.94384; // 米/秒转节
        gust = gust != null ? gust * 1.94384 : null;
      }
      
      return WindVisualizationData(
        direction: direction,
        speed: speed,
        gust: gust,
        isVariable: isVariable,
        isCalm: isCalm,
        unit: 'kt',
        directionText: _getWindDirectionText(direction),
        speedCategory: _getWindSpeedCategory(speed),
      );
    }
    
    return WindVisualizationData(
      direction: 0,
      speed: 0,
      isVariable: false,
      isCalm: true,
      unit: 'kt',
      directionText: '静风',
      speedCategory: WindSpeedCategory.calm,
    );
  }
  
  /// 解析能见度数据
  static VisibilityVisualizationData parseVisibilityData(WeatherData weatherData) {
    final metar = weatherData.rawMetar ?? '';
    
    // CAVOK情况
    if (metar.contains('CAVOK')) {
      return VisibilityVisualizationData(
        visibility: 10.0,
        unit: 'km',
        level: VisibilityLevel.excellent,
        isCavok: true,
        description: 'CAVOK - 天空晴朗，能见度10公里以上',
      );
    }
    
    // 数字能见度：9999, 1200, 0800等
    final visPattern = RegExp(r'\b(\d{4})\b');
    final match = visPattern.firstMatch(metar);
    
    if (match != null) {
      final visMeters = int.parse(match.group(1)!);
      double visKm;
      
      if (visMeters == 9999) {
        visKm = 10.0;
      } else {
        visKm = visMeters / 1000.0;
      }
      
      return VisibilityVisualizationData(
        visibility: visKm,
        unit: 'km',
        level: _getVisibilityLevel(visKm),
        isCavok: false,
        description: _getVisibilityDescription(visKm),
      );
    }
    
    // 默认值
    return VisibilityVisualizationData(
      visibility: 10.0,
      unit: 'km',
      level: VisibilityLevel.excellent,
      isCavok: false,
      description: '能见度良好',
    );
  }
  
  /// 解析云层数据
  static List<CloudLayerVisualizationData> parseCloudData(WeatherData weatherData) {
    final metar = weatherData.rawMetar ?? '';
    final cloudLayers = <CloudLayerVisualizationData>[];
    
    // 晴空情况
    if (metar.contains('SKC') || metar.contains('CLR') || metar.contains('NSC') || metar.contains('CAVOK')) {
      cloudLayers.add(CloudLayerVisualizationData(
        coverage: CloudCoverage.clear,
        height: 0,
        type: CloudType.clear,
        description: '晴空',
      ));
      return cloudLayers;
    }
    
    // 云层正则表达式：FEW015, SCT025, BKN040, OVC080, FEW015TCU, BKN025CB
    final cloudPattern = RegExp(r'(FEW|SCT|BKN|OVC|VV)(\d{3})(TCU|CB)?');
    final matches = cloudPattern.allMatches(metar);
    
    for (final match in matches) {
      final coverageStr = match.group(1)!;
      final heightStr = match.group(2)!;
      final typeStr = match.group(3);
      
      final coverage = _getCloudCoverage(coverageStr);
      final height = int.parse(heightStr) * 100; // 转换为英尺
      final type = _getCloudType(typeStr);
      
      cloudLayers.add(CloudLayerVisualizationData(
        coverage: coverage,
        height: height.toDouble(),
        type: type,
        description: _getCloudDescription(coverage, height, type),
      ));
    }
    
    // 如果没有解析到云层，添加默认晴空
    if (cloudLayers.isEmpty) {
      cloudLayers.add(CloudLayerVisualizationData(
        coverage: CloudCoverage.clear,
        height: 0,
        type: CloudType.clear,
        description: '晴空',
      ));
    }
    
    return cloudLayers;
  }
  
  /// 解析温度露点数据
  static TemperatureVisualizationData parseTemperatureData(WeatherData weatherData) {
    final metar = weatherData.rawMetar ?? '';
    
    // 温度露点正则表达式：M04/M10, 15/08, 22/M05
    final tempPattern = RegExp(r'\b(M?\d{2})/(M?\d{2})\b');
    final match = tempPattern.firstMatch(metar);
    
    if (match != null) {
      final tempStr = match.group(1)!;
      final dewStr = match.group(2)!;
      
      final temperature = _parseTemperature(tempStr);
      final dewpoint = _parseTemperature(dewStr);
      final spread = temperature - dewpoint;
      
      return TemperatureVisualizationData(
        temperature: temperature.toDouble(),
        dewpoint: dewpoint.toDouble(),
        spread: spread.toDouble(),
        unit: '°C',
        category: _getTemperatureCategory(temperature.toInt()),
        humidity: _calculateRelativeHumidity(temperature.toInt(), dewpoint.toInt()),
      );
    }
    
    // 尝试使用结构化数据
    if (weatherData.temperature != null && weatherData.dewpoint != null) {
      final temp = weatherData.temperature!;
      final dew = weatherData.dewpoint!;
      final spread = temp - dew;
      
      return TemperatureVisualizationData(
        temperature: temp.toDouble(),
        dewpoint: dew.toDouble(),
        spread: spread.toDouble(),
        unit: '°C',
        category: _getTemperatureCategory(temp.toInt()),
        humidity: _calculateRelativeHumidity(temp.toInt(), dew.toInt()),
      );
    }
    
    return TemperatureVisualizationData(
      temperature: 15.0,
      dewpoint: 10.0,
      spread: 5.0,
      unit: '°C',
      category: TemperatureCategory.mild,
      humidity: 70.0,
    );
  }
  
  // 辅助方法
  static String _getWindDirectionText(double direction) {
    if (direction >= 348.75 || direction < 11.25) return '北风';
    if (direction >= 11.25 && direction < 33.75) return '北北东风';
    if (direction >= 33.75 && direction < 56.25) return '东北风';
    if (direction >= 56.25 && direction < 78.75) return '东北东风';
    if (direction >= 78.75 && direction < 101.25) return '东风';
    if (direction >= 101.25 && direction < 123.75) return '东南东风';
    if (direction >= 123.75 && direction < 146.25) return '东南风';
    if (direction >= 146.25 && direction < 168.75) return '南南东风';
    if (direction >= 168.75 && direction < 191.25) return '南风';
    if (direction >= 191.25 && direction < 213.75) return '南南西风';
    if (direction >= 213.75 && direction < 236.25) return '西南风';
    if (direction >= 236.25 && direction < 258.75) return '西南西风';
    if (direction >= 258.75 && direction < 281.25) return '西风';
    if (direction >= 281.25 && direction < 303.75) return '西北西风';
    if (direction >= 303.75 && direction < 326.25) return '西北风';
    if (direction >= 326.25 && direction < 348.75) return '北北西风';
    return '未知';
  }
  
  static WindSpeedCategory _getWindSpeedCategory(double speed) {
    if (speed == 0) return WindSpeedCategory.calm;
    if (speed <= 3) return WindSpeedCategory.light;
    if (speed <= 10) return WindSpeedCategory.gentle;
    if (speed <= 20) return WindSpeedCategory.moderate;
    if (speed <= 30) return WindSpeedCategory.fresh;
    if (speed <= 40) return WindSpeedCategory.strong;
    return WindSpeedCategory.gale;
  }
  
  static VisibilityLevel _getVisibilityLevel(double visibility) {
    if (visibility >= 10) return VisibilityLevel.excellent;
    if (visibility >= 5) return VisibilityLevel.good;
    if (visibility >= 1.5) return VisibilityLevel.moderate;
    if (visibility >= 0.8) return VisibilityLevel.poor;
    return VisibilityLevel.veryPoor;
  }
  
  static String _getVisibilityDescription(double visibility) {
    final level = _getVisibilityLevel(visibility);
    switch (level) {
      case VisibilityLevel.excellent:
        return '能见度极佳，视野清晰';
      case VisibilityLevel.good:
        return '能见度良好，适合飞行';
      case VisibilityLevel.moderate:
        return '能见度一般，需要注意';
      case VisibilityLevel.poor:
        return '能见度较差，飞行需谨慎';
      case VisibilityLevel.veryPoor:
        return '能见度很差，不适合飞行';
    }
  }
  
  static CloudCoverage _getCloudCoverage(String coverage) {
    switch (coverage) {
      case 'FEW': return CloudCoverage.few;
      case 'SCT': return CloudCoverage.scattered;
      case 'BKN': return CloudCoverage.broken;
      case 'OVC': return CloudCoverage.overcast;
      case 'VV': return CloudCoverage.obscured;
      default: return CloudCoverage.clear;
    }
  }
  
  static CloudType _getCloudType(String? type) {
    if (type == null) return CloudType.normal;
    switch (type) {
      case 'TCU': return CloudType.towering;
      case 'CB': return CloudType.cumulonimbus;
      default: return CloudType.normal;
    }
  }
  
  static String _getCloudDescription(CloudCoverage coverage, int height, CloudType type) {
    String coverageText = '';
    switch (coverage) {
      case CloudCoverage.clear: coverageText = '晴空'; break;
      case CloudCoverage.few: coverageText = '少云'; break;
      case CloudCoverage.scattered: coverageText = '散云'; break;
      case CloudCoverage.broken: coverageText = '多云'; break;
      case CloudCoverage.overcast: coverageText = '阴天'; break;
      case CloudCoverage.obscured: coverageText = '遮蔽'; break;
    }
    
    String typeText = '';
    switch (type) {
      case CloudType.towering: typeText = '(塔状积云)'; break;
      case CloudType.cumulonimbus: typeText = '(积雨云)'; break;
      case CloudType.normal: typeText = ''; break;
      case CloudType.clear: typeText = ''; break;
    }
    
    if (coverage == CloudCoverage.clear) {
      return coverageText;
    }
    
    return '$coverageText ${height}英尺$typeText';
  }
  
  static int _parseTemperature(String tempStr) {
    if (tempStr.startsWith('M')) {
      return -int.parse(tempStr.substring(1));
    }
    return int.parse(tempStr);
  }
  
  static TemperatureCategory _getTemperatureCategory(int temperature) {
    if (temperature <= -10) return TemperatureCategory.freezing;
    if (temperature <= 0) return TemperatureCategory.cold;
    if (temperature <= 10) return TemperatureCategory.cool;
    if (temperature <= 25) return TemperatureCategory.mild;
    if (temperature <= 35) return TemperatureCategory.warm;
    return TemperatureCategory.hot;
  }
  
  static double _calculateRelativeHumidity(int temperature, int dewpoint) {
    // 使用Magnus公式计算相对湿度
    final a = 17.27;
    final b = 237.7;
    
    final alpha = ((a * temperature) / (b + temperature)) + (dewpoint / (b + dewpoint));
    final beta = (a * dewpoint) / (b + dewpoint);
    
    return (100 * (alpha - beta)).clamp(0, 100);
  }
}

// 数据模型类
class WindVisualizationData {
  final double direction;
  final double speed;
  final double? gust;
  final bool isVariable;
  final bool isCalm;
  final String unit;
  final String directionText;
  final WindSpeedCategory speedCategory;
  
  WindVisualizationData({
    required this.direction,
    required this.speed,
    this.gust,
    required this.isVariable,
    required this.isCalm,
    required this.unit,
    required this.directionText,
    required this.speedCategory,
  });
}

class VisibilityVisualizationData {
  final double visibility;
  final String unit;
  final VisibilityLevel level;
  final bool isCavok;
  final String description;
  
  VisibilityVisualizationData({
    required this.visibility,
    required this.unit,
    required this.level,
    required this.isCavok,
    required this.description,
  });
}

class CloudLayerVisualizationData {
  final CloudCoverage coverage;
  final double height;
  final CloudType type;
  final String description;
  
  CloudLayerVisualizationData({
    required this.coverage,
    required this.height,
    required this.type,
    required this.description,
  });
}

class TemperatureVisualizationData {
  final double temperature;
  final double dewpoint;
  final double spread;
  final String unit;
  final TemperatureCategory category;
  final double humidity;
  
  TemperatureVisualizationData({
    required this.temperature,
    required this.dewpoint,
    required this.spread,
    required this.unit,
    required this.category,
    required this.humidity,
  });
}

// 枚举类型
enum WindSpeedCategory {
  calm('静风'),
  light('微风'),
  gentle('轻风'),
  moderate('和风'),
  fresh('清风'),
  strong('强风'),
  gale('大风');
  
  const WindSpeedCategory(this.description);
  final String description;
}

enum VisibilityLevel {
  excellent('优秀'),
  good('良好'),
  moderate('一般'),
  poor('较差'),
  veryPoor('很差');
  
  const VisibilityLevel(this.description);
  final String description;
}

enum CloudCoverage {
  clear('晴空'),
  few('少云'),
  scattered('散云'),
  broken('多云'),
  overcast('阴天'),
  obscured('遮蔽');
  
  const CloudCoverage(this.description);
  final String description;
}

enum CloudType {
  clear('晴空'),
  normal('普通云'),
  towering('塔状积云'),
  cumulonimbus('积雨云');
  
  const CloudType(this.description);
  final String description;
}

enum TemperatureCategory {
  freezing('严寒'),
  cold('寒冷'),
  cool('凉爽'),
  mild('温和'),
  warm('温暖'),
  hot('炎热');
  
  const TemperatureCategory(this.description);
  final String description;
}
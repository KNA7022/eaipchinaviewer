import '../models/weather_model.dart';

class WeatherTranslator {
  static String translateMetar(WeatherData data) {
    List<String> parts = [];
    
    // 基本信息
    parts.add('${data.icaoId}机场天气报告');
    parts.add('观测时间：${_formatDateTime(data.reportTime)}');
    
    // 温度露点
    if (data.temperature != null) {
      parts.add('温度：${data.temperature}°C');
    }
    if (data.dewpoint != null) {
      parts.add('露点：${data.dewpoint}°C');
    }
    
    // 风向风速
    if (data.windDirection != null && data.windSpeed != null) {
      parts.add('风向：${data.windDirection}度');
      parts.add('风速：${data.windSpeed}节');
    }
    
    // 能见度
    parts.add('能见度：${_translateVisibility(data.visibility)}');
    
    // 云层
    if (data.clouds.isNotEmpty) {
      parts.add('云层：${_translateClouds(data.clouds)}');
    }
    
    return parts.join('\n');
  }

  static String translateTaf(String rawTaf) {
    if (rawTaf.isEmpty) return '无预报信息';
    
    List<String> parts = rawTaf.split(' ');
    if (parts.isEmpty) return '预报解析失败';

    // 如果第一个词是TAF，则移除它
    if (parts[0] == 'TAF') {
      parts = parts.sublist(1);
    }
    if (parts.isEmpty) return '预报解析失败';

    List<String> translated = ['天气预报：'];
    
    // 机场和发布时间
    String icao = parts[0];
    String issueTime = _translateDateTime(parts[1]);
    translated.add('$icao机场 发布时间：$issueTime');

    // 预报有效时段
    if (parts.length > 2) {
      String validPeriod = _translateValidPeriod(parts[2]);
      translated.add('预报时段：$validPeriod');
    }

    // 基本天气信息
    List<String> weatherInfo = [];
    
    // 处理风向风速
    for (int i = 3; i < parts.length; i++) {
      String part = parts[i];
      
      // 解析风速 (例如: 04006MPS)
      if (RegExp(r'^\d{5}(MPS|KT)$').hasMatch(part)) {
        int direction = int.tryParse(part.substring(0, 3)) ?? 0;
        int speed = int.tryParse(part.substring(3, 5)) ?? 0;
        String unit = part.endsWith('MPS') ? '米/秒' : '节';
        weatherInfo.add('风向${direction}度，风速$speed$unit');
        continue;
      }
      
      // 解析能见度 (例如: 6000)
      if (RegExp(r'^\d{4}$').hasMatch(part)) {
        int vis = int.tryParse(part) ?? 0;
        weatherInfo.add('能见度${vis ~/ 1000}公里');
        continue;
      }

      // 解析云层
      if (_isCloud(part)) {
        String cloudCover = _translateCloudCover(part.substring(0, 3));
        int height = int.tryParse(part.substring(3)) ?? 0;
        weatherInfo.add('$cloudCover，云底高${height * 100}英尺');
        continue;
      }

      // 解析温度
      if (part.startsWith('TX') || part.startsWith('TN')) {
        String tempType = part.startsWith('TX') ? '最高' : '最低';
        String temp = part.substring(2, part.indexOf('/'));
        String time = part.substring(part.indexOf('/') + 1, part.length - 1);
        int hour = int.tryParse(time.substring(2, 4)) ?? 0;
        weatherInfo.add('$tempType温度${temp}°C (${hour}时)');
        continue;
      }
    }

    if (weatherInfo.isNotEmpty) {
      translated.add(weatherInfo.join('，'));
    }

    return translated.join('\n');
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}年${dt.month}月${dt.day}日 ${dt.hour}:${dt.minute}';
  }

  static String _translateVisibility(String vis) {
    if (vis == '10+') return '大于10千米';
    return '$vis千米';
  }

  static String _translateClouds(List<Cloud> clouds) {
    return clouds.map((cloud) {
      String cover = _translateCloudCover(cloud.cover);
      return '$cover ${cloud.base}尺';
    }).join('，');
  }

  static String _translateCloudCover(String cover) {
    switch (cover) {
      case 'SKC': return '晴空';
      case 'FEW': return '少量';
      case 'SCT': return '疏云';
      case 'BKN': return '多云';
      case 'OVC': return '阴天';
      default: return cover;
    }
  }

  static String _translateTafPart(String part) {
    return part;
  }

  static String _translateDateTime(String code) {
    try {
      int day = int.parse(code.substring(0, 2));
      int hour = int.parse(code.substring(2, 4));
      int minute = int.parse(code.substring(4, 6));
      return '$day日$hour时${minute}分';
    } catch (e) {
      return code;
    }
  }

  static String _translateValidPeriod(String code) {
    if (code.length != 9) return code;
    try {
      int fromDay = int.parse(code.substring(0, 2));
      int fromHour = int.parse(code.substring(2, 4));
      int toDay = int.parse(code.substring(5, 7));
      int toHour = int.parse(code.substring(7, 9));
      return '$fromDay日$fromHour时 至 $toDay日$toHour时';
    } catch (e) {
      return code;
    }
  }

  static String _translateForecastGroup(List<String> group) {
    if (group.isEmpty) return '';

    List<String> translated = [];
    
    // 处理时段标记
    if (group[0].startsWith('FM')) {
      String time = _translateFromTime(group[0]);
      translated.add('\n从$time起：');
      group = group.sublist(1);
    } else if (group[0].startsWith('PROB')) {
      String prob = group[0].substring(4);
      translated.add('\n概率$prob%：');
      group = group.sublist(1);
    } else if (group[0].startsWith('TEMPO')) {
      translated.add('\n短时：');
      group = group.sublist(1);
    }

    // 处理天气现象
    Map<String, String> weather = _parseWeatherElements(group);
    
    if (weather['wind'] != null) translated.add(weather['wind']!);
    if (weather['vis'] != null) translated.add(weather['vis']!);
    if (weather['weather'] != null) translated.add(weather['weather']!);
    if (weather['clouds'] != null) translated.add(weather['clouds']!);

    return translated.join(' ');
  }

  static String _translateFromTime(String code) {
    if (code.length != 7) return code;
    try {
      int day = int.parse(code.substring(2, 4));
      int hour = int.parse(code.substring(4, 6));
      return '$day日$hour时';
    } catch (e) {
      return code;
    }
  }

  static Map<String, String> _parseWeatherElements(List<String> elements) {
    Map<String, String> result = {};
    
    for (String element in elements) {
      if (_isWind(element)) {
        result['wind'] = _translateWind(element);
      } else if (_isVisibility(element)) {
        result['vis'] = _translateTafVisibility(element);
      } else if (_isWeather(element)) {
        result['weather'] = _translateWeatherPhenomena(element);
      } else if (_isCloud(element)) {
        String cloud = _translateCloudCover(element.substring(0, 3));
        int height = int.tryParse(element.substring(3)) ?? 0;
        result['clouds'] = '$cloud ${height * 100}英尺';
      }
    }
    
    return result;
  }

  static bool _isWind(String code) => 
      RegExp(r'^\d{5}(G\d{2})?KT$').hasMatch(code);
  
  static bool _isVisibility(String code) => 
      RegExp(r'^\d{4}$').hasMatch(code) || code == 'CAVOK' || code == '9999';
  
  static bool _isWeather(String code) =>
      RegExp(r'^[+-]?(VC)?(MI|PR|BC|DR|BL|SH|TS|FZ)?'
          r'(DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PO|SQ|FC|SS|DS)$')
          .hasMatch(code);
  
  static bool _isCloud(String code) =>
      code.startsWith('SKC') || code.startsWith('FEW') || 
      code.startsWith('SCT') || code.startsWith('BKN') || 
      code.startsWith('OVC');

  static String _translateWind(String code) {
    try {
      int dir = int.parse(code.substring(0, 3));
      int speed = int.parse(code.substring(3, 5));
      if (code.contains('G')) {
        int gust = int.parse(code.substring(code.indexOf('G') + 1, code.length - 2));
        return '风向$dir度，风速${speed}节，阵风${gust}节';
      }
      return '风向$dir度，风速${speed}节';
    } catch (e) {
      return code;
    }
  }

  static String _translateTafVisibility(String code) {
    if (code == 'CAVOK') return '能见度良好';
    if (code == '9999') return '能见度大于10公里';
    try {
      int vis = int.parse(code);
      return '能见度${vis < 1000 ? vis : vis ~/ 1000}${vis < 1000 ? '米' : '公里'}';
    } catch (e) {
      return code;
    }
  }

  static String _translateWeatherPhenomena(String code) {
    Map<String, String> phenomena = {
      'RA': '雨', 'SN': '雪', 'FG': '雾',
      'BR': '轻雾', 'HZ': '霾', 'TS': '雷暴',
      'DZ': '毛毛雨', 'SH': '阵雨', 'FZ': '冻',
      'GR': '冰雹', 'DU': '扬沙', 'SA': '沙尘',
    };

    String intensity = code.startsWith('+') ? '强' : 
                      code.startsWith('-') ? '弱' : '';
    
    for (var entry in phenomena.entries) {
      if (code.contains(entry.key)) {
        return '$intensity${entry.value}';
      }
    }
    
    return code;
  }
}

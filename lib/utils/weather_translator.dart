import '../models/weather_model.dart';

class WeatherTranslator {
  // METAR翻译主方法
  static String translateMetar(WeatherData data) {
    List<String> parts = [];
    
    // 基本信息
    parts.add('${data.icaoId}机场天气报告');
    parts.add('观测时间：${_formatDateTime(data.reportTime)}');
    
    // 解析原始METAR报文
    String rawMetar = data.rawMetar.trim();
    if (rawMetar.isNotEmpty) {
      MetarParser parser = MetarParser(rawMetar);
      
      // 风向风速
      String? windInfo = parser.getWindInfo();
      if (windInfo != null) {
        parts.add(windInfo);
      }
      
      // 能见度
      String? visibilityInfo = parser.getVisibilityInfo();
      if (visibilityInfo != null) {
        parts.add(visibilityInfo);
      }
      
      // 天气现象
      List<String> weatherPhenomena = parser.getWeatherPhenomena();
      if (weatherPhenomena.isNotEmpty) {
        parts.add('天气现象：${weatherPhenomena.join('、')}');
      }
      
      // 云层信息
      List<String> cloudInfo = parser.getCloudInfo();
      if (cloudInfo.isNotEmpty) {
        parts.add('云层：${cloudInfo.join('、')}');
      }
      
      // 温度露点（优先使用解析的数据）
      String? tempDewInfo = parser.getTemperatureDewpointInfo();
      if (tempDewInfo != null) {
        parts.add(tempDewInfo);
      } else {
        // 备用：使用结构化数据
        if (data.temperature != null) {
          parts.add('温度：${data.temperature}°C');
        }
        if (data.dewpoint != null) {
          parts.add('露点：${data.dewpoint}°C');
        }
      }
      
      // 气压
      String? pressureInfo = parser.getPressureInfo();
      if (pressureInfo != null) {
        parts.add(pressureInfo);
      }
      
      // 跑道视程
      List<String> rvrInfo = parser.getRunwayVisualRangeInfo();
      if (rvrInfo.isNotEmpty) {
        parts.add('跑道视程：${rvrInfo.join('、')}');
      }
    }
    
    return parts.join('\n');
  }

  // TAF翻译主方法
  static String translateTaf(String rawTaf) {
    if (rawTaf.isEmpty) return '无预报信息';
    
    TafParser parser = TafParser(rawTaf);
    return parser.parse();
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}年${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// METAR解析器
class MetarParser {
  final String rawMetar;
  final List<String> parts;
  
  MetarParser(this.rawMetar) : parts = rawMetar.split(RegExp(r'\s+'));
  
  // 获取风向风速信息
  String? getWindInfo() {
    for (String part in parts) {
      // 匹配风向风速格式：09008KT, 00000KT, 24015G25KT, VRB03KT, 04004MPS
      RegExp windPattern = RegExp(r'^(VRB|\d{3})(\d{2})(G(\d{2}))?(KT|MPS)$');
      Match? match = windPattern.firstMatch(part);
      
      if (match != null) {
        String direction = match.group(1)!;
        int speed = int.parse(match.group(2)!);
        String? gustGroup = match.group(4);
        String unit = match.group(5)!;
        
        List<String> windInfo = [];
        
        // 风向
        if (direction == 'VRB') {
          windInfo.add('风向：不定');
        } else if (direction == '000') {
          windInfo.add('风向：静风');
        } else {
          int dir = int.parse(direction);
          String dirText = _getWindDirectionText(dir);
          windInfo.add('风向：${dir}度 ($dirText)');
        }
        
        // 风速
        if (speed == 0) {
          windInfo.add('风速：静风');
        } else {
          String speedUnit = unit == 'MPS' ? '米/秒' : '节';
          int kmhSpeed = unit == 'MPS' ? _convertMpsToKmh(speed) : _convertKnotsToKmh(speed);
          windInfo.add('风速：$speed$speedUnit (${kmhSpeed}公里/小时)');
          
          // 阵风
          if (gustGroup != null) {
            int gust = int.parse(gustGroup);
            int kmhGust = unit == 'MPS' ? _convertMpsToKmh(gust) : _convertKnotsToKmh(gust);
            windInfo.add('阵风：$gust$speedUnit (${kmhGust}公里/小时)');
          }
        }
        
        return windInfo.join('，');
      }
    }
    return null;
  }
  
  // 获取能见度信息
  String? getVisibilityInfo() {
    for (String part in parts) {
      // CAVOK
      if (part == 'CAVOK') {
        return '能见度：CAVOK (天空晴朗，能见度10公里以上，无重要云层)';
      }
      
      // 数字能见度：9999, 1200, 0800等
      if (RegExp(r'^\d{4}$').hasMatch(part)) {
        int vis = int.parse(part);
        if (vis == 9999) {
          return '能见度：10公里以上';
        } else {
          double visKm = vis / 1000.0;
          String warning = vis <= 5000 ? ' (能见度较低)' : '';
          return '能见度：${visKm.toStringAsFixed(1)}公里$warning';
        }
      }
      
      // 分数能见度：1/2SM, 3/4SM等
      if (RegExp(r'^\d+/\d+SM$').hasMatch(part)) {
        return '能见度：$part';
      }
      
      // 小数能见度：1.5SM, 2.5SM等
      if (RegExp(r'^\d+\.\d+SM$').hasMatch(part)) {
        return '能见度：$part';
      }
    }
    return null;
  }
  
  // 获取天气现象
  List<String> getWeatherPhenomena() {
    List<String> phenomena = [];
    
    for (String part in parts) {
      if (_isWeatherPhenomena(part)) {
        String translated = _translateWeatherPhenomena(part);
        if (translated.isNotEmpty) {
          phenomena.add(translated);
        }
      }
    }
    
    return phenomena;
  }
  
  // 获取云层信息
  List<String> getCloudInfo() {
    List<String> clouds = [];
    
    for (String part in parts) {
      if (_isCloudLayer(part)) {
        String translated = _translateCloudLayer(part);
        if (translated.isNotEmpty) {
          clouds.add(translated);
        }
      }
    }
    
    return clouds;
  }
  
  // 获取温度露点信息
  String? getTemperatureDewpointInfo() {
    for (String part in parts) {
      // 匹配温度露点格式：M04/M10, 15/08, 22/M05等
      RegExp tempPattern = RegExp(r'^(M?\d{2})/(M?\d{2})$');
      Match? match = tempPattern.firstMatch(part);
      
      if (match != null) {
        String tempStr = match.group(1)!;
        String dewStr = match.group(2)!;
        
        int temp = _parseTemperature(tempStr);
        int dew = _parseTemperature(dewStr);
        
        return '温度：${temp}°C，露点：${dew}°C';
      }
    }
    return null;
  }
  
  // 获取气压信息
  String? getPressureInfo() {
    for (String part in parts) {
      // QNH格式：Q1013, A2992等
      if (RegExp(r'^Q\d{4}$').hasMatch(part)) {
        String pressure = part.substring(1);
        return 'QNH：${pressure} hPa';
      }
      
      if (RegExp(r'^A\d{4}$').hasMatch(part)) {
        String pressure = part.substring(1);
        double inHg = int.parse(pressure) / 100.0;
        int hPa = (inHg * 33.8639).round();
        return 'QNH：${inHg.toStringAsFixed(2)} inHg (${hPa} hPa)';
      }
    }
    return null;
  }
  
  // 获取跑道视程信息
  List<String> getRunwayVisualRangeInfo() {
    List<String> rvrInfo = [];
    
    for (String part in parts) {
      // RVR格式：R06/1200V1800FT, R24/0600FT等
      if (part.startsWith('R') && part.contains('/')) {
        RegExp rvrPattern = RegExp(r'^R(\d{2}[LCR]?)/(\d{4})(V(\d{4}))?(FT|M)?$');
        Match? match = rvrPattern.firstMatch(part);
        
        if (match != null) {
          String runway = match.group(1)!;
          String vis1 = match.group(2)!;
          String? vis2 = match.group(4);
          String unit = match.group(5) ?? 'M';
          
          String unitText = unit == 'FT' ? '英尺' : '米';
          
          if (vis2 != null) {
            rvrInfo.add('跑道${runway}：${vis1}-${vis2}${unitText}');
          } else {
            rvrInfo.add('跑道${runway}：${vis1}${unitText}');
          }
        }
      }
    }
    
    return rvrInfo;
  }
  
  // 判断是否为天气现象
  bool _isWeatherPhenomena(String code) {
    // 天气现象的正则表达式
    RegExp pattern = RegExp(r'^[+-]?(VC)?(MI|PR|BC|DR|BL|SH|TS|FZ)?(DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PO|SQ|FC|SS|DS)+$');
    return pattern.hasMatch(code);
  }
  
  // 判断是否为云层
  bool _isCloudLayer(String code) {
    return RegExp(r'^(SKC|CLR|NSC|NCD|FEW|SCT|BKN|OVC|VV)(\d{3})?(TCU|CB)?$').hasMatch(code) ||
           ['SKC', 'CLR', 'NSC', 'NCD'].contains(code);
  }
  
  // 翻译天气现象
  String _translateWeatherPhenomena(String code) {
    String result = '';
    String remaining = code;
    
    // 强度前缀
    if (remaining.startsWith('+')) {
      result += '强';
      remaining = remaining.substring(1);
    } else if (remaining.startsWith('-')) {
      result += '弱';
      remaining = remaining.substring(1);
    }
    
    // 附近标识
    bool isVicinity = false;
    if (remaining.startsWith('VC')) {
      isVicinity = true;
      remaining = remaining.substring(2);
    }
    
    // 描述符
    Map<String, String> descriptors = {
      'MI': '浅', 'PR': '部分', 'BC': '散片', 'DR': '低吹',
      'BL': '高吹', 'SH': '阵', 'TS': '雷暴', 'FZ': '冻'
    };
    
    for (var entry in descriptors.entries) {
      if (remaining.startsWith(entry.key)) {
        result += entry.value;
        remaining = remaining.substring(entry.key.length);
        break;
      }
    }
    
    // 天气现象
    Map<String, String> phenomena = {
      'DZ': '毛毛雨', 'RA': '雨', 'SN': '雪', 'SG': '雪粒',
      'IC': '冰晶', 'PL': '冰粒', 'GR': '冰雹', 'GS': '小冰雹',
      'UP': '未知降水', 'BR': '轻雾', 'FG': '雾', 'FU': '烟',
      'VA': '火山灰', 'DU': '扬沙', 'SA': '沙', 'HZ': '霾',
      'PO': '尘卷风', 'SQ': '飑', 'FC': '漏斗云', 'SS': '沙暴',
      'DS': '尘暴'
    };
    
    // 可能有多个天气现象组合
    for (var entry in phenomena.entries) {
      if (remaining.contains(entry.key)) {
        result += entry.value;
        remaining = remaining.replaceFirst(entry.key, '');
      }
    }
    
    if (isVicinity) {
      result += '(附近)';
    }
    
    return result.isEmpty ? code : result;
  }
  
  // 翻译云层
  String _translateCloudLayer(String code) {
    // 特殊云层代码
    Map<String, String> specialClouds = {
      'SKC': '晴空', 'CLR': '晴空', 'NSC': '无重要云层', 'NCD': '无云'
    };
    
    if (specialClouds.containsKey(code)) {
      return specialClouds[code]!;
    }
    
    // 解析云层覆盖度和高度
    RegExp pattern = RegExp(r'^(FEW|SCT|BKN|OVC|VV)(\d{3})(TCU|CB)?$');
    Match? match = pattern.firstMatch(code);
    
    if (match != null) {
      String cover = match.group(1)!;
      String height = match.group(2)!;
      String? type = match.group(3);
      
      Map<String, String> coverTypes = {
        'FEW': '少量(1-2成)', 'SCT': '疏云(3-4成)',
        'BKN': '多云(5-7成)', 'OVC': '阴天(8成以上)',
        'VV': '垂直能见度'
      };
      
      String coverText = coverTypes[cover] ?? cover;
      int heightFt = int.parse(height) * 100;
      int heightM = (heightFt * 0.3048).round();
      
      String result = '$coverText ${heightFt}英尺(${heightM}米)';
      
      if (type == 'TCU') {
        result += ' 塔状积云';
      } else if (type == 'CB') {
        result += ' 积雨云';
      }
      
      return result;
    }
    
    return code;
  }
  
  // 解析温度（处理负温度M前缀）
  int _parseTemperature(String tempStr) {
    if (tempStr.startsWith('M')) {
      return -int.parse(tempStr.substring(1));
    } else {
      return int.parse(tempStr);
    }
  }
  
  // 获取风向文字描述
  String _getWindDirectionText(int direction) {
    if (direction < 0 || direction > 360) return '无效风向';
    
    final directions = [
      '北', '北东北', '东北', '东东北', 
      '东', '东东南', '东南', '南东南',
      '南', '南西南', '西南', '西西南', 
      '西', '西西北', '西北', '北西北'
    ];
    
    int index = ((direction + 11.25) % 360) ~/ 22.5;
    return directions[index % 16];
  }
  
  // 节转公里/小时
  int _convertKnotsToKmh(int knots) {
    return (knots * 1.852).round();
  }
  
  // 米/秒转公里/小时
  int _convertMpsToKmh(int mps) {
    return (mps * 3.6).round();
  }
}

// TAF解析器
class TafParser {
  final String rawTaf;
  final List<String> lines;
  
  TafParser(this.rawTaf) : lines = rawTaf.split('\n').where((line) => line.trim().isNotEmpty).toList();
  
  String parse() {
    if (lines.isEmpty) return '无预报信息';
    
    List<String> result = [];
    
    for (String line in lines) {
      String translated = _parseTafLine(line.trim());
      if (translated.isNotEmpty) {
        result.add(translated);
      }
    }
    
    return result.join('\n\n');
  }
  
  String _parseTafLine(String line) {
    if (line.isEmpty) return '';
    
    List<String> parts = line.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '预报解析失败';
    
    // 移除TAF标识
    if (parts[0] == 'TAF') {
      parts = parts.sublist(1);
    }
    
    if (parts.isEmpty) return '预报解析失败';
    
    List<String> translated = [];
    
    // 机场代码
    if (parts.isNotEmpty && RegExp(r'^[A-Z]{4}$').hasMatch(parts[0])) {
      translated.add('${parts[0]}机场天气预报');
      parts = parts.sublist(1);
    }
    
    // 发布时间
    if (parts.isNotEmpty && RegExp(r'^\d{6}Z$').hasMatch(parts[0])) {
      String timeStr = _parseDateTime(parts[0]);
      translated.add('发布时间：$timeStr');
      parts = parts.sublist(1);
    }
    
    // 有效时段
    if (parts.isNotEmpty && RegExp(r'^\d{4}/\d{4}$').hasMatch(parts[0])) {
      String periodStr = _parseValidPeriod(parts[0]);
      translated.add('有效时段：$periodStr');
      parts = parts.sublist(1);
    }
    
    // 解析预报内容
    if (parts.isNotEmpty) {
      TafContentParser contentParser = TafContentParser(parts);
      String content = contentParser.parse();
      if (content.isNotEmpty) {
        translated.add(content);
      }
    }
    
    return translated.join('\n');
  }
  
  String _parseDateTime(String timeStr) {
    if (timeStr.length != 7 || !timeStr.endsWith('Z')) return timeStr;
    
    try {
      int day = int.parse(timeStr.substring(0, 2));
      int hour = int.parse(timeStr.substring(2, 4));
      int minute = int.parse(timeStr.substring(4, 6));
      return '$day日$hour时${minute}分UTC';
    } catch (e) {
      return timeStr;
    }
  }
  
  String _parseValidPeriod(String periodStr) {
    if (periodStr.length != 9 || !periodStr.contains('/')) return periodStr;
    
    try {
      List<String> parts = periodStr.split('/');
      int fromDay = int.parse(parts[0].substring(0, 2));
      int fromHour = int.parse(parts[0].substring(2, 4));
      int toDay = int.parse(parts[1].substring(0, 2));
      int toHour = int.parse(parts[1].substring(2, 4));
      
      return '$fromDay日${fromHour}时 至 $toDay日${toHour}时';
    } catch (e) {
      return periodStr;
    }
  }
}

// TAF内容解析器
class TafContentParser {
  final List<String> parts;
  int currentIndex = 0;
  
  TafContentParser(this.parts);
  
  String parse() {
    List<String> result = [];
    
    while (currentIndex < parts.length) {
      String part = parts[currentIndex];
      
      if (_isChangeIndicator(part)) {
        String changeInfo = _parseChangeGroup();
        if (changeInfo.isNotEmpty) {
          result.add(changeInfo);
        }
      } else {
        // 基本预报
        String basicForecast = _parseBasicForecast();
        if (basicForecast.isNotEmpty) {
          result.add('基本预报：$basicForecast');
        }
      }
    }
    
    return result.join('\n');
  }
  
  String _parseBasicForecast() {
    List<String> forecastParts = [];
    
    while (currentIndex < parts.length && !_isChangeIndicator(parts[currentIndex])) {
      forecastParts.add(parts[currentIndex]);
      currentIndex++;
    }
    
    return _translateWeatherGroup(forecastParts);
  }
  
  String _parseChangeGroup() {
    if (currentIndex >= parts.length) return '';
    
    String changeType = parts[currentIndex];
    currentIndex++;
    
    List<String> changeParts = [];
    while (currentIndex < parts.length && !_isChangeIndicator(parts[currentIndex])) {
      changeParts.add(parts[currentIndex]);
      currentIndex++;
    }
    
    String changeTypeText = _translateChangeType(changeType);
    String changeContent = _translateWeatherGroup(changeParts);
    
    return '$changeTypeText：$changeContent';
  }
  
  bool _isChangeIndicator(String part) {
    return part.startsWith('BECMG') || 
           part.startsWith('TEMPO') || 
           part.startsWith('FM') || 
           part.startsWith('PROB');
  }
  
  String _translateChangeType(String changeType) {
    if (changeType.startsWith('BECMG')) {
      return '逐渐变化';
    } else if (changeType.startsWith('TEMPO')) {
      return '短时变化';
    } else if (changeType.startsWith('FM')) {
      return '从${_parseFromTime(changeType)}起';
    } else if (changeType.startsWith('PROB')) {
      String prob = changeType.length >= 6 ? changeType.substring(4, 6) : '??';
      return '概率${prob}%';
    }
    return changeType;
  }
  
  String _parseFromTime(String fmCode) {
    if (!fmCode.startsWith('FM') || fmCode.length < 8) return fmCode;
    
    try {
      int day = int.parse(fmCode.substring(2, 4));
      int hour = int.parse(fmCode.substring(4, 6));
      int minute = int.parse(fmCode.substring(6, 8));
      return '$day日$hour时${minute}分';
    } catch (e) {
      return fmCode;
    }
  }
  
  String _translateWeatherGroup(List<String> group) {
    if (group.isEmpty) return '';
    
    List<String> result = [];
    
    // 使用METAR解析器来解析天气组
    String groupStr = group.join(' ');
    MetarParser parser = MetarParser(groupStr);
    
    // 风向风速
    String? wind = parser.getWindInfo();
    if (wind != null) {
      result.add(wind);
    }
    
    // 能见度
    String? visibility = parser.getVisibilityInfo();
    if (visibility != null) {
      result.add(visibility);
    }
    
    // 天气现象
    List<String> weather = parser.getWeatherPhenomena();
    if (weather.isNotEmpty) {
      result.add('天气现象：${weather.join('、')}');
    }
    
    // 云层
    List<String> clouds = parser.getCloudInfo();
    if (clouds.isNotEmpty) {
      result.add('云层：${clouds.join('、')}');
    }
    
    return result.join('，');
  }
}

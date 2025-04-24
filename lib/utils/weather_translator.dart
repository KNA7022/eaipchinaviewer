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
      String windDirectionText = _getWindDirectionText(data.windDirection!);
      parts.add('风向：${data.windDirection}度 ($windDirectionText)');
      parts.add('风速：${data.windSpeed}节 (${_convertKnotsToKmh(data.windSpeed!)}公里/小时)');
    } else if (data.windDirection == 0 && data.windSpeed == 0) {
      parts.add('风向风速：静风');
    } else if (data.windDirection == null && data.windSpeed != null) {
      parts.add('风速：${data.windSpeed}节 (${_convertKnotsToKmh(data.windSpeed!)}公里/小时)');
    }
    
    // 能见度
    parts.add('能见度：${_translateVisibility(data.visibility)}');
    
    // 云层
    if (data.clouds.isNotEmpty) {
      parts.add('云层：${_translateClouds(data.clouds)}');
    }
    
    // 解析METAR中的特殊天气现象
    String rawMetar = data.rawMetar;
    List<String> weatherPhenomena = _extractWeatherPhenomena(rawMetar);
    if (weatherPhenomena.isNotEmpty) {
      parts.add('天气现象：${weatherPhenomena.join('、')}');
    }
    
    // QNH (气压)
    String? qnh = _extractQNH(rawMetar);
    if (qnh != null) {
      parts.add('QNH：$qnh hPa');
    }
    
    return parts.join('\n');
  }

  static String translateTaf(String rawTaf) {
    if (rawTaf.isEmpty) return '无预报信息';
    
    List<String> lines = rawTaf.split('\n');
    List<String> result = [];
    
    for (String line in lines) {
      result.add(_translateTafLine(line));
    }
    
    return result.join('\n\n');
  }
  
  static String _translateTafLine(String line) {
    if (line.trim().isEmpty) return '';
    
    List<String> parts = line.split(' ');
    if (parts.isEmpty) return '预报解析失败';

    // 如果第一个词是TAF，则移除它
    if (parts[0] == 'TAF') {
      parts = parts.sublist(1);
    }
    if (parts.isEmpty) return '预报解析失败';

    List<String> translated = ['天气预报：'];
    
    // 机场和发布时间
    String icao = parts[0];
    translated.add('$icao机场');
    
    if (parts.length > 1) {
      String issueTime = _translateDateTime(parts[1]);
      translated.add('发布时间：$issueTime');
    }

    // 预报有效时段
    if (parts.length > 2 && _isValidPeriod(parts[2])) {
      String validPeriod = _translateValidPeriod(parts[2]);
      translated.add('预报时段：$validPeriod');
      parts = parts.sublist(3);
    } else {
      parts = parts.sublist(2);
    }

    // 找出基本预报部分和变化部分的分界点
    int changeIndex = _findFirstChangeIndex(parts);
    
    // 处理基本预报
    if (changeIndex > 0) {
      List<String> baseForecast = parts.sublist(0, changeIndex);
      translated.add('\n预报：${_translateWeatherGroup(baseForecast)}');
      
      // 提取并翻译温度信息
      List<String> tempInfo = _extractTemperatureInfo(parts);
      if (tempInfo.isNotEmpty) {
        translated.add('\n${tempInfo.join("，")}');
      }
      
      parts = parts.sublist(changeIndex);
    } else if (changeIndex == -1) {
      // 没有变化部分，整个都是基本预报
      List<String> baseForecast = parts;
      translated.add('\n预报：${_translateWeatherGroup(baseForecast)}');
      
      // 提取并翻译温度信息
      List<String> tempInfo = _extractTemperatureInfo(parts);
      if (tempInfo.isNotEmpty) {
        translated.add('\n${tempInfo.join("，")}');
      }
      
      return translated.join('\n');
    }

    // 处理变化部分
    while (parts.isNotEmpty) {
      int nextChangeIndex = _findNextChangeIndex(parts);
      List<String> changeGroup;
      
      if (nextChangeIndex > 0) {
        changeGroup = parts.sublist(0, nextChangeIndex);
        parts = parts.sublist(nextChangeIndex);
      } else {
        changeGroup = parts;
        parts = [];
      }
      
      translated.add(_translateChangeGroup(changeGroup));
    }

    return translated.join('\n');
  }

  // 寻找第一个变化标记的位置
  static int _findFirstChangeIndex(List<String> parts) {
    for (int i = 0; i < parts.length; i++) {
      if (_isChangeIndicator(parts[i])) {
        return i;
      }
    }
    return -1;
  }
  
  // 寻找下一个变化标记的位置
  static int _findNextChangeIndex(List<String> parts) {
    if (parts.isEmpty) return -1;
    
    // 跳过第一个变化标记
    for (int i = 1; i < parts.length; i++) {
      if (_isChangeIndicator(parts[i])) {
        return i;
      }
    }
    return -1;
  }
  
  // 判断是否是变化标记
  static bool _isChangeIndicator(String part) {
    return part.startsWith('BECMG') || 
           part.startsWith('TEMPO') || 
           part.startsWith('FM') || 
           part.startsWith('PROB');
  }
  
  // 翻译基本天气组
  static String _translateWeatherGroup(List<String> group) {
    List<String> result = [];
    
    // 处理风向风速
    String? wind = _findAndTranslateWind(group, 0);
    if (wind != null) {
      result.add(wind);
    }
    
    // 处理能见度
    String? visibility = _findAndTranslateVisibility(group, 0);
    if (visibility != null) {
      result.add(visibility);
    }
    
    // 处理天气现象
    List<String> wxPhenomena = _findAndTranslateWeatherPhenomena(group, 0);
    if (wxPhenomena.isNotEmpty) {
      result.add('天气现象：${wxPhenomena.join('、')}');
    }
    
    // 处理云层
    List<String> clouds = _findAndTranslateClouds(group, 0);
    if (clouds.isNotEmpty) {
      result.add('云层：${clouds.join('、')}');
    }
    
    return result.join(' ');
  }
  
  // 翻译变化组
  static String _translateChangeGroup(List<String> group) {
    if (group.isEmpty) return '';
    
    String changeType = group[0];
    List<String> result = [];
    
    if (changeType.startsWith('BECMG')) {
      // 处理BECMG (Becoming) 格式
      String period = _translatePeriod(changeType.substring(5));
      result.add('\n逐渐变化${period.isNotEmpty ? period : ''}：');
      result.add(_translateWeatherGroup(group.sublist(1)));
    } else if (changeType.startsWith('TEMPO')) {
      // 处理TEMPO (Temporarily) 格式
      String period = _translatePeriod(changeType.substring(5));
      result.add('\n短时${period.isNotEmpty ? period : ''}：');
      result.add(_translateWeatherGroup(group.sublist(1)));
    } else if (changeType.startsWith('FM')) {
      // 处理FM (From) 格式
      String time = _translateFromTime(changeType);
      result.add('\n从$time起：');
      result.add(_translateWeatherGroup(group.sublist(1)));
    } else if (changeType.startsWith('PROB')) {
      // 处理PROB (Probability) 格式
      String prob = changeType.substring(4, 6);
      
      if (group.length > 1 && group[1].startsWith('TEMPO')) {
        result.add('\n概率$prob%短时：');
        result.add(_translateWeatherGroup(group.sublist(2)));
      } else {
        result.add('\n概率$prob%：');
        result.add(_translateWeatherGroup(group.sublist(1)));
      }
    }
    
    return result.join(' ');
  }
  
  // 翻译时间段
  static String _translatePeriod(String period) {
    if (period.length != 9) return '';
    try {
      int fromDay = int.parse(period.substring(0, 2));
      int fromHour = int.parse(period.substring(2, 4));
      int toDay = int.parse(period.substring(5, 7));
      int toHour = int.parse(period.substring(7, 9));
      return '($fromDay日$fromHour时至$toDay日$toHour时)';
    } catch (e) {
      return '';
    }
  }
  
  // 提取并翻译温度信息
  static List<String> _extractTemperatureInfo(List<String> parts) {
    List<String> result = [];
    
    for (String part in parts) {
      if (part.startsWith('TX')) {
        try {
          // 例如 TX26/2508Z
          String temp = part.substring(2, part.indexOf('/'));
          String timeCode = part.substring(part.indexOf('/') + 1, part.length - 1);
          int day = int.parse(timeCode.substring(0, 2));
          int hour = int.parse(timeCode.substring(2, 4));
          result.add('最高温度：${temp}°C ($day日$hour时)');
        } catch (e) {
          result.add('最高温度：$part');
        }
      } else if (part.startsWith('TN')) {
        try {
          // 例如 TN11/2423Z
          String temp = part.substring(2, part.indexOf('/'));
          String timeCode = part.substring(part.indexOf('/') + 1, part.length - 1);
          int day = int.parse(timeCode.substring(0, 2));
          int hour = int.parse(timeCode.substring(2, 4));
          result.add('最低温度：${temp}°C ($day日$hour时)');
        } catch (e) {
          result.add('最低温度：$part');
        }
      }
    }
    
    return result;
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}年${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _translateFromTime(String code) {
    if (!code.startsWith('FM') || code.length < 6) return code;
    try {
      int day = int.parse(code.substring(2, 4));
      int hour = int.parse(code.substring(4, 6));
      int minute = code.length >= 8 ? int.parse(code.substring(6, 8)) : 0;
      return '$day日$hour时${minute > 0 ? '$minute分' : ''}';
    } catch (e) {
      return code;
    }
  }

  static String? _findAndTranslateWind(List<String> parts, int startIndex) {
    for (int i = startIndex; i < parts.length; i++) {
      if (_isWind(parts[i])) {
        return _translateWind(parts[i]);
      }
    }
    return null;
  }

  static bool _isWind(String code) {
    // 匹配风向风速格式，例如 09008KT, 00000KT, 24015G25KT, VRB03KT
    // 以及MPS格式：04004MPS, 23010G16MPS
    return RegExp(r'^(VRB|\d{3})\d{2}(G\d{2})?(KT|MPS)$').hasMatch(code);
  }

  static String _translateWind(String code) {
    try {
      String dirPart = code.substring(0, 3);
      int speed = int.parse(code.substring(3, 5));
      bool isMPS = code.contains('MPS');
      
      String dirText;
      if (dirPart == 'VRB') {
        dirText = '风向不定';
      } else {
        int dir = int.parse(dirPart);
        dirText = '风向${dir}度 (${_getWindDirectionText(dir)})';
      }
      
      String speedUnit = isMPS ? '米/秒' : '节';
      int kmhSpeed = isMPS ? _convertMpsToKmh(speed) : _convertKnotsToKmh(speed);
      String speedText = '风速$speed$speedUnit ($kmhSpeed公里/小时)';
      
      if (code.contains('G')) {
        int gust = int.parse(code.substring(code.indexOf('G') + 1, code.indexOf(isMPS ? 'M' : 'K')));
        int kmhGust = isMPS ? _convertMpsToKmh(gust) : _convertKnotsToKmh(gust);
        return '$dirText，$speedText，阵风$gust$speedUnit ($kmhGust公里/小时)';
      }
      
      return '$dirText，$speedText';
    } catch (e) {
      return '风：$code';
    }
  }

  // 将米/秒转换为公里/小时
  static int _convertMpsToKmh(int mps) {
    return (mps * 3.6).round();
  }

  static String _translateVisibility(String vis) {
    if (vis == '10+' || vis == '9999') return '大于10千米';
    if (vis == 'CAVOK') return '能见度良好，无云层';
    if (vis == 'NA') return '不可用';
    
    try {
      double visValue = double.parse(vis);
      // 小于等于5000米时需要特别注意
      if (visValue <= 5) {
        return '$vis千米 (能见度较低)';
      }
      return '$vis千米';
    } catch (e) {
      return '$vis';
    }
  }

  static String _translateClouds(List<Cloud> clouds) {
    return clouds.map((cloud) {
      String cover = _translateCloudCover(cloud.cover);
      int heightMeters = (cloud.base * 30.48).round(); // 英尺转米
      return '$cover ${cloud.base}英尺 ($heightMeters米)';
    }).join('，');
  }

  static String _translateCloudCover(String cover) {
    switch (cover.toUpperCase()) {
      case 'SKC': return '晴空';
      case 'CLR': return '晴空';
      case 'NCD': return '无云';
      case 'NSC': return '无重要云层';
      case 'FEW': return '少量 (1-2成)';
      case 'SCT': return '疏云 (3-4成)';
      case 'BKN': return '多云 (5-7成)';
      case 'OVC': return '阴天 (8成以上)';
      case 'VV': return '垂直能见度';
      case 'TCU': return '塔状积云';
      case 'CB': return '积雨云';
      default: return cover;
    }
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

  static bool _isValidPeriod(String code) {
    return code.length == 9 && code.contains('/');
  }

  static String _translateValidPeriod(String code) {
    if (code.length != 9 || !code.contains('/')) return code;
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

  static List<String> _findAndTranslateWeatherPhenomena(List<String> parts, int startIndex) {
    List<String> result = [];
    for (int i = startIndex; i < parts.length; i++) {
      if (_isWeather(parts[i])) {
        result.add(_translateWeatherPhenomena(parts[i]));
      }
    }
    return result;
  }

  static List<String> _findAndTranslateClouds(List<String> parts, int startIndex) {
    List<String> result = [];
    for (int i = startIndex; i < parts.length; i++) {
      if (_isCloud(parts[i])) {
        String cover = _translateCloudCover(parts[i].substring(0, 3));
        int height = int.tryParse(parts[i].substring(3)) ?? 0;
        int heightMeters = (height * 30.48).round(); // 英尺转米
        result.add('$cover ${height * 100}英尺 ($heightMeters米)');
      }
    }
    return result;
  }

  static bool _isVisibility(String code) {
    // 匹配能见度格式，例如 9999, 1000, CAVOK
    return RegExp(r'^\d{4}$').hasMatch(code) || code == 'CAVOK' || code == '9999';
  }
  
  static bool _isWeather(String code) {
    // 匹配天气现象格式
    return RegExp(r'^[+-]?(VC)?(MI|PR|BC|DR|BL|SH|TS|FZ)?'
        r'(DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PO|SQ|FC|SS|DS)').hasMatch(code);
  }
  
  static bool _isCloud(String code) {
    // 匹配云层格式，例如 FEW020, BKN030, OVC100, SKC, NSC
    return code.startsWith('FEW') || code.startsWith('SCT') || 
           code.startsWith('BKN') || code.startsWith('OVC') ||
           code == 'SKC' || code == 'NSC' || code == 'CLR' || code == 'NCD';
  }

  static String _translateWeatherPhenomena(String code) {
    // 强度前缀
    String intensity = '';
    if (code.startsWith('+')) {
      intensity = '强';
      code = code.substring(1);
    } else if (code.startsWith('-')) {
      intensity = '弱';
      code = code.substring(1);
    }
    
    // 附近天气
    bool isVicinity = false;
    if (code.startsWith('VC')) {
      isVicinity = true;
      code = code.substring(2);
    }
    
    // 描述符
    String descriptor = '';
    if (code.startsWith('MI')) { // 浅
      descriptor = '浅';
      code = code.substring(2);
    } else if (code.startsWith('PR')) { // 部分
      descriptor = '部分';
      code = code.substring(2);
    } else if (code.startsWith('BC')) { // 散片
      descriptor = '散片';
      code = code.substring(2);
    } else if (code.startsWith('DR')) { // 低吹
      descriptor = '低吹';
      code = code.substring(2);
    } else if (code.startsWith('BL')) { // 高吹
      descriptor = '高吹';
      code = code.substring(2);
    } else if (code.startsWith('SH')) { // 阵
      descriptor = '阵';
      code = code.substring(2);
    } else if (code.startsWith('TS')) { // 雷暴
      descriptor = '雷暴';
      code = code.substring(2);
    } else if (code.startsWith('FZ')) { // 冻
      descriptor = '冻';
      code = code.substring(2);
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
    
    String weather = '';
    for (var entry in phenomena.entries) {
      if (code.contains(entry.key)) {
        weather = entry.value;
        break;
      }
    }
    
    if (weather.isEmpty) return code; // 无法识别的天气现象
    
    String result = intensity + descriptor + weather;
    if (isVicinity) {
      result += '(附近)';
    }
    
    return result;
  }
  
  // 从METAR中提取天气现象
  static List<String> _extractWeatherPhenomena(String rawMetar) {
    List<String> parts = rawMetar.split(' ');
    List<String> phenomena = [];
    
    for (String part in parts) {
      if (_isWeather(part)) {
        phenomena.add(_translateWeatherPhenomena(part));
      }
    }
    
    return phenomena;
  }
  
  // 从METAR中提取气压值
  static String? _extractQNH(String rawMetar) {
    List<String> parts = rawMetar.split(' ');
    
    for (String part in parts) {
      if (part.startsWith('Q') && part.length == 5) {
        try {
          return part.substring(1);
        } catch (e) {
          return null;
        }
      }
    }
    
    return null;
  }
  
  // 根据风向角度获取风向文字描述
  static String _getWindDirectionText(int direction) {
    if (direction < 0 || direction > 360) return '无效风向';
    
    final directions = [
      '北', '北东北', '东北', '东东北', 
      '东', '东东南', '东南', '南东南',
      '南', '南西南', '西南', '西西南', 
      '西', '西西北', '西北', '北西北', '北'
    ];
    
    // 将360度分成16个部分，每个部分22.5度
    int index = ((direction + 11.25) % 360) ~/ 22.5;
    return directions[index];
  }
  
  // 将节转换为公里/小时
  static int _convertKnotsToKmh(int knots) {
    return (knots * 1.852).round();
  }

  static String? _findAndTranslateVisibility(List<String> parts, int startIndex) {
    for (int i = startIndex; i < parts.length; i++) {
      if (_isVisibility(parts[i])) {
        return '能见度：${_translateTafVisibility(parts[i])}';
      }
    }
    return null;
  }

  static String _translateTafVisibility(String code) {
    if (code == 'CAVOK') return '能见度良好，无云层';
    if (code == '9999') return '大于10公里';
    
    try {
      int vis = int.parse(code);
      double visKm = vis / 1000.0;
      
      if (visKm <= 5) {
        return '${visKm}公里 (能见度较低)';
      }
      
      return '${visKm}公里';
    } catch (e) {
      return code;
    }
  }
}

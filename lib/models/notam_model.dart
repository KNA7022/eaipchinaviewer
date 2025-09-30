import 'package:intl/intl.dart';

/// NOTAM数据模型
class NotamItem {
  final String seriesName;
  final String document;
  final DateTime generateTime;
  final String generateTimeEn;

  NotamItem({
    required this.seriesName,
    required this.document,
    required this.generateTime,
    required this.generateTimeEn,
  });

  /// 从JSON数据创建NotamItem实例
  factory NotamItem.fromJson(Map<String, dynamic> json) {
    // 解析生成时间
    final generateTime = DateFormat('yyyy-MM-dd HH:mm').parse(json['GenerateTime'] as String);

    return NotamItem(
      seriesName: json['SeriesName'] as String,
      document: json['Document'] as String,
      generateTime: generateTime,
      generateTimeEn: json['GenerateTime_En'] as String,
    );
  }

  /// 格式化生成时间为本地时间字符串
  String get formattedGenerateTime {
    return DateFormat('yyyy-MM-dd HH:mm').format(generateTime);
  }
}
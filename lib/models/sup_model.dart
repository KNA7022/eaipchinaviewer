import 'package:intl/intl.dart';
import '../services/api_service.dart';

class SupItem {
  final String id;
  final String document;
  final String chapterType;
  final String serial;
  final String subject;
  final String localSubject;
  final String isModified;
  final DateTime effectiveTime;
  final DateTime? outDate;
  final DateTime pubDate;
  String? pdfUrl;

  SupItem({
    required this.id,
    required this.document,
    required this.chapterType,
    required this.serial,
    required this.subject,
    required this.localSubject,
    required this.isModified,
    required this.effectiveTime,
    this.outDate,
    required this.pubDate,
    this.pdfUrl,
  });

  factory SupItem.fromJson(Map<String, dynamic> json) {
    // 处理生效时间
    DateTime parseEffectiveTime(String timeStr) {
      if (timeStr == 'WIE') {
        return DateTime.now();
      }
      // 处理时间戳格式 (例如: "2509031600")
      if (timeStr.length == 10 && RegExp(r'^\d+$').hasMatch(timeStr)) {
        final year = int.parse(timeStr.substring(0, 2)) + 2000;
        final month = int.parse(timeStr.substring(2, 4));
        final day = int.parse(timeStr.substring(4, 6));
        final hour = int.parse(timeStr.substring(6, 8));
        final minute = int.parse(timeStr.substring(8, 10));
        return DateTime(year, month, day, hour, minute);
      }
      // 如果都不匹配，尝试直接解析
      return DateTime.tryParse(timeStr) ?? DateTime.now();
    }

    // 处理失效时间
    DateTime? parseOutDate(String? dateStr) {
      if (dateStr == null || dateStr.isEmpty) return null;
      if (dateStr.length == 10 && RegExp(r'^\d+$').hasMatch(dateStr)) {
        final year = int.parse(dateStr.substring(0, 2)) + 2000;
        final month = int.parse(dateStr.substring(2, 4));
        final day = int.parse(dateStr.substring(4, 6));
        final hour = int.parse(dateStr.substring(6, 8));
        final minute = int.parse(dateStr.substring(8, 10));
        return DateTime(year, month, day, hour, minute);
      }
      return DateTime.tryParse(dateStr);
    }

    // 处理发布日期
    DateTime parsePubDate(String dateStr) {
      return DateTime.tryParse(dateStr) ?? DateTime.now();
    }

    final item = SupItem(
      id: json['Id'] ?? '',
      document: json['Document'] ?? '',
      chapterType: json['CHAPTER_TYPE'] ?? '',
      serial: json['Serial'] ?? '',
      subject: json['Subject'] ?? '',
      localSubject: json['Local_Subject'] ?? '',
      isModified: json['IS_MODIFIED'] ?? 'N',
      effectiveTime: parseEffectiveTime(json['Effective_Time'] ?? ''),
      outDate: parseOutDate(json['Out_Date']),
      pubDate: parsePubDate(json['Pub_Date'] ?? ''),
    );

    // 构建PDF URL
    if (item.document.isNotEmpty) {
      final api = ApiService();
      item.pdfUrl = api.buildPdfUrl(item.document);
    }

    return item;
  }

  // 格式化日期时间
  String get formattedEffectiveTime {
    if (effectiveTime.year < 2000) return 'WIE';
    return DateFormat('yyyy-MM-dd HH:mm').format(effectiveTime);
  }

  String get formattedOutDate {
    if (outDate == null) return '长期有效';
    return DateFormat('yyyy-MM-dd HH:mm').format(outDate!);
  }

  String get formattedPubDate {
    return DateFormat('yyyy-MM-dd').format(pubDate);
  }

  // 检查是否过期
  bool get isExpired {
    if (outDate == null) return false;
    return DateTime.now().isAfter(outDate!);
  }

  // 检查是否生效
  bool get isEffective {
    final now = DateTime.now();
    return now.isAfter(effectiveTime) && 
           (outDate == null || now.isBefore(outDate!));
  }

  // 获取状态文本
  String get statusText {
    if (isExpired) return '已失效';
    if (isEffective) return '生效中';
    if (DateTime.now().isBefore(effectiveTime)) return '未生效';
    return '未知状态';
  }

  // 获取章节类型列表
  List<String> get chapterTypes {
    return chapterType.split(',').map((e) => e.trim()).toList();
  }

  // 获取修改状态的布尔值
  bool get isModifiedBool => isModified == 'Y';
}
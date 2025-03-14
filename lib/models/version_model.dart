import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EaipVersion {
  final String name;
  final String status;
  final DateTime effectiveDate;
  final DateTime? deadlineDate;  // 添加失效日期
  final String filePath;

  EaipVersion({
    required this.name,
    required this.status,
    required this.effectiveDate,
    this.deadlineDate,
    required this.filePath,
  });

  factory EaipVersion.fromJson(Map<String, dynamic> json) {
    return EaipVersion(
      name: json['dataName'] ?? '',
      status: json['dataStatus'] ?? '',
      effectiveDate: DateTime.tryParse(json['effectiveTime'] ?? '') ?? DateTime.now(),
      deadlineDate: DateTime.tryParse(json['deadline'] ?? ''),
      filePath: json['filePath'] ?? '',
    );
  }

  bool get isCurrent => status == 'CURRENTLY_ISSUE';

  String get statusText {
    switch (status) {
      case 'CURRENTLY_ISSUE':
        return '当前版本';
      case 'NEXT_ISSUE':
        return '即将生效 (${_formatDate(effectiveDate)})';
      case 'EXPIRED':
        return '已过期 (${_formatDate(deadlineDate ?? effectiveDate)})';
      default:
        return '未知状态';
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MM-dd HH:mm').format(date);
  }

  Color get statusColor {
    switch (status) {
      case 'CURRENTLY_ISSUE':
        return Colors.green;
      case 'NEXT_ISSUE':
        return Colors.blue;
      case 'EXPIRED':
        return Colors.grey;
      default:
        return Colors.black;
    }
  }
}

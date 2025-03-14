import 'dart:convert';
import '../services/api_service.dart';

class AipItem {
  final String nameCn;
  final String isModified;
  final List<AipItem> children;
  final String? pdfPath;


  AipItem({
    required this.nameCn,
    this.isModified = 'N',
    this.children = const [],
    this.pdfPath,
  });

  factory AipItem.fromJson(Map<String, dynamic> json) {
    String? pdfPath;
    if (json['pdfPath'] != null && json['pdfPath'].toString().isNotEmpty) {
      // 直接保存原始PDF路径或已构建的URL
      pdfPath = json['pdfPath'].toString();
      if (!pdfPath.startsWith('http')) {
        final api = ApiService();
        pdfPath = api.buildPdfUrl(pdfPath);
      }
    }

    // 使用 UTF-8 解码中文字符
    final nameCn = _decodeUtf8String(json['name_cn'] ?? '');

    return AipItem(
      nameCn: nameCn,
      isModified: json['Is_Modified'] ?? 'N',
      pdfPath: pdfPath,
      children: (json['children'] as List<dynamic>?)
              ?.map((e) => AipItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  // 添加UTF-8解码方法
  static String _decodeUtf8String(String input) {
    try {
      // 尝试UTF-8解码
      return utf8.decode(input.runes.toList());
    } catch (e) {
      print('UTF-8解码失败: $e');
      return input;
    }
  }

  String? get itemNumber {
    final regex = RegExp(r'(\d+(\.\d+)*)');
    final match = regex.firstMatch(nameCn);
    return match?.group(1);
  }

  // 添加自动生成子项的方法
  void generateSubItems() {
    // 检查是否为可生成子项的类型
    if (nameCn.contains('GEN')) {
      final baseNumber = itemNumber;
      if (baseNumber != null) {
        // 生成子项
        for (var i = 0; i < 3; i++) {
          final subItem = AipItem(
            nameCn: '$nameCn.$i',
            isModified: isModified,
          );
          children.add(subItem);
          
          // 为GEN0再生成子项
          if (nameCn.endsWith('0')) {
            subItem.generateSubItems();
          }
        }
      }
    }
  }
}

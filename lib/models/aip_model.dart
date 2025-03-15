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

  factory AipItem.fromJson(Map<String, dynamic> json, {List<String> parentPath = const []}) {
    // 检查是否需要保留该项目
    if (!_shouldKeepItem(json['name_cn'], parentPath)) {
      return AipItem(nameCn: '', isModified: 'N');
    }

    // 使用 UTF-8 解码中文字符
    final nameCn = _decodeUtf8String(json['name_cn'] ?? '');
    final currentPath = [...parentPath, nameCn];

    // 处理子项，过滤掉空的子项
    final children = (json['children'] as List<dynamic>?)
        ?.map((e) => AipItem.fromJson(e as Map<String, dynamic>, parentPath: currentPath))
        .where((item) => item.nameCn.isNotEmpty) // 过滤掉空项
        .toList() ?? [];

    // 如果当前项没有名称且没有子项，返回空项
    if (nameCn.isEmpty && children.isEmpty) {
      return AipItem(nameCn: '', isModified: 'N');
    }

    String? pdfPath;
    if (json['pdfPath'] != null && json['pdfPath'].toString().isNotEmpty) {
      pdfPath = json['pdfPath'].toString();
      if (!pdfPath.startsWith('http')) {
        final api = ApiService();
        pdfPath = api.buildPdfUrl(pdfPath);
      }
    }

    return AipItem(
      nameCn: nameCn,
      isModified: json['Is_Modified'] ?? 'N',
      pdfPath: pdfPath,
      children: children,
    );
  }

  static bool _shouldKeepItem(String? nameCn, List<String> parentPath) {
    if (nameCn == null) return false;
    
    // 检查ENR章节
    if (nameCn.contains("ENR 6")) {
      return true;
    }
    
    // 检查是否为AD 2机场清单
    if (nameCn.contains("AD 2 机场清单")) {
      return true;
    }
    
    // 检查是否为机场ICAO代码开头的章节
    if (RegExp(r'Z[PBGHLSUWY][A-Z]{2}').hasMatch(nameCn)) {
      return true;
    }
    
    // 如果是航图部分，总是保留父级目录下的所有内容
    bool parentIsChart = parentPath.any((p) => p.contains('机场清单'));
    if (parentIsChart && RegExp(r'Z[PBGHLSUWY][A-Z]{2}-\d[A-Z]?\d?\d?').hasMatch(nameCn)) {
      return true;
    }
    
    return false;
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

  // 获取章节类型权重
  int get sectionWeight {
    if (nameCn.startsWith('GEN')) return 1;
    if (nameCn.startsWith('ENR')) return 2;
    if (nameCn.startsWith('AD')) return 3;
    return 4;
  }

  // 从名称中提取数字
  List<num> getNumbers() {
    final regex = RegExp(r'(\d+(\.\d+)*)');
    final matches = regex.allMatches(nameCn);
    if (matches.isEmpty) return [];
    
    return matches.map((match) {
      final parts = match.group(1)!.split('.');
      return parts.map((part) => num.tryParse(part) ?? 0).toList();
    }).expand((x) => x).toList();
  }

  // 修改 getEnrNumbers 方法，优化提取逻辑
  List<num> getEnrNumbers() {
    if (!nameCn.startsWith('ENR')) return [];
    
    // 更精确的匹配 ENR 数字
    final regex = RegExp(r'ENR\s*(\d+(?:\.\d+)*)');
    final match = regex.firstMatch(nameCn);
    if (match?.group(1) == null) return [];
    
    // 将数字部分按点分割并转换为数值列表
    return match!.group(1)!.split('.')
        .map((s) => num.tryParse(s.trim()) ?? 0)
        .toList();
  }

  // 修改 compareTo 方法实现正确的排序逻辑
  int compareTo(AipItem other) {
    // 如果两者都是 ENR 项，使用特殊规则
    if (nameCn.startsWith('ENR') && other.nameCn.startsWith('ENR')) {
      final aNumbers = getEnrNumbers();
      final bNumbers = other.getEnrNumbers();
      
      // 检查第一个数字是否相同（如 ENR 6）
      if (aNumbers.isNotEmpty && bNumbers.isNotEmpty) {
        final firstNumberCompare = aNumbers[0].compareTo(bNumbers[0]);
        if (firstNumberCompare != 0) return firstNumberCompare;
        
        // 如果第一个数字相同，比较层级深度
        // 更少的层级应该排在前面 (ENR 6.1 应该在 ENR 6.1.1 前面)
        if (aNumbers.length != bNumbers.length) {
          return aNumbers.length.compareTo(bNumbers.length);
        }
        
        // 层级相同时，按照每一级数字大小比较
        for (var i = 1; i < aNumbers.length; i++) {
          final numCompare = aNumbers[i].compareTo(bNumbers[i]);
          if (numCompare != 0) return numCompare;
        }
      }
    }
    
    // 其他情况保持原有排序规则
    final weightCompare = sectionWeight.compareTo(other.sectionWeight);
    if (weightCompare != 0) return weightCompare;
    
    final numbers = getNumbers();
    final otherNumbers = other.getNumbers();
    
    for (var i = 0; i < numbers.length && i < otherNumbers.length; i++) {
      final numCompare = numbers[i].compareTo(otherNumbers[i]);
      if (numCompare != 0) return numCompare;
    }
    
    return nameCn.compareTo(other.nameCn);
  }
}

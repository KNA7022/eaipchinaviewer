import 'dart:convert';
import '../services/api_service.dart';

class AipItem {
  final String nameCn;
  final String isModified;
  List<AipItem> children; // 移除 final
  final String? pdfPath;

  AipItem({
    required this.nameCn,
    this.isModified = 'N',
    List<AipItem>? children, // 改为可选参数
    this.pdfPath,
  }) : children = children ?? []; // 使用非const列表初始化

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
    
    // 检查所有 ENR 6 相关章节
    if (RegExp(r'ENR\s*6(\.\d+)*').hasMatch(nameCn)) {
      return true;
    }
    
    // 如果父路径中包含 ENR 6，则保留所有子项
    if (parentPath.any((p) => RegExp(r'ENR\s*6(\.\d+)*').hasMatch(p))) {
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

  // 从列表中提取 ENR 的章节号
  static List<int> _getEnrSectionNumbers(String nameCn) {
    final regex = RegExp(r'ENR\s*(\d+(?:\.\d+)*)');
    final match = regex.firstMatch(nameCn);
    if (match?.group(1) == null) return [];
    
    return match!.group(1)!.split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList();
  }

  // 构建层级关系
  static List<AipItem> buildHierarchy(List<AipItem> items) {
  final Map<String, AipItem> enrMap = {};
  final List<AipItem> result = [];
  
  print('开始构建层级关系...');
  print('总项目数: ${items.length}');
  
  // 第一步：收集所有 ENR 项并按照章节号排序
  final List<AipItem> enrItems = items
      .where((item) => item.nameCn.startsWith('ENR'))
      .toList();
  
  // 修正排序逻辑：按章节号数字顺序排序
  enrItems.sort((a, b) {
    final aNumbers = _getEnrSectionNumbers(a.nameCn);
    final bNumbers = _getEnrSectionNumbers(b.nameCn);
    for (int i = 0; i < aNumbers.length && i < bNumbers.length; i++) {
      int cmp = aNumbers[i].compareTo(bNumbers[i]);
      if (cmp != 0) return cmp;
    }
    return aNumbers.length.compareTo(bNumbers.length);
  });
  
  // 第二步：将所有 ENR 项添加到映射
  for (var item in enrItems) {
    enrMap[item.nameCn] = AipItem(
      nameCn: item.nameCn,
      isModified: item.isModified,
      pdfPath: item.pdfPath,
      children: [],
    );
    print('添加到映射: ${item.nameCn}');
  }
  
  // 第三步：构建父子关系
  for (var item in enrItems) {
    final numbers = _getEnrSectionNumbers(item.nameCn);
    if (numbers.length > 1) {
      final parentNumbers = numbers.sublist(0, numbers.length - 1);
      AipItem? parent;
      
      // 查找与父级章节号匹配的项
      for (var enrItem in enrItems) {
        final enrNumbers = _getEnrSectionNumbers(enrItem.nameCn);
        if (enrNumbers.length == parentNumbers.length) {
          bool match = true;
          for (int i = 0; i < parentNumbers.length; i++) {
            if (enrNumbers[i] != parentNumbers[i]) {
              match = false;
              break;
            }
          }
          if (match) {
            parent = enrMap[enrItem.nameCn];
            break;
          }
        }
      }
      
      if (parent != null) {
        final child = enrMap[item.nameCn];
        if (child != null) {
          parent.children.add(child);
          print('成功添加子项: ${item.nameCn} -> ${parent.nameCn}');
        }
      } else {
        print('未找到父级项: ${item.nameCn} 的父级章节号 $parentNumbers');
      }
    }
  }
  
  // 第四步：添加顶级项到结果列表
  for (var item in enrItems) {
    final numbers = _getEnrSectionNumbers(item.nameCn);
    if (numbers.length == 1) {
      result.add(enrMap[item.nameCn]!);
      print('添加顶级项到结果: ${item.nameCn}');
    }
  }
  
  // 添加非 ENR 项
  result.addAll(items.where((item) => !item.nameCn.startsWith('ENR')));
  
  // 打印最终结构
  for (var item in result) {
    if (item.nameCn.startsWith('ENR')) {
      print('最终结构：${item.nameCn}，子项数量：${item.children.length}');
      for (var child in item.children) {
        print('  - ${child.nameCn}');
      }
    }
  }
  
  return result;
}
}

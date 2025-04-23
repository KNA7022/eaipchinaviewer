import 'dart:convert';
import 'dart:collection';
import '../services/api_service.dart';

class AipItem {
  final String nameCn;
  final String isModified;
  List<AipItem> children;
  final String? pdfPath;

  AipItem({
    required this.nameCn,
    this.isModified = 'N',
    List<AipItem>? children,
    this.pdfPath,
  }) : children = children ?? [];


  factory AipItem.fromJson(Map<String, dynamic> json, {List<String> parentPath = const []}) {
    if (!_shouldKeepItem(json['name_cn'], parentPath)) {
      return AipItem(nameCn: '', isModified: 'N');
    }

    final nameCn = _decodeUtf8String(json['name_cn'] ?? '');
    final currentPath = [...parentPath, nameCn];

    final children = (json['children'] as List<dynamic>?)
        ?.map((e) => AipItem.fromJson(e as Map<String, dynamic>, parentPath: currentPath))
        .where((item) => item.nameCn.isNotEmpty)
        .toList() ?? [];

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
    
    final enrPattern = RegExp(r'ENR\s*6(\.\d+)*');
    final airportPattern = RegExp(r'^Z[PBGHLJSUWY][A-Z]{2}');
    
    return enrPattern.hasMatch(nameCn) ||
        parentPath.any((p) => enrPattern.hasMatch(p)) ||
        nameCn.contains("AD 2 机场清单") ||
        airportPattern.hasMatch(nameCn) ||
        (parentPath.any((p) => p.contains('机场清单')) && 
         RegExp(r'Z[PBGHLJSUWY][A-Z]{2}-\d[A-Z]?\d?\d?').hasMatch(nameCn));
  }

  static String _decodeUtf8String(String input) {
    try {
      return utf8.decode(input.runes.toList());
    } catch (e) {
      print('UTF-8解码失败: $e');
      return input;
    }
  }

  int get sectionWeight {
    if (nameCn.startsWith('GEN')) return 1;
    if (nameCn.startsWith('ENR')) return 2;
    if (nameCn.startsWith('AD')) return 3;
    return 4;
  }

  List<num> getNumbers() {
    return RegExp(r'(\d+(\.\d+)*)')
        .allMatches(nameCn)
        .map((match) => match.group(1)!.split('.').map((s) => num.tryParse(s) ?? 0))
        .expand((x) => x)
        .toList();
  }

  List<num> getEnrNumbers() {
    final match = RegExp(r'ENR\s*(\d+(?:\.\d+)*)').firstMatch(nameCn);
    return match?.group(1)?.split('.').map((s) => num.tryParse(s.trim()) ?? 0).toList() ?? [];
  }

  int compareTo(AipItem other) {
    // 机场排序 - 只比较ICAO码部分
    final thisCode = airportCode;
    final otherCode = other.airportCode;
    if (thisCode != null && otherCode != null) {
      return thisCode.compareTo(otherCode);
    }

    // ENR排序
    if (nameCn.startsWith('ENR') && other.nameCn.startsWith('ENR')) {
      final aNums = _getEnrSectionNumbers(nameCn);
      final bNums = _getEnrSectionNumbers(other.nameCn);
      
      for (int i = 0; i < aNums.length && i < bNums.length; i++) {
        final cmp = aNums[i].compareTo(bNums[i]);
        if (cmp != 0) return cmp;
      }
      return aNums.length.compareTo(bNums.length);
    }

    // 通用排序
    final weightCmp = sectionWeight.compareTo(other.sectionWeight);
    if (weightCmp != 0) return weightCmp;
    
    final nums = getNumbers();
    final otherNums = other.getNumbers();
    for (int i = 0; i < nums.length && i < otherNums.length; i++) {
      final cmp = nums[i].compareTo(otherNums[i]);
      if (cmp != 0) return cmp;
    }
    return nameCn.compareTo(other.nameCn);
  }

  static List<AipItem> buildHierarchy(List<AipItem> items) {
    final Map<String, AipItem> enrMap = {};
    final Map<String, AipItem> airportMap = {};
    final List<AipItem> result = [];
    final processedItems = HashSet<AipItem>();

    // 分离 ENR 和机场项
    final enrItems = items.where((item) => item.nameCn.startsWith('ENR')).toList();
    final airportItems = items.where((item) => 
      RegExp(r'Z[PBGHLJSUWY][A-Z]{2}').hasMatch(item.nameCn)
    ).toList();
    
    // 将所有已处理的项添加到 processedItems
    processedItems.addAll(enrItems);
    processedItems.addAll(airportItems);

    // 按章节号深度和数值排序
    enrItems.sort((a, b) {
      final aNumbers = _getEnrSectionNumbers(a.nameCn);
      final bNumbers = _getEnrSectionNumbers(b.nameCn);
      
      // 首先按层级深度排序
      if (aNumbers.length != bNumbers.length) {
        return aNumbers.length.compareTo(bNumbers.length);
      }
      
      // 同层级按数字大小排序
      for (var i = 0; i < aNumbers.length && i < bNumbers.length; i++) {
        if (aNumbers[i] != bNumbers[i]) {
          return aNumbers[i].compareTo(bNumbers[i]);
        }
      }
      return 0;
    });

    // ENR 项的处理保持不变
    print('排序后的ENR项：');
    for (var item in enrItems) {
      print('  ${item.nameCn}');
      processedItems.add(item);
    }

    // 创建所有 ENR 项的映射
    for (var item in enrItems) {
      final numbers = _getEnrSectionNumbers(item.nameCn);
      final key = 'ENR ${numbers.join('.')}';
      enrMap[key] = item.copyWith(children: []);
      print('创建ENR项: $key');
    }

    // 构建父子关系
    for (var item in enrItems) {
      final numbers = _getEnrSectionNumbers(item.nameCn);
      if (numbers.length > 1) {
        final parentNumbers = numbers.sublist(0, numbers.length - 1);
        final parentKey = 'ENR ${parentNumbers.join('.')}';
        final itemKey = 'ENR ${numbers.join('.')}';
        
        final parent = enrMap[parentKey];
        final child = enrMap[itemKey];
        
        if (parent != null && child != null) {
          parent.children.add(child);
          print('添加子项: $itemKey -> $parentKey (当前子项数: ${parent.children.length})');
        } else {
          print('无法添加子项: $itemKey, 父项${parentKey}${parent == null ? "不存在" : ""}');
        }
      }
    }

    // 仅添加顶级项到结果
    for (var item in enrItems) {
      final numbers = _getEnrSectionNumbers(item.nameCn);
      if (numbers.length == 1) {
        final key = 'ENR ${numbers.join('.')}';
        final topItem = enrMap[key];
        if (topItem != null) {
          result.add(topItem);
          print('添加顶级项: $key, 子项数: ${topItem.children.length}');
          _printHierarchy(topItem, '  ');
        }
      }
    }

    // --------------- 机场项处理逻辑 ---------------
    
    // 正则表达式匹配ICAO码
    final icaoCodeRegex = RegExp(r'^(Z[PBGHLJSUWY][A-Z]{2})\b');
    
    // 正则表达式匹配 "ICAO-机场名" 格式 (如 "ZBAA-北京/首都")
    final fullAirportNameRegex = RegExp(r'^(Z[PBGHLJSUWY][A-Z]{2})-([^-\d][^-]*?)$');
    
    // 正则表达式匹配子项格式 (如 "ZBAA-1A", "ZBAA-6", "ZBAA-7B10", "ZGOW-20B")
    final childItemRegex = RegExp(r'^(Z[PBGHLJSUWY][A-Z]{2})-(\d+[A-Z0-9]*)');
    
    // 创建一个收集机场名称的映射 (ICAO码 -> 机场名)
    final Map<String, String> airportNames = {};
    
    // 首先遍历所有项目，找出符合 "ICAO-机场名" 格式的条目，提取机场名
    for (final item in airportItems) {
      final fullNameMatch = fullAirportNameRegex.firstMatch(item.nameCn);
      if (fullNameMatch != null) {
        final icaoCode = fullNameMatch.group(1)!;
        final airportName = fullNameMatch.group(2)!;
        airportNames[icaoCode] = airportName;
      }
    }
    
    // 创建临时结构以区分父项和子项
    final Map<String, List<AipItem>> airportChildren = {};
    final Map<String, AipItem> airportParents = {};
    
    // 分类处理所有机场相关项
    for (final item in airportItems) {
      // 提取ICAO码
      final icaoMatch = icaoCodeRegex.firstMatch(item.nameCn);
      if (icaoMatch == null) continue;
      
      final icaoCode = icaoMatch.group(1)!;
      
      // 初始化子项列表（如果不存在）
      airportChildren.putIfAbsent(icaoCode, () => []);
      
      // 检查是否是符合 "ICAO-机场名" 格式的父项
      final fullNameMatch = fullAirportNameRegex.firstMatch(item.nameCn);
      if (fullNameMatch != null) {
        // 这是父项，记录其 PDF 路径
        airportParents[icaoCode] = item;
        continue;
      }
      
      // 检查是否是符合 "ICAO-子项编号" 格式的子项
      final childMatch = childItemRegex.firstMatch(item.nameCn);
      if (childMatch != null) {
        // 这是子项，添加到对应的子项列表
        airportChildren[icaoCode]!.add(item);
      }
    }
    
    // 构建最终的机场层次结构
    for (final icaoCode in {...airportParents.keys, ...airportChildren.keys}) {
      // 首先获取机场名（如果已知）
      final airportName = airportNames[icaoCode] ?? '';
      
      // 构建父项名称格式为 "ICAO-机场名"
      final parentName = airportName.isEmpty ? icaoCode : '$icaoCode-$airportName';
      
      // 获取现有的父项（如果存在）或创建新的父项
      AipItem parentItem;
      if (airportParents.containsKey(icaoCode)) {
        // 使用现有父项并更新其名称
        parentItem = airportParents[icaoCode]!.copyWith(
          nameCn: parentName,
          children: [],
        );
      } else {
        // 创建新的父项（没有PDF路径）
        parentItem = AipItem(
          nameCn: parentName,
          isModified: 'N',
          pdfPath: null,
          children: [],
        );
      }
      
      // 添加子项（如果有）
      if (airportChildren.containsKey(icaoCode)) {
        parentItem = parentItem.copyWith(
          children: airportChildren[icaoCode]!,
        );
      }
      
      // 将构建的父项添加到结果中
      airportMap[icaoCode] = parentItem;
    }
    
    // 添加机场父项到结果
    result.addAll(airportMap.values);
    
    // 添加剩余项并排序
    result
      ..addAll(items.where((item) => !processedItems.contains(item)))
      ..sort((a, b) => a.compareTo(b));

    // 排序子项
    for (final parent in result) {
      parent.children.sort((a, b) => a.compareTo(b));
    }

    return result;
  }

  // 添加用于打印层级结构的辅助方法
  static void _printHierarchy(AipItem item, String indent) {
    for (var child in item.children) {
      print('$indent- ${child.nameCn} (子项数: ${child.children.length})');
      _printHierarchy(child, '$indent  ');
    }
  }

  String? get airportCode {
    final match = RegExp(r'^(Z[PBGHLJSUWY][A-Z]{2})\b').firstMatch(nameCn);
    return match?.group(1);
  }

// 构建ENR名称
String _buildEnrName(List<int> numbers) {
  return 'ENR ${numbers.join('.')}';
}

// 增强版章节号提取方法
static List<int> _getEnrSectionNumbers(String nameCn) {
    final match = RegExp(r'ENR[^\d]*((\d+\.)*\d+)').firstMatch(nameCn);
    return match?.group(1)?.split('.')?.map(int.parse)?.toList() ?? [];
  }

  // 添加静态的copyWith方法
  AipItem copyWith({
    String? nameCn,
    String? isModified,
    List<AipItem>? children,
    String? pdfPath,
  }) {
    return AipItem(
      nameCn: nameCn ?? this.nameCn,
      isModified: isModified ?? this.isModified,
      children: children ?? List.from(this.children),
      pdfPath: pdfPath ?? this.pdfPath,
    );
  }

  // 添加计算修改状态的 getter
  bool get hasModifiedChildren {
    return isModified == 'Y' || children.any((child) => child.hasModifiedChildren);
  }
}

extension _ListEquals on List<int> {
  bool equals(List<int> other) {
    if (length != other.length) return false;
    for (int i = 0; i < length; i++) {
      if (this[i] != other[i]) return false;
    }
    return true;
  }
}
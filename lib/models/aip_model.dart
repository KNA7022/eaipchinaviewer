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
    final airportPattern = RegExp(r'^Z[PBGHLSUWY][A-Z]{2}');
    
    return enrPattern.hasMatch(nameCn) ||
        parentPath.any((p) => enrPattern.hasMatch(p)) ||
        nameCn.contains("AD 2 机场清单") ||
        airportPattern.hasMatch(nameCn) ||
        (parentPath.any((p) => p.contains('机场清单')) && 
         RegExp(r'Z[PBGHLSUWY][A-Z]{2}-\d[A-Z]?\d?\d?').hasMatch(nameCn));
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
    // 机场排序
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
      RegExp(r'Z[PBGHLSUWY][A-Z]{2}').hasMatch(item.nameCn)
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

    // 处理机场项
    final airportCodeRegex = RegExp(r'^(Z[PBGHLSUWY][A-Z]{2})\b');
    
    // 第一阶段：收集所有父项信息
    final airportParentItems = airportItems.where(
      (item) => airportCodeRegex.matchAsPrefix(item.nameCn)?.end == item.nameCn.length
    ).toList();

    // 创建机场父项
    for (final parentItem in airportParentItems) {
      final code = parentItem.airportCode!;
      airportMap[code] = parentItem.copyWith(
        children: [],
        pdfPath: parentItem.pdfPath,
        // 父项的修改状态设为 'N'，后续通过子项状态动态判断
        isModified: 'N',
      );
    }

    // 第二阶段：处理子项
    for (final item in airportItems) {
      final code = item.airportCode;
      if (code == null) continue;

      if (!airportMap.containsKey(code)) {
        airportMap[code] = AipItem(
          nameCn: code,
          isModified: 'N',
          pdfPath: null,
          children: [],
        );
      }

      if (item.nameCn != code) {
        airportMap[code] = airportMap[code]!.copyWith(
          children: [...airportMap[code]!.children, item],
        );
      }
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
    final match = RegExp(r'^(Z[PBGHLSUWY][A-Z]{2})\b').firstMatch(nameCn);
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
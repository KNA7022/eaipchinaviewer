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
    final enrMap = <String, AipItem>{};
    final airportMap = <String, AipItem>{};
    final result = <AipItem>[];
    final processedItems = HashSet<AipItem>();

    // 分离ENR和机场项
    final enrItems = items.where((item) {
      if (item.nameCn.startsWith('ENR')) {
        processedItems.add(item);
        return true;
      }
      return false;
    }).toList();

    final airportItems = items.where((item) {
      if (item.airportCode != null) {
        processedItems.add(item);
        return true;
      }
      return false;
    }).toList();

    // 处理ENR层级
    enrItems.sort((a, b) {
      final aNums = _getEnrSectionNumbers(a.nameCn);
      final bNums = _getEnrSectionNumbers(b.nameCn);
      for (int i = 0; i < aNums.length && i < bNums.length; i++) {
        final cmp = aNums[i].compareTo(bNums[i]);
        if (cmp != 0) return cmp;
      }
      return aNums.length.compareTo(bNums.length);
    });

    // 创建ENR映射
    for (final item in enrItems) {
      enrMap[item.nameCn] = item.copyWith(children: []);
    }

    // 建立ENR父子关系
    for (final item in enrItems) {
      final numbers = _getEnrSectionNumbers(item.nameCn);
      if (numbers.length > 1) {
        final parentNumbers = numbers.sublist(0, numbers.length - 1);
        final parent = enrItems.firstWhere(
          (e) => _getEnrSectionNumbers(e.nameCn).equals(parentNumbers),
          orElse: () => AipItem(nameCn: ''),
        );
        parent.children.add(enrMap[item.nameCn]!);
      }
    }

    // 添加ENR顶级项
    result.addAll(enrItems.where((item) => 
      _getEnrSectionNumbers(item.nameCn).length == 1));

    final airportCodeRegex = RegExp(r'^(Z[PBGHLSUWY][A-Z]{2})\b');
    
    // 第一阶段：收集所有父项信息
    final airportParentItems = airportItems.where(
      (item) => airportCodeRegex.matchAsPrefix(item.nameCn)?.end == item.nameCn.length
    ).toList();

    // 创建机场父项（使用实际存在的父项信息）
    for (final parentItem in airportParentItems) {
      final code = parentItem.airportCode!;
      airportMap[code] = parentItem.copyWith(
        children: [],
        pdfPath: parentItem.pdfPath,
        isModified: parentItem.isModified
      );
    }

    // 第二阶段：处理子项
    for (final item in airportItems) {
      final code = item.airportCode;
      if (code == null) continue;

      // 自动创建缺失的父项（使用代码作为名称）
      if (!airportMap.containsKey(code)) {
        airportMap[code] = AipItem(
          nameCn: code,
          isModified: 'N',
          pdfPath: null,
          children: [],
        );
      }

      // 添加子项（排除父项自身）
      if (item.nameCn != code) {
        airportMap[code] = airportMap[code]!.copyWith(
          children: [...airportMap[code]!.children, item]
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

  String? get airportCode {
    final match = RegExp(r'^(Z[PBGHLSUWY][A-Z]{2})\b').firstMatch(nameCn);
    return match?.group(1);
  }

  static List<int> _getEnrSectionNumbers(String nameCn) {
    final match = RegExp(r'ENR\s*(\d+(?:\.\d+)*)').firstMatch(nameCn);
    return match?.group(1)?.split('.')?.map(int.parse)?.toList() ?? [];
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
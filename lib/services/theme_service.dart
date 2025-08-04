import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static const String _themeKey = 'theme_mode';
  
  // 添加 ValueNotifier 来监听主题变化
  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
  // 自动收起侧边栏设置通知器
  final ValueNotifier<bool> autoCollapseNotifier = ValueNotifier(true);

  // 单例模式
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    int themeIndex;
    final dynamic storedValue = prefs.get(_themeKey);
    if (storedValue is int) {
      themeIndex = storedValue;
    } else if (storedValue is String) {
      themeIndex = int.tryParse(storedValue) ?? 0;
    } else {
      themeIndex = 0;
    }
    themeNotifier.value = ThemeMode.values[themeIndex];
    
    // 初始化自动收起侧边栏设置，默认为true
    final autoCollapse = prefs.getBool('auto_collapse_sidebar') ?? true;
    autoCollapseNotifier.value = autoCollapse;
  }

  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.get(_themeKey);
    int themeIndex;
    if (storedValue is int) {
      themeIndex = storedValue;
    } else if (storedValue is String) {
      themeIndex = int.tryParse(storedValue) ?? 0;
    } else {
      themeIndex = 0;
    }
    return ThemeMode.values[themeIndex];
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    themeNotifier.value = mode;
  }
  
  // 获取自动收起侧边栏设置
  Future<bool> getAutoCollapseSidebar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_collapse_sidebar') ?? true;
  }
  
  // 设置自动收起侧边栏
  Future<void> setAutoCollapseSidebar(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_collapse_sidebar', value);
    autoCollapseNotifier.value = value;
  }
}

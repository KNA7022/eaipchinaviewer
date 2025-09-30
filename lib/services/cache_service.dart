import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class CacheService {
  static Future<void> clearCache() async {
    try {
      // 清理SharedPreferences中的所有应用相关缓存数据
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // 清理天气缓存
      final weatherKeys = keys.where((key) => key.startsWith('weather_')).toList();
      for (final key in weatherKeys) {
        await prefs.remove(key);
      }
      
      // 清理机场信息缓存
      final airportKeys = keys.where((key) => key.startsWith('airport_')).toList();
      for (final key in airportKeys) {
        await prefs.remove(key);
      }
      
      // 清理其他可能的应用缓存（如主题设置、用户偏好等，但保留重要设置）
      final otherKeys = keys.where((key) => 
        !key.startsWith('weather_') && 
        !key.startsWith('airport_') &&
        !key.startsWith('theme_') &&  // 保留主题设置
        !key.startsWith('auth_') &&   // 保留认证信息
        !key.startsWith('user_')      // 保留用户设置
      ).toList();
      for (final key in otherKeys) {
        await prefs.remove(key);
      }
      
      print('已清理 ${weatherKeys.length} 个天气缓存、${airportKeys.length} 个机场缓存和 ${otherKeys.length} 个其他缓存');
      
      // 清理文件缓存
      await _clearTempFiles();
      await _clearPdfCache();
      await _clearAppCache();
      
    } catch (e) {
      print('清理缓存失败: $e');
    }
  }
  
  static Future<void> _clearTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        final appTempDir = Directory('${tempDir.path}/eaipchinaviewer');
        if (appTempDir.existsSync()) {
          await appTempDir.delete(recursive: true);
          print('已清理应用临时文件');
        }
      }
    } catch (e) {
      print('清理临时文件失败: $e');
    }
  }
  
  /// 清理PDF缓存文件（包括版本文件夹中的文件）
  static Future<void> _clearPdfCache() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final pdfDir = Directory('${documentsDir.path}/pdfs');
      
      if (pdfDir.existsSync()) {
        int deletedCount = 0;
        int deletedFolders = 0;
        
        // 递归遍历所有文件和文件夹
        await for (final entity in pdfDir.list(recursive: true)) {
          try {
            if (entity is File && entity.path.endsWith('.pdf')) {
              await entity.delete();
              deletedCount++;
            } else if (entity is Directory) {
              // 检查文件夹是否为空，如果为空则删除
              final isEmpty = await _isDirectoryEmpty(entity);
              if (isEmpty) {
                await entity.delete();
                deletedFolders++;
              }
            }
          } catch (e) {
            print('删除缓存项失败: ${entity.path}, 错误: $e');
          }
        }
        
        // 清理根目录下的直接PDF文件（兼容旧版本）
        final rootFiles = pdfDir.listSync(recursive: false);
        for (final file in rootFiles) {
          if (file is File && file.path.endsWith('.pdf')) {
            try {
              await file.delete();
              deletedCount++;
            } catch (e) {
              print('删除根目录PDF文件失败: ${file.path}, 错误: $e');
            }
          }
        }
        
        print('已清理 $deletedCount 个PDF缓存文件和 $deletedFolders 个空文件夹');
      }
    } catch (e) {
      print('清理PDF缓存失败: $e');
    }
  }
  
  /// 检查目录是否为空
  static Future<bool> _isDirectoryEmpty(Directory dir) async {
    try {
      final contents = await dir.list().toList();
      return contents.isEmpty;
    } catch (e) {
      return false;
    }
  }
  
  static Future<void> _clearAppCache() async {
    try {
      // 清理应用缓存目录（可能包含旧版本应用的缓存）
      final cacheDir = await getApplicationCacheDirectory();
      if (cacheDir.existsSync()) {
        final files = cacheDir.listSync();
        int deletedCount = 0;
        
        for (final item in files) {
          try {
            if (item is File) {
              await item.delete();
              deletedCount++;
            } else if (item is Directory) {
              await item.delete(recursive: true);
              deletedCount++;
            }
          } catch (e) {
            print('删除缓存项失败: ${item.path}, 错误: $e');
          }
        }
        
        print('已清理应用缓存目录中的 $deletedCount 个项目');
      }
      
      // 清理支持目录中可能的缓存文件
      try {
        final supportDir = await getApplicationSupportDirectory();
        final appSupportDir = Directory('${supportDir.path}/eaipchinaviewer');
        if (appSupportDir.existsSync()) {
          await appSupportDir.delete(recursive: true);
          print('已清理应用支持目录缓存');
        }
      } catch (e) {
        // 支持目录可能不存在或无权限访问，忽略错误
        print('清理支持目录时出现错误（可忽略）: $e');
      }
      
    } catch (e) {
      print('清理应用缓存失败: $e');
    }
  }
  
  /// 获取缓存统计信息
  static Future<Map<String, int>> getCacheStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      final weatherCount = keys.where((key) => key.startsWith('weather_')).length;
      final airportCount = keys.where((key) => key.startsWith('airport_')).length;
      
      // 统计其他SharedPreferences缓存
      final otherPrefsCount = keys.where((key) => 
        !key.startsWith('weather_') && 
        !key.startsWith('airport_') &&
        !key.startsWith('theme_') &&
        !key.startsWith('auth_') &&
        !key.startsWith('user_')
      ).length;
      
      // 统计PDF缓存文件数量
      int pdfCount = 0;
      try {
        final documentsDir = await getApplicationDocumentsDirectory();
        final pdfDir = Directory('${documentsDir.path}/pdfs');
        if (pdfDir.existsSync()) {
          // 递归遍历所有子文件夹（包括版本文件夹）
          await for (final entity in pdfDir.list(recursive: true)) {
            if (entity is File && entity.path.endsWith('.pdf')) {
              pdfCount++;
            }
          }
        }
      } catch (e) {
        print('统计PDF缓存失败: $e');
      }
      
      // 统计应用缓存目录文件数量
      int appCacheCount = 0;
      try {
        final cacheDir = await getApplicationCacheDirectory();
        if (cacheDir.existsSync()) {
          final items = cacheDir.listSync();
          appCacheCount = items.length;
        }
      } catch (e) {
        print('统计应用缓存失败: $e');
      }
      
      return {
        'weather': weatherCount,
        'airport': airportCount,
        'other_prefs': otherPrefsCount,
        'pdf': pdfCount,
        'app_cache': appCacheCount,
        'total': weatherCount + airportCount + otherPrefsCount + pdfCount + appCacheCount,
      };
    } catch (e) {
      print('获取缓存统计失败: $e');
      return {'weather': 0, 'airport': 0, 'other_prefs': 0, 'pdf': 0, 'app_cache': 0, 'total': 0};
    }
  }
}

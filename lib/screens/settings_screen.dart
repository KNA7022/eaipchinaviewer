import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';  // 添加这一行
import 'package:flutter/services.dart';  // 添加这个导入

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _cacheSize = '计算中...';

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    try {
      int totalSize = 0;
      
      // 计算临时目录大小
      final tempDir = await getTemporaryDirectory();
      totalSize += await _getTotalDirectorySize(tempDir);
      
      // 计算应用文档目录大小（PDF缓存可能存储在这里）
      final appDocDir = await getApplicationDocumentsDirectory();
      totalSize += await _getTotalDirectorySize(appDocDir);
      
      // 计算应用缓存目录大小
      final appCacheDir = await getApplicationCacheDirectory();
      totalSize += await _getTotalDirectorySize(appCacheDir);

      setState(() {
        _cacheSize = _formatBytes(totalSize);
      });
    } catch (e) {
      setState(() {
        _cacheSize = '计算失败';
      });
      print('计算缓存大小出错: $e');
    }
  }

  Future<int> _getTotalDirectorySize(Directory dir) async {
    int totalSize = 0;
    try {
      if (dir.existsSync()) {
        dir.listSync(recursive: true, followLinks: false)
            .forEach((FileSystemEntity entity) {
          if (entity is File) {
            totalSize += entity.lengthSync();
          }
        });
      }
    } catch (e) {
      print('计算缓存大小出错: $e');
    }
    return totalSize;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<void> _clearCache() async {
    try {
      // 清理临时目录
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
        await tempDir.create();
      }
      
      // 清理应用文档目录
      final appDocDir = await getApplicationDocumentsDirectory();
      if (appDocDir.existsSync()) {
        for (var entity in appDocDir.listSync()) {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        }
      }
      
      // 清理应用缓存目录
      final appCacheDir = await getApplicationCacheDirectory();
      if (appCacheDir.existsSync()) {
        await appCacheDir.delete(recursive: true);
        await appCacheDir.create();
      }

      await _calculateCacheSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缓存已清除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除缓存失败: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    try {
      final authService = AuthService();
      await authService.clearAuthData();
      await _clearCache();
      
      if (mounted) {
        // 清除导航堆栈并跳转到登录页
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login',
          (Route<dynamic> route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('退出登录失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('清除缓存'),
            subtitle: Text('当前缓存: $_cacheSize'),
            onTap: _clearCache,
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            subtitle: const Text('清除所有数据并返回登录界面'),
            onTap: () => showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('确认退出'),
                content: const Text('退出将清除所有本地数据，确定继续吗？'),
                actions: [
                  TextButton(
                    child: const Text('取消'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TextButton(
                    child: const Text('确定'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _logout();
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('版本 1.0.0'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'AIP中国航图查看器',
              applicationVersion: '1.0.0',
              applicationIcon: const Icon(Icons.flight),
              children: [
                const Text('这是一个非官方的第三方应用程序，用于查看中国民航航图。'),
                const SizedBox(height: 8),
                const Text('数据来源: https://www.eaipchina.cn/'),
                const SizedBox(height: 8),
                const Text('声明：本应用仅供参考，不作为航行依据。航图数据的最终解释权归中国民航局所有。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

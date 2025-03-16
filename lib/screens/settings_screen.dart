import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';  // 添加这个导入

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
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        elevation: 0,
      ),
      body: ListView(
        children: [
          // 缓存管理部分
          _buildSection(
            icon: Icons.storage,
            title: '存储',
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('清除缓存'),
                subtitle: Text('当前缓存: $_cacheSize'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showClearCacheDialog(context),
              ),
            ],
          ),
          
          const Divider(height: 1),
          
          // 账号管理部分
          _buildSection(
            icon: Icons.account_circle,
            title: '账号',
            children: [
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('退出登录', style: TextStyle(color: Colors.red)),
                subtitle: const Text('清除所有数据并返回登录界面'),
                trailing: const Icon(Icons.chevron_right, color: Colors.red),
                onTap: () => _showLogoutDialog(context),
              ),
            ],
          ),
          
          const Divider(height: 1),
          
          // 关于部分
          _buildSection(
            icon: Icons.info,
            title: '关于',
            children: [
              ListTile(
                leading: const Icon(Icons.code),
                title: const Text('开源代码'),
                subtitle: const Text('GitHub 仓库'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _launchUrl('https://github.com/KNA7022/eaipchinaviewer'),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本信息'),
                subtitle: const Text('1.0.0'),
                onTap: () => _showAboutDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }

  Future<void> _showClearCacheDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('确定要清除所有缓存数据吗？'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text('确定'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearCache();
    }
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出将清除所有本地数据，确定继续吗？'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('退出'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'AIP中国航图查看器',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.flight),
      children: [
        const Text('这是一个非官方的第三方应用程序，用于查看中国民航航图。'),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _launchUrl('https://github.com/KNA7022/eaipchinaviewer'),
          child: const Text(
            'GitHub: https://github.com/KNA7022/eaipchinaviewer',
            style: TextStyle(
              color: Colors.blue,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text('数据来源: https://www.eaipchina.cn/'),
        const SizedBox(height: 8),
        const Text('声明：本应用仅供参考，不作为航行依据。航图数据的最终解释权归中国民航局所有。'),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url')),
        );
      }
    }
  }
}

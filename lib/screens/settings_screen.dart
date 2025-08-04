import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';  
import 'package:shared_preferences/shared_preferences.dart';
import 'policy_screen.dart';
import '../main.dart';  // 添加这一行
import 'package:package_info_plus/package_info_plus.dart';  // 添加这一行

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _cacheSize = '计算中...';
  Map<String, int> _cacheStats = {'weather': 0, 'airport': 0, 'total': 0};
  ThemeMode _currentThemeMode = ThemeMode.system;
  final _themeService = ThemeService();
  final _updateService = UpdateService();
  bool _autoCollapseSidebar = true;
  bool _isCheckingForUpdates = false;
  String _sponsors = '加载中...';  // 添加捐助者信息变量

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
    _loadCacheStats();
    _loadThemeMode();
    _loadSponsors();  // 加载捐助者信息
  }

  Future<void> _loadThemeMode() async {
    final mode = await _themeService.getThemeMode();
    setState(() => _currentThemeMode = mode);
  }

  Future<void> _updateThemeMode(ThemeMode mode) async {
    await _themeService.setThemeMode(mode);
    setState(() => _currentThemeMode = mode);
    if (!mounted) return;
    
    // 使用 MainApp.of 方法更新主题
    final mainApp = MainApp.of(context);
    if (mainApp != null) {
      mainApp.setState(() {});
    }
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

  Future<void> _loadCacheStats() async {
    try {
      final stats = await CacheService.getCacheStats();
      setState(() {
        _cacheStats = stats;
      });
    } catch (e) {
      print('加载缓存统计失败: $e');
    }
  }

  Future<void> _clearCache() async {
    try {
      await CacheService.clearCache();
      await _calculateCacheSize();
      await _loadCacheStats();
      
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

  // 添加获取版本信息的方法
  Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return '${packageInfo.version} (${packageInfo.buildNumber})';
    } catch (e) {
      print('获取版本信息失败: $e');
      return '1.3.5';  // fallback version
    }
  }

  // 修改版本信息的显示方式
  Widget _buildVersionTile() {
    return FutureBuilder<String>(
      future: _getAppVersion(),
      builder: (context, snapshot) {
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('版本信息'),
          subtitle: Text(snapshot.data ?? '加载中...'),
          onTap: () => _showAboutDialog(context),
        );
      },
    );
  }

  // 添加加载捐助者信息的方法
  Future<void> _loadSponsors() async {
    try {
      final sponsors = await _updateService.getSponsors();
      if (mounted) {
        setState(() {
          _sponsors = sponsors.isEmpty ? '暂无捐助者' : sponsors;
        });
      }
    } catch (e) {
      print('加载捐助者信息失败: $e');
      if (mounted) {
        setState(() {
          _sponsors = '加载失败';
        });
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
          // 主题设置部分
          _buildSection(
            icon: Icons.palette,
            title: '显示',
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_auto),
                title: const Text('主题模式'),
                subtitle: Text(_getThemeModeText()),
                onTap: _showThemeModeDialog,
              ),
              // 使用 ValueListenableBuilder 来实时响应自动收起侧边栏设置的变化
              ValueListenableBuilder<bool>(
                valueListenable: _themeService.autoCollapseNotifier,
                builder: (context, autoCollapse, child) {
                  return SwitchListTile(
                    secondary: const Icon(Icons.view_sidebar),
                    title: const Text('打开PDF时自动收起侧边栏'),
                    subtitle: const Text('查看航图时自动隐藏左侧导航栏'),
                    value: autoCollapse,
                    onChanged: (value) {
                      // 直接设置值，不需要等待setState
                      _themeService.setAutoCollapseSidebar(value);
                    },
                  );
                },
              ),
            ],
          ),

          const Divider(height: 1),

          // 缓存管理部分
          _buildSection(
            icon: Icons.storage,
            title: '存储',
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('缓存统计'),
                subtitle: Text(
                  '天气缓存: ${_cacheStats['weather']} 条\n'
                  '机场缓存: ${_cacheStats['airport']} 条\n'
                  'PDF缓存: ${_cacheStats['pdf']} 个\n'
                  '其他缓存: ${_cacheStats['other_prefs'] ?? 0} 条\n'
                  '应用缓存: ${_cacheStats['app_cache'] ?? 0} 项\n'
                  '总计: ${_cacheStats['total']} 项'
                ),
                isThreeLine: true,
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('清除缓存'),
                subtitle: Text('文件缓存: $_cacheSize'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showClearCacheDialog(context),
              ),
            ],
          ),
          
          const Divider(height: 1),
          
          // 应用部分
          _buildSection(
            icon: Icons.apps,
            title: '应用',
            children: [
              _buildVersionTile(),
              ListTile(
                leading: const Icon(Icons.system_update),
                title: const Text('检查更新'),
                subtitle: const Text('检查是否有新版本可用'),
                trailing: _isCheckingForUpdates 
                  ? const SizedBox(
                      width: 20, 
                      height: 20, 
                      child: CircularProgressIndicator(strokeWidth: 2.0)
                    )
                  : const Icon(Icons.chevron_right),
                onTap: _isCheckingForUpdates ? null : _checkForUpdates,
              ),
              // 添加捐助者信息部分
              ListTile(
                leading: const Icon(Icons.favorite, color: Colors.red),
                title: const Text('捐助者名单'),
                subtitle: Text('点击查看详细名单'),
                onTap: () => _showSponsorsDialog(context),
              ),
              // 新增捐助作者入口
              ListTile(
                leading: const Icon(Icons.volunteer_activism, color: Colors.orange),
                title: const Text('捐助作者'),
                subtitle: const Text('支持作者，点此跳转'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _launchUrl('http://afdian.tv/a/kna7022'),
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
          
          // 添加保密提示部分
          _buildSection(
            icon: Icons.security,
            title: '保密提示',
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  color: theme.colorScheme.errorContainer.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '保密提示',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '保守国家秘密是我国公民的基本义务，根据《中华人民共和国保守国家秘密法》，所有国家机关、组织及公民都有此责任。',
                          style: TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '国家秘密关乎国家安全和利益，泄露将造成重大损害。',
                          style: TextStyle(height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '因此，保守国家秘密不仅是法律要求，也是公民应尽的责任，任何危害行为都将受到法律追究。',
                          style: TextStyle(height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
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
            ],
          ),

          const Divider(height: 1),
          
          // 将隐私政策和用户协议合并为一个选项
          _buildSection(
            icon: Icons.gavel,
            title: '法律条款',
            children: [
              ListTile(
                leading: const Icon(Icons.policy),
                title: const Text('用户协议与隐私政策'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PolicyScreen(
                      type: 'privacy',
                      showBothPolicies: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getThemeModeText() {
    switch (_currentThemeMode) {
      case ThemeMode.light:
        return '浅色模式';
      case ThemeMode.dark:
        return '深色模式';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  void _showThemeModeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              value: ThemeMode.system,
              groupValue: _currentThemeMode,
              onChanged: (value) {
                Navigator.pop(context);
                _updateThemeMode(value!);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('浅色模式'),
              value: ThemeMode.light,
              groupValue: _currentThemeMode,
              onChanged: (value) {
                Navigator.pop(context);
                _updateThemeMode(value!);
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色模式'),
              value: ThemeMode.dark,
              groupValue: _currentThemeMode,
              onChanged: (value) {
                Navigator.pop(context);
                _updateThemeMode(value!);
              },
            ),
          ],
        ),
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
    final confirmed = await showDialog<bool>(      context: context,
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

  void _showAboutDialog(BuildContext context) async {
    final version = await _getAppVersion();
    if (!mounted) return;
    
    showAboutDialog(
      context: context,
      applicationName: 'EAIP中国航图查看器',
      applicationVersion: version,
      applicationIcon: const Icon(Icons.flight),
      children: [
        const Text('这是一个非官方的第三方应用程序，用于查看中国民航英文航图，此版本航图不涉及国家机密，请注意甄别'),
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

  Future<void> _checkForUpdates() async {
    if (_isCheckingForUpdates) return;
    
    setState(() {
      _isCheckingForUpdates = true;
    });
    
    try {
      // 使用MainApp中的方法检查更新
      final mainApp = MainApp.of(context);
      
      if (mainApp != null) {
        // 获取主应用状态
        final mainAppState = mainApp as MainAppState;
        
        // 设置检查标识为false，以便进行新的检查
        mainAppState.hasCheckedForUpdates = false;
        
        // 等待检查更新，并获取结果
        final updateResult = await mainAppState.updateService.checkForUpdates();
        
        // 标记为已检查
        mainAppState.hasCheckedForUpdates = true;
        
        // 更新捐助者信息
        if (updateResult != null && updateResult.containsKey('sponsors')) {
          setState(() {
            _sponsors = updateResult['sponsors'] ?? '暂无捐助者';
          });
        }
        
        // 根据结果显示相应提示
        if (mounted) {
          if (updateResult == null) {
            // 检查失败
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('检查更新失败，请稍后再试')),
            );
          } else if (updateResult['hasUpdate'] == true) {
            // 有更新，显示更新对话框
            mainAppState.showUpdateDialog(context, updateResult);
          } else {
            // 没有更新
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已是最新版本')),
            );
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('检查更新时出错: $e')),
        );
      }
    }
  }

  // 添加显示捐助者对话框的方法
  void _showSponsorsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.favorite, color: Colors.red),
              const SizedBox(width: 10),
              const Text('捐助者名单'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '感谢以下捐助者对本项目的支持:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              _sponsors.isEmpty
                ? const Text('暂无捐助者')
                : Text(_sponsors),
              const SizedBox(height: 16),
              const Text(
                '如果您喜欢这个应用，可以通过以下方式支持:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _launchUrl('https://github.com/KNA7022/eaipchinaviewer'),
                child: const Text(
                  '1. 在GitHub上给项目点Star',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '2. 分享给更多的人使用',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('关闭'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('刷新'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _loadSponsors();
                _showSponsorsDialog(context);
              },
            ),
          ],
        );
      },
    );
  }
}

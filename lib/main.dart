import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/weather_service.dart';
import 'services/theme_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/weather_screen.dart';
import 'services/auth_service.dart';
import 'screens/policy_screen.dart';
import 'services/update_service.dart';

// 全局导航键，用于在任何地方获取有效的context
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await _loadFonts();
  
  final weatherService = WeatherService();
  await weatherService.clearExpiredCache();
  
  final themeService = ThemeService();
  await themeService.init();  // 初始化主题服务
  
  final prefs = await SharedPreferences.getInstance();
  final isFirstRun = prefs.getBool('first_run') ?? true;
  final isLoggedIn = await AuthService().isLoggedIn();
  
  runApp(MainApp(
    isFirstRun: isFirstRun,
    isLoggedIn: isLoggedIn,
  ));
}

Future<void> _loadFonts() async {
  try {
    await rootBundle.load('assets/fonts/NotoSansSC-Regular.otf');
    await rootBundle.load('assets/fonts/NotoSansSC-Medium.otf');
    await rootBundle.load('assets/fonts/NotoSansSC-Bold.otf');
  } catch (e) {
    print('字体加载失败: $e');
  }
}

class MainApp extends StatefulWidget {
  final bool isFirstRun;
  final bool isLoggedIn;
  
  const MainApp({
    super.key,
    required this.isFirstRun,
    required this.isLoggedIn,
  });

  // 添加静态方法来访问主题状态
  static MainAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<MainAppState>();
  }

  @override
  State<MainApp> createState() => MainAppState();
}

// 公开的 MainAppState
class MainAppState extends State<MainApp> {
  final _themeService = ThemeService();
  final UpdateService updateService = UpdateService(); // 改为公开
  ThemeMode _themeMode = ThemeMode.system;
  bool _autoCollapseSidebar = true;
  bool hasCheckedForUpdates = false; // 修改为公共变量，供其他组件访问
  
  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _loadAutoCollapseSidebar();
  }

  Future<void> _loadThemeMode() async {
    final mode = await _themeService.getThemeMode();
    setState(() => _themeMode = mode);
  }
  
  Future<void> _loadAutoCollapseSidebar() async {
    final autoCollapse = await _themeService.getAutoCollapseSidebar();
    setState(() => _autoCollapseSidebar = autoCollapse);
  }
  
  Future<bool> checkForUpdates() async {
    // 如果已经检查过更新，则不再重复检查
    if (hasCheckedForUpdates) {
      print('已经检查过更新，跳过本次检查');
      return false;
    }
    
    try {
      final updateInfo = await updateService.checkForUpdates();
      
      if (updateInfo != null && updateInfo['hasUpdate'] == true) {
        hasCheckedForUpdates = true; // 设置标志，表示已检查过更新
        
        // 使用全局导航键获取有效的context
        final context = navigatorKey.currentContext;
        if (context != null) {
          // 延迟显示更新对话框，确保MaterialApp完全初始化
          Future.delayed(const Duration(seconds: 1), () {
            showUpdateDialog(context, updateInfo);
          });
        }
        return true; // 返回找到更新
      } else {
        hasCheckedForUpdates = true; // 标记已检查，但没有更新
        return false; // 返回没有找到更新
      }
    } catch (e) {
      print('检查更新时出错: $e');
      return false; // 出错也返回 false
    }
  }
  
  void showUpdateDialog(BuildContext context, Map<String, dynamic> updateInfo) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('发现新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本: ${updateInfo['currentVersion']}'),
              Text('最新版本: ${updateInfo['newVersion']}'),
              const SizedBox(height: 8),
              const Text('更新内容:'),
              Text(updateInfo['updateNotes']),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('立即更新'),
              onPressed: () {
                Navigator.of(context).pop();
                updateService.downloadAndInstallUpdate(context, updateInfo['updateUrl'] ?? '');
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeService.themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          navigatorKey: navigatorKey, // 使用全局导航键
          title: '航图查看器',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.light,
            ),
            fontFamily: 'NotoSansSC',
            textTheme: TextTheme(
              displayLarge: const TextStyle(fontFamily: 'NotoSansSC'),
              displayMedium: const TextStyle(fontFamily: 'NotoSansSC'),
              displaySmall: const TextStyle(fontFamily: 'NotoSansSC'),
              headlineLarge: const TextStyle(fontFamily: 'NotoSansSC'),
              headlineMedium: const TextStyle(fontFamily: 'NotoSansSC'),
              headlineSmall: const TextStyle(fontFamily: 'NotoSansSC'),
              titleLarge: const TextStyle(fontFamily: 'NotoSansSC'),
              titleMedium: const TextStyle(fontFamily: 'NotoSansSC'),
              titleSmall: const TextStyle(fontFamily: 'NotoSansSC'),
              bodyLarge: const TextStyle(fontFamily: 'NotoSansSC'),
              bodyMedium: const TextStyle(fontFamily: 'NotoSansSC'),
              bodySmall: const TextStyle(fontFamily: 'NotoSansSC'),
            ).apply(
              bodyColor: Colors.black87,
              displayColor: Colors.black87,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: themeMode,  // 使用 themeMode 而不是 _themeMode
          home: _buildHome(),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/home': (context) => const HomeScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/weather': (context) => const WeatherScreen(),
          },
          onUnknownRoute: (settings) {
            return MaterialPageRoute(
              builder: (context) => const LoginScreen(),
            );
          },
        );
      },
    );
  }
  
  Widget _buildHome() {
    Widget homeWidget = widget.isFirstRun 
        ? const PolicyScreen(type: 'privacy', isFirstRun: true)
        : widget.isLoggedIn 
            ? const HomeScreen() 
            : const LoginScreen();
            
    // 使用Builder来确保有一个有效的context，并在构建后检查更新
    return Builder(
      builder: (context) {
        // 在下一帧检查更新，确保MaterialApp完全初始化
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // 添加延迟，确保应用完全初始化
          Future.delayed(const Duration(milliseconds: 1500), () {
            // 避免设置界面手动检查后又自动检查
            if (!hasCheckedForUpdates) {
              // 忽略返回值，因为自动检查不需要显示"已是最新版本"的提示
              checkForUpdates();
            }
          });
        });
        return homeWidget;
      }
    );
  }
}

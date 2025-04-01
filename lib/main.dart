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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await _loadFonts();
  
  // 清理过期的天气缓存
  final weatherService = WeatherService();
  await weatherService.clearExpiredCache();
  
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

// 将 _MainAppState 改为公开的 MainAppState
class MainAppState extends State<MainApp> {
  ThemeMode _themeMode = ThemeMode.system;
  final _themeService = ThemeService();

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final mode = await _themeService.getThemeMode();
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      themeMode: _themeMode,
      home: widget.isFirstRun 
          ? const PolicyScreen(type: 'privacy', isFirstRun: true)
          : widget.isLoggedIn 
              ? const HomeScreen() 
              : const LoginScreen(),
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
  }
}

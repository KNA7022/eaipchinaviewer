import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';  // 添加这一行
import 'screens/weather_screen.dart';  // 添加这一行
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 使用 rootBundle 预加载字体
  await _loadFonts();
  
  final isLoggedIn = await AuthService().isLoggedIn();
  runApp(MainApp(isLoggedIn: isLoggedIn));
}

Future<void> _loadFonts() async {
  // 使用 rootBundle 加载字体文件
  try {
    await rootBundle.load('assets/fonts/NotoSansSC-Regular.otf');
    await rootBundle.load('assets/fonts/NotoSansSC-Medium.otf');
    await rootBundle.load('assets/fonts/NotoSansSC-Bold.otf');
  } catch (e) {
    print('字体加载失败: $e');
  }
}

class MainApp extends StatelessWidget {
  final bool isLoggedIn;
  
  const MainApp({super.key, required this.isLoggedIn});

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
      home: isLoggedIn ? const HomeScreen() : const LoginScreen(),
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

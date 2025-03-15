import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/rsa_helper.dart';
import 'package:http/io_client.dart';

class ApiService {
  static const baseUrl = 'https://www.eaipchina.cn/eaip';
  static const int timeout = 30;
  static const int maxRetries = 3;
  
  final Map<String, String> _defaultHeaders = {
          'Accept': 'application/json, text/plain, */*',
          'Accept-Encoding': 'gzip, deflate, br, zstd',
          'Accept-Language': 'en-US',
          'Connection': 'keep-alive',
          'Host': 'www.eaipchina.cn',
          'Origin': 'https://www.eaipchina.cn',
          'Referer': 'https://www.eaipchina.cn/',
          'Sec-Fetch-Dest': 'empty',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'same-origin',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
          'sec-ch-ua': '"Chromium";v="134", "Not:A-Brand";v="24", "Microsoft Edge";v="134"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': "Windows"
  };
  
  final Map<String, String> _cookies = {};
  bool _verifySSL = false; // 对应 verify=False
  Map<String, String>? _proxy;

  Map<String, String> get headers => _defaultHeaders;
  String? _token;
  String? _userId;
  Map<String, dynamic>? _currentPackage;

  // 新增：加载配置
  Future<void> loadConfig() async {
    try {
      // TODO: 实现配置文件加载
      final proxyUrl = ''; // 从配置文件读取
      if (proxyUrl.isNotEmpty) {
        _proxy = {
          'http': proxyUrl,
          'https': proxyUrl,
        };
      }
    } catch (e) {
      print('加载配置失败: $e');
    }
  }

  void setLoginCookies(String token, String userId) {
    _token = token;
    _userId = userId;
    
    // 更新headers中的所有必要字段
    _defaultHeaders.addAll({
      'token': token,
      'Content-Type': 'application/json',
      'Cookie': 'userId=$userId; username=$token',
    });
  }

  // 添加初始化方法
  Future<void> initializeWithAuth(String token, String userId) async {
    _token = token;
    _userId = userId;
    _defaultHeaders.addAll({
      'token': token,
      'Content-Type': 'application/json',
      'Cookie': 'userId=$userId; username=$token',
    });
  }

  // 检查和还原认证状态
  Future<bool> restoreAuth() async {
    if (_token != null) return true;
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userId = prefs.getString('user_id');
    
    if (token != null && userId != null) {
      await initializeWithAuth(token, userId);
      return true;
    }
    return false;
  }

  Future<HttpClient> _getHttpClient() async {
    HttpClient client = HttpClient()
      ..badCertificateCallback = 
          (X509Certificate cert, String host, int port) => true;
    return client;
  }

  Future<http.Client> _getClient() async {
    return IOClient(await _getHttpClient());
  }

  Future<Map<String, dynamic>?> login(String username, String password, String captcha, String captchaId) async {
    try {
      final encryptedPassword = RsaHelper.encryptPassword(password);
      final loginData = {
        'username': username,
        'password': encryptedPassword,
        'captcha': captcha,
        'captchaId': captchaId,
      };

      // 添加登录专用的headers
      final loginHeaders = Map<String, String>.from(_defaultHeaders)
        ..addAll({
          'Content-Type': 'application/json',
          'Content-Length': utf8.encode(jsonEncode(loginData)).length.toString()
        });

      print('请求头: ${JsonEncoder.withIndent('  ').convert(loginHeaders)}');
      print('登录数据: ${JsonEncoder.withIndent('  ').convert(loginData)}');

      final client = await _getClient();
      try {
        final response = await client.post(
          Uri.parse('$baseUrl/login/login'),
          headers: loginHeaders,
          body: jsonEncode(loginData),
        ).timeout(const Duration(seconds: timeout));

        print('响应状态码: ${response.statusCode}');
        print('响应数据: ${response.body}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['retCode'] == 200) {
            // 修改这里：使用setLoginCookies而不是setLoginCookie
            final token = data['data']['token'];
            final userUuid = data['data']['eaipUserUuid'];
            setLoginCookies(token, userUuid); // 直接设置token和userId
            print('登录成功，已设置token: $token'); // 调试日志
            print('登录成功，已设置userId: $userUuid'); // 调试日志
            return data;
          } else {
            print('登录失败：${data['retMsg'] ?? '未知错误'}');
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('登录请求异常: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getPackageList() async {
    try {
      // 尝试还原认证状态
      if (!await restoreAuth()) {
        throw Exception('需要登录');
      }

      // 检查是否有token
      if (_token == null) {
        print('Token不存在，需要重新登录');
        throw Exception('需要登录');
      }

      final headers = Map<String, String>.from(_defaultHeaders)
        ..addAll({
          'Content-Type': 'application/json',
          'Content-Length': '2',
          'token': _token!,
          'Cookie': 'userId=$_userId; username=$_token',
        });

      print('包列表完整请求头: ${JsonEncoder.withIndent('  ').convert(headers)}');
      
      // 第一次请求
      final client = await _getClient();
      final firstResponse = await client.post(
        Uri.parse('$baseUrl/package/listPage'),
        headers: headers,
        body: '{}',
      );

      if (firstResponse.statusCode != 200) {
        print('第一次请求失败: ${firstResponse.statusCode}');
        return null;
      }

      final firstData = jsonDecode(firstResponse.body);
      if (firstData['retCode'] == 0 && 
          firstData['retMsg']?.contains('login has expired') == true) {
        print('登录已过期，需要重新登录');
        return null;
      }

      // 等待1秒
      await Future.delayed(const Duration(seconds: 1));

      // 第二次请求
      final response = await client.post(
        Uri.parse('$baseUrl/package/listPage'),
        headers: headers,
        body: '{}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      }
    } catch (e) {
      print('获取包列表失败: $e');
      if (e.toString().contains('需要登录') || e.toString().contains('login has expired')) {
        return null;  // 返回null以触发重新登录流程
      }
      rethrow;
    }
    return null;
  }

  Future<List<dynamic>?> getCurrentAipStructure() async {
    try {
      final packages = await getPackageList();
      if (packages == null) return null;

      final packageList = packages['data']['data'] as List;
      final currentPackage = packageList.firstWhere(
        (pkg) => pkg['dataStatus'] == 'CURRENTLY_ISSUE',
        orElse: () => null,
      );

      if (currentPackage != null) {
        // 保存当前包信息用于构建PDF路径
        _currentPackage = currentPackage;
        return await getAipJson(currentPackage);
      }
    } catch (e) {
      print('获取AIP结构失败: $e');
    }
    return null;
  }

  Future<List<dynamic>?> getAipStructureForVersion(String version) async {
    try {
      final packages = await getPackageList();
      if (packages == null) return null;

      final packageList = packages['data']['data'] as List;
      final targetPackage = packageList.firstWhere(
        (pkg) => pkg['dataName'] == version,
        orElse: () => null,
      );

      if (targetPackage != null) {
        // 保存当前包信息用于构建PDF路径
        _currentPackage = targetPackage;
        return await getAipJson(targetPackage);
      }
    } catch (e) {
      print('获取版本AIP结构失败: $e');
    }
    return null;
  }

  String? buildPdfUrl(String pdfPath) {
    try {
      // 如果输入已经是完整URL，直接返回
      if (pdfPath.startsWith('https://')) {
        return pdfPath;
      }

      if (_currentPackage == null) {
        final List<String> parts = pdfPath.split('/');
        if (parts.length >= 3) {
          // 从完整路径中提取版本信息
          final version = parts[2]; // 例如: EAIP2025-02.V1.5
          // 从版本号中提取年月: EAIP2025-02.V1.5 -> 2025-02
          final RegExp yearMonthRegex = RegExp(r'EAIP(\d{4}-\d{2})');
          final match = yearMonthRegex.firstMatch(version);
          if (match != null) {
            final yearMonth = match.group(1);
            _currentPackage = {
              "filePath": "packageFile/BASELINE/$yearMonth",
              "dataName": version
            };
          }
        }
      }

      if (_currentPackage != null) {
        final String basePath = _currentPackage!["filePath"];
        final String version = _currentPackage!["dataName"];
        // 从完整路径中提取相对路径部分
        final List<String> parts = pdfPath.split('/');
        if (parts.length >= 4) {
          // 如果是/Data/开头的路径，去掉前3个部分
          if (parts[1] == "Data") {
            final String relativePath = parts.sublist(3).join('/');
            //print('构建PDF URL - 相对路径: $relativePath');
            return '$baseUrl/$basePath/$version/$relativePath';
          }
          
          // 其他情况直接使用完整路径
          return '$baseUrl/$pdfPath';
        }
      }
    } catch (e) {
      print('构建PDF URL失败: $e');
    }
    return null;
  }

  Future<List<dynamic>?> getAipJson(Map<String, dynamic> packageInfo) async {
    try {
      if (_token == null) {
        print('Token不存在，需要重新登录');
        return null;
      }

      final headers = Map<String, String>.from(_defaultHeaders)
        ..addAll({
          'token': _token!,
          'Cookie': 'userId=$_userId; username=$_token',
        });

      final String basePath = packageInfo["filePath"];
      // 移除版本拼接,直接使用basePath
      final url = "$baseUrl/$basePath/JsonPath/AIP.JSON";
      
      print('AIP.JSON请求头: ${JsonEncoder.withIndent('  ').convert(headers)}');
      print('请求URL: $url'); // 用于调试URL
      
      final client = await _getClient();
      final response = await client.get(
        Uri.parse(url),
        headers: headers,
      );
      
      if (response.statusCode != 200) {
        print("获取AIP.JSON失败, 状态码: ${response.statusCode}");
        return null;
      }
      
      final data = jsonDecode(response.body) as List<dynamic>;
      return data;
    } catch (e) {
      print("获取AIP.JSON失败: $e");
      return null;
    }
  }
}

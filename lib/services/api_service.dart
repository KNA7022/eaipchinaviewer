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


      final client = await _getClient();
      try {
        final response = await client.post(
          Uri.parse('$baseUrl/login/login'),
          headers: loginHeaders,
          body: jsonEncode(loginData),
        ).timeout(const Duration(seconds: timeout));


        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['retCode'] == 200) {
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
      print('开始获取航图版本列表');
      if (!await restoreAuth()) {
        print('认证状态恢复失败，需要重新登录');
        throw Exception('需要登录');
      }

      final requestBody = jsonEncode({
        'pageNo': 1,
        'pageSize': 50,
        'dataName': '',
        'dataType': '',  // 不在请求时过滤，而是在响应中过滤
        'dataStatus': ''
      });

      // 准备头部
      final headers = Map<String, String>.from(_defaultHeaders)
        ..addAll({
          'Content-Type': 'application/json',
          'Content-Length': utf8.encode(requestBody).length.toString(),
          'token': _token!,
          'Cookie': 'userId=$_userId; username=$_token',
        });

      print('请求体: $requestBody');
      print('请求头: ${JsonEncoder.withIndent('  ').convert(headers)}');

      final client = await _getClient();
      final response = await client.post(
        Uri.parse('$baseUrl/package/listPage'),
        headers: headers,
        body: requestBody,
      );

      print('响应状态码: ${response.statusCode}');


      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // 过滤响应数据，只保留 BASELINE 类型
        if (data['data']?['data'] != null) {
          final List<dynamic> allPackages = data['data']['data'];
          final List<dynamic> baselinePackages = allPackages
              .where((pkg) => pkg['dataType'] == 'BASELINE')
              .toList();
          
          // 替换原始数据
          data['data']['data'] = baselinePackages;
        }
        
        return data;
      }
    } catch (e, stack) {
      print('获取航图版本列表失败:');
      print('错误: $e');
      print('堆栈: $stack');
    }
    return null;
  }

  Future<List<dynamic>?> getCurrentAipStructure() async {
    try {
      print('开始获取当前航图结构');
      final packages = await getPackageList();
      if (packages == null) {
        print('获取版本列表失败，返回 null');
        return null;
      }

      final List<dynamic> allPackages = packages['data']['data'] as List;
      
      // 过滤出 BASELINE 类型的版本
      final baselinePackages = allPackages.where((pkg) {
        final isBaseline = pkg['dataType'] == 'BASELINE';
        print('检查版本 ${pkg['dataName']}: type=${pkg['dataType']}, isBaseline=$isBaseline');
        return isBaseline;
      }).toList();

      print('过滤后找到 ${baselinePackages.length} 个基准版本');
      if (baselinePackages.isEmpty) {
        print('没有找到基准版本，原始列表长度: ${allPackages.length}');
        print('所有版本类型: ${allPackages.map((p) => p['dataType']).toSet().toList()}');
        return null;
      }

      // 按生效时间排序，取最新的版本
      baselinePackages.sort((a, b) => 
        DateTime.parse(b['effectiveTime']).compareTo(
          DateTime.parse(a['effectiveTime'])
        )
      );

      final currentPackage = baselinePackages.first;
      print('选择的基准版本:');
      print(JsonEncoder.withIndent('  ').convert(currentPackage));
      
      _currentPackage = currentPackage;
      return await getAipJson(currentPackage);
    } catch (e, stack) {
      print('获取AIP结构失败:');
      print('错误: $e');
      print('堆栈: $stack');
    }
    return null;
  }

  Future<List<dynamic>?> getAipStructureForVersion(String version) async {
    try {
      final packages = await getPackageList();
      if (packages == null) return null;

      final packageList = packages['data']['data'] as List;
      
      // 只保留 BASELINE 类型的版本
      final baselinePackages = packageList.where((pkg) => 
        pkg['dataType'] == 'BASELINE'
      ).toList();

      print('版本切换: 找到 ${baselinePackages.length} 个基准版本');

      final targetPackage = baselinePackages.firstWhere(
        (pkg) => pkg['dataName'] == version,
        orElse: () => null,
      );

      if (targetPackage != null) {
        print('切换到版本: ${targetPackage['dataName']}');
        _currentPackage = targetPackage;
        return await getAipJson(targetPackage);
      } else {
        print('未找到指定的基准版本: $version');
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
        return null;
      }

      final headers = Map<String, String>.from(_defaultHeaders)
        ..addAll({
          'token': _token!,
          'Cookie': 'userId=$_userId; username=$_token',
        });

      final String basePath = packageInfo["filePath"];
      final url = "$baseUrl/$basePath/JsonPath/AIP.JSON";
      

      final client = await _getClient();
      final response = await client.get(
        Uri.parse(url),
        headers: headers,
      );
      
      if (response.statusCode != 200) {
        return null;
      }
      
      final data = jsonDecode(response.body) as List<dynamic>;
      return data;
    } catch (e) {
      return null;
    }
  }
}

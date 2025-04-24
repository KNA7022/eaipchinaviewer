import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../main.dart'; // 导入主文件以使用全局导航键

class UpdateService {
  static const String _updateUrl = 'https://gitee.com/KNA7022/eaipchinaviewerupdate/raw/master/version.json';
  
  // 添加标记，避免重复检查
  bool _isCheckingForUpdates = false;
  
  Future<Map<String, dynamic>?> checkForUpdates() async {
    // 如果正在检查更新，直接返回null
    if (_isCheckingForUpdates) {
      return null;
    }
    
    _isCheckingForUpdates = true;
    
    try {
      // 检查网络连接状态
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult == ConnectivityResult.none) {
        print('没有网络连接');
        _isCheckingForUpdates = false;
        return {'hasUpdate': false, 'error': '没有网络连接'};
      }
      
      final response = await http.get(Uri.parse(_updateUrl));
      
      if (response.statusCode == 200) {
        // 确保使用UTF-8解码
        final String responseBody = utf8.decode(response.bodyBytes);
        final updateInfo = json.decode(responseBody);
        final PackageInfo packageInfo = await PackageInfo.fromPlatform();
        final currentVersion = packageInfo.version;
        
        print('当前版本: $currentVersion, 远程版本: ${updateInfo['version']}');
        print('更新公告: ${updateInfo['notic']}');
        
        // 比较版本号
        if (_isNewerVersion(currentVersion, updateInfo['version'])) {
          _isCheckingForUpdates = false;
          return {
            'hasUpdate': true,
            'currentVersion': currentVersion,
            'newVersion': updateInfo['version'],
            'updateNotes': updateInfo['notic'] ?? '',
            'updateUrl': updateInfo['url'] ?? '',
            'sponsors': updateInfo['Sponsors'] ?? '',
          };
        } else {
          _isCheckingForUpdates = false;
          return {
            'hasUpdate': false,
            'sponsors': updateInfo['Sponsors'] ?? '',
          };
        }
      }
    } catch (e) {
      print('检查更新失败: $e');
    }
    
    _isCheckingForUpdates = false;
    return null;
  }
  
  Future<String> getSponsors() async {
    try {
      // 检查网络连接状态
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult == ConnectivityResult.none) {
        print('没有网络连接');
        return '';
      }
      
      final response = await http.get(Uri.parse(_updateUrl));
      
      if (response.statusCode == 200) {
        // 确保使用UTF-8解码
        final String responseBody = utf8.decode(response.bodyBytes);
        final updateInfo = json.decode(responseBody);
        
        return updateInfo['Sponsors'] ?? '';
      }
    } catch (e) {
      print('获取捐助者信息失败: $e');
    }
    
    return '';
  }
  
  bool _isNewerVersion(String currentVersion, String newVersion) {
    // 分割版本号的各个部分
    List<int> currentParts = currentVersion.split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    List<int> newParts = newVersion.split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
    
    // 确保两个列表长度相同
    while (currentParts.length < newParts.length) {
      currentParts.add(0);
    }
    while (newParts.length < currentParts.length) {
      newParts.add(0);
    }
    
    // 比较各个部分
    for (int i = 0; i < currentParts.length; i++) {
      if (newParts[i] > currentParts[i]) {
        return true;
      } else if (newParts[i] < currentParts[i]) {
        return false;
      }
    }
    
    return false; // 版本相同
  }
  
  Future<void> downloadAndInstallUpdate(BuildContext context, String apkUrl) async {
    // 验证 APK URL
    if (apkUrl.isEmpty) {
      _showErrorDialog('无法获取下载地址');
      return;
    }
    
    // 进度值
    ValueNotifier<double> progressValue = ValueNotifier<double>(0.0);
    
    // 显示下载进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('正在下载更新'),
            content: ValueListenableBuilder<double>(
              valueListenable: progressValue,
              builder: (context, progress, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 16),
                    Text('下载进度: ${(progress * 100).toStringAsFixed(1)}%'),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    
    // 检查权限
    try {
      bool permissionsGranted = false;
      
      if (Platform.isAndroid) {
        // 请求存储权限
        if (await Permission.storage.request().isGranted) {
          permissionsGranted = true;
        }
        
        // Android 10及以上可能需要所有文件访问权限
        if (!permissionsGranted && Platform.isAndroid) {
          if (await Permission.manageExternalStorage.request().isGranted) {
            permissionsGranted = true;
          }
        }
        
        // 如果权限仍未获取，显示错误
        if (!permissionsGranted) {
          _closeProgressDialog(context);
          _showErrorDialog('需要存储权限才能下载更新，请前往系统设置开启权限');
          return;
        }
      }
      
      // 获取下载目录
      Directory? directory;
      
      try {
        // 获取系统下载目录
        if (Platform.isAndroid) {
          directory = Directory('/storage/emulated/0/Download');
          if (!await directory.exists()) {
            await directory.create(recursive: true);
          }
        } else {
          directory = await getApplicationDocumentsDirectory();
        }
      } catch (e) {
        // 回退到应用文档目录
        directory = await getApplicationDocumentsDirectory();
      }
      
      if (directory == null) {
        _closeProgressDialog(context);
        _showErrorDialog('无法获取存储目录');
        return;
      }
      
      final filePath = '${directory.path}/eaipchinaviewer_update.apk';
      final file = File(filePath);
      
      print('开始下载APK: $apkUrl 到 $filePath');
      final client = http.Client();
      
      try {
        final request = http.Request('GET', Uri.parse(apkUrl));
        final response = await client.send(request);
        
        if (response.statusCode == 200) {
          final contentLength = response.contentLength ?? 0;
          
          // 创建文件并准备写入
          final sink = file.openWrite();
          int receivedBytes = 0;
          
          await response.stream.listen((bytes) {
            sink.add(bytes);
            receivedBytes += bytes.length;
            
            // 计算并更新进度
            if (contentLength > 0) {
              progressValue.value = receivedBytes / contentLength;
              print('下载进度: ${(progressValue.value * 100).toStringAsFixed(1)}%');
            }
          }).asFuture();
          
          await sink.flush();
          await sink.close();
          
          print('APK下载完成: $filePath');
          
          // 关闭进度对话框
          _closeProgressDialog(context);
          
          // 检查文件是否存在
          if (await file.exists()) {
            // 直接打开APK，让系统安装器处理
            final result = await OpenFile.open(filePath);
            
            if (result.type != ResultType.done) {
              print('自动打开安装包失败: ${result.message}');
              _showFileLocationDialog(context, filePath);
            }
          } else {
            _showErrorDialog('下载完成，但无法找到文件：$filePath');
          }
        } else {
          _closeProgressDialog(context);
          _showErrorDialog('下载失败，服务器返回状态码：${response.statusCode}');
        }
      } catch (e) {
        print('下载过程错误: $e');
        _closeProgressDialog(context);
        _showErrorDialog('下载过程中出错: $e');
      } finally {
        client.close();
      }
    } catch (e) {
      print('更新过程出错: $e');
      _closeProgressDialog(context);
      _showErrorDialog('更新过程出错: $e');
    }
  }
  
  void _closeProgressDialog(BuildContext context) {
    // 安全地关闭进度对话框
    if (navigatorKey.currentState != null && navigatorKey.currentState!.canPop()) {
      navigatorKey.currentState!.pop();
    }
  }
  
  void _showFileLocationDialog(BuildContext context, String filePath) {
    final ctx = navigatorKey.currentContext ?? context;
    if (ctx == null) return;
    
    showDialog(
      context: ctx,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('安装提示'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('安装包已下载到您的设备，请在文件管理器中找到并点击安装'),
              const SizedBox(height: 12),
              const Text('文件位置:'),
              const SizedBox(height: 4),
              Text(filePath, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('我知道了'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
  
  void _showErrorDialog(String message) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      print('无法显示错误对话框：$message');
      return;
    }
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('更新失败'),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('确定'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

// 自定义 StatefulBuilder 以便获取其 State
class StatefulBuilderState extends State<StatefulBuilder> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
} 
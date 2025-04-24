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
        // 针对不同Android版本使用不同的权限策略
        if (await Permission.requestInstallPackages.request().isGranted) {
          print('已获取安装未知应用权限');
          permissionsGranted = true;
        } else {
          print('尝试获取安装包权限失败，尝试获取存储权限');
          
          // 请求存储权限
          if (await Permission.storage.request().isGranted) {
            print('已获取存储权限');
            permissionsGranted = true;
          }
          
          // Android 10及以上可能需要所有文件访问权限
          if (!permissionsGranted && Platform.isAndroid) {
            final status = await Permission.manageExternalStorage.request();
            if (status.isGranted) {
              print('已获取管理外部存储权限');
              permissionsGranted = true;
            } else {
              print('管理外部存储权限请求结果: $status');
            }
          }
        }
        
        // 如果权限仍未获取，显示更详细的错误
        if (!permissionsGranted) {
          _closeProgressDialog(context);
          _showErrorDetailDialog(
            context,
            '权限不足，无法下载安装更新',
            '可能需要您前往系统设置手动开启以下权限：\n'
            '1. 允许安装来自未知来源的应用\n'
            '2. 存储空间访问权限\n\n'
            '您也可以直接下载APK手动安装，点击下方按钮前往下载页面',
            apkUrl
          );
          return;
        }
      }
      
      // 尝试两种不同的下载方法
      final downloadResult = await _tryDownloadWithMultipleMethods(context, apkUrl, progressValue);
      
      if (downloadResult == null || downloadResult.isEmpty) {
        _closeProgressDialog(context);
        _showErrorDialog('下载失败，请尝试使用浏览器下载');
        return;
      }
      
      print('APK下载完成: $downloadResult');
      
      // 关闭进度对话框
      _closeProgressDialog(context);
      
      // 尝试多种方法安装APK
      _tryInstallApk(context, downloadResult, apkUrl);
      
    } catch (e) {
      print('更新过程出错: $e');
      _closeProgressDialog(context);
      _showErrorDialog('更新过程出错: $e');
    }
  }
  
  // 尝试多种方法下载APK文件
  Future<String?> _tryDownloadWithMultipleMethods(
    BuildContext context, 
    String apkUrl, 
    ValueNotifier<double> progressValue
  ) async {
    // 先尝试直接下载到Download目录
    try {
      final filePath = await _downloadToPublicDirectory(apkUrl, progressValue);
      if (filePath != null) {
        return filePath;
      }
    } catch (e) {
      print('下载到公共目录失败: $e');
    }
    
    // 如果第一种方法失败，尝试下载到应用私有目录
    try {
      final filePath = await _downloadToPrivateDirectory(apkUrl, progressValue);
      if (filePath != null) {
        return filePath;
      }
    } catch (e) {
      print('下载到私有目录失败: $e');
    }
    
    return null;
  }
  
  // 下载APK到公共下载目录
  Future<String?> _downloadToPublicDirectory(String apkUrl, ValueNotifier<double> progressValue) async {
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
      print('获取公共下载目录失败: $e');
      return null;
    }
    
    if (directory == null) {
      return null;
    }
    
    final filePath = '${directory.path}/eaipchinaviewer_update.apk';
    final file = File(filePath);
    
    // 如果文件已存在，先删除它
    if (await file.exists()) {
      try {
        await file.delete();
        print('删除已存在的APK文件');
      } catch (e) {
        print('删除已存在的APK文件失败: $e');
      }
    }
    
    try {
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
          
          print('APK下载完成(公共目录): $filePath，总大小: ${await file.length()} 字节');
          
          // 延迟一下，确保文件写入完成
          await Future.delayed(const Duration(seconds: 1));
          
          if (await file.exists() && await file.length() > 0) {
            return filePath;
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('下载到公共目录错误: $e');
    }
    
    return null;
  }
  
  // 下载APK到应用私有目录
  Future<String?> _downloadToPrivateDirectory(String apkUrl, ValueNotifier<double> progressValue) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/update.apk';
      final file = File(filePath);
      
      // 如果文件已存在，先删除它
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          print('删除已存在的APK文件失败: $e');
        }
      }
      
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
          
          print('APK下载完成(私有目录): $filePath，总大小: ${await file.length()} 字节');
          
          // 延迟一下，确保文件写入完成
          await Future.delayed(const Duration(seconds: 1));
          
          if (await file.exists() && await file.length() > 0) {
            return filePath;
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      print('下载到私有目录错误: $e');
    }
    
    return null;
  }
  
  // 尝试多种方法安装APK
  Future<void> _tryInstallApk(BuildContext context, String filePath, String apkUrl) async {
    final file = File(filePath);
    if (!await file.exists()) {
      _showErrorDialog('安装文件不存在: $filePath');
      return;
    }
    
    print('尝试安装APK: $filePath');
    
    try {
      // 第一种方法：使用OpenFile
      final result = await OpenFile.open(filePath);
      
      if (result.type == ResultType.done) {
        print('使用OpenFile打开APK成功');
        return;
      }
      
      print('使用OpenFile打开APK失败: ${result.message}');
      
      // 第二种方法：尝试使用URL启动（部分设备上可能有效）
      if (Platform.isAndroid) {
        try {
          final apkUri = Uri.file(filePath);
          if (await canLaunchUrl(apkUri)) {
            print('尝试使用URL启动器打开APK');
            await launchUrl(apkUri, mode: LaunchMode.externalApplication);
            return;
          }
        } catch (e) {
          print('URL启动失败: $e');
        }
      }
      
      // 如果所有自动方法都失败，显示手动安装对话框
      _showManualInstallDialog(context, filePath, apkUrl);
    } catch (e) {
      print('尝试安装APK过程中出错: $e');
      _showManualInstallDialog(context, filePath, apkUrl);
    }
  }
  
  // 显示手动安装对话框（增强版）
  void _showManualInstallDialog(BuildContext context, String filePath, String originalUrl) {
    final ctx = navigatorKey.currentContext ?? context;
    if (ctx == null) return;
    
    showDialog(
      context: ctx,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('需要手动安装'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('已下载安装包，但需要手动完成安装：'),
              const SizedBox(height: 12),
              Text('文件位置: $filePath', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder),
                    label: const Text('打开文件位置'),
                    onPressed: () async {
                      try {
                        // 尝试打开文件所在的文件夹
                        final directory = Directory(filePath.substring(0, filePath.lastIndexOf('/')));
                        final uri = Uri.directory(directory.path);
                        
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        } else {
                          // 如果不能直接打开文件夹，至少尝试再次打开文件
                          await OpenFile.open(filePath);
                        }
                      } catch (e) {
                        print('打开文件位置失败: $e');
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('浏览器下载'),
                    onPressed: () async {
                      final uri = Uri.parse(originalUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '提示：\n1. 点击打开文件位置后，找到并点击APK文件\n'
                '2. 系统可能会提示允许来自此来源的应用安装\n'
                '3. 如果遇到问题，可以使用浏览器下载并安装',
                style: TextStyle(fontSize: 12),
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
          ],
        );
      },
    );
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
  
  void _showErrorDetailDialog(BuildContext context, String title, String message, String apkUrl) {
    final ctx = navigatorKey.currentContext ?? context;
    if (ctx == null) return;
    
    showDialog(
      context: ctx,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('浏览器下载'),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
                      // 使用浏览器打开下载链接
                      final uri = Uri.parse(apkUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } else {
                        if (ctx.mounted) {
                          _showErrorDialog('无法打开浏览器下载链接');
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '提示：下载完成后请点击APK文件进行安装',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('去设置'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                // 尝试打开应用设置页面
                try {
                  await openAppSettings();
                } catch (e) {
                  if (ctx.mounted) {
                    _showErrorDialog('无法打开设置页面');
                  }
                }
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
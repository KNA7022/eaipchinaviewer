import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../main.dart'; // 导入主文件以使用全局导航键

class DownloadTask {
  final String version;
  final String packageVersion;
  double progress;
  bool isDownloading;
  bool isCancelled = false;
  final VoidCallback? onCancelled;

  DownloadTask({
    required this.version,
    required this.packageVersion,
    this.progress = 0.0,
    this.isDownloading = false,
    this.onCancelled,
  });

  void cancel({bool showCancelledSnackBar = true, BuildContext? context}) {
    isCancelled = true;
    isDownloading = false;
    progress = 0.0;  // 重置进度
    if (showCancelledSnackBar && context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载已取消')),
      );
    }
    UpdateService.currentTask.value = null; // 取消后清空任务，隐藏提示栏
  }
}

class UpdateService {
  static final ValueNotifier<DownloadTask?> currentTask = ValueNotifier(null);
  /// 下载当期航图完整包（后台下载，不影响主界面）
  Future<void> downloadCurrentAipPackage(BuildContext context, {
    required String version, // 例如 '2025-07'
    required String packageVersion, // 例如 'V1.4'
    String? saveFileName, // 可选，默认用原始zip名
  }) async {
    // 检查网络连接
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      _showErrorDialog('没有网络连接', context: context);
      return;
    }

    // 检查是否有正在下载的任务
    if (currentTask.value != null && currentTask.value!.isDownloading) {
      // 显示统一的对话框，处理取消当前下载或切换到新版本
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('下载确认'),
          content: Text(
            currentTask.value!.version == version
            ? '当前版本正在下载中，是否取消下载？'
            : '正在下载版本 ${currentTask.value!.version}，是否切换到下载版本 $version？'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false), 
              child: Text(currentTask.value!.version == version ? '继续下载' : '取消')
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true), 
              child: Text(currentTask.value!.version == version ? '取消' : '切换')
            ),
          ],
        ),
      );

      if (shouldContinue != true) return;

      // 无论是取消当前版本还是切换到新版本，都需要取消当前任务
      currentTask.value?.cancel(showCancelledSnackBar: false);
      currentTask.value = null; // 立即清空当前任务，防止后续判断出错
      
      // 如果是取消当前版本的下载，直接返回
      if (currentTask.value != null && currentTask.value!.version == version) return;

      // 等待一小段时间确保旧任务完全取消
      await Future.delayed(const Duration(milliseconds: 100));

      // 新增：切换版本时提示开始下载哪个版本
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始下载版本 $version 的航图包')),
      );
    }

    // 获取token（即username）
    String token = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      token = prefs.getString('auth_token') ?? prefs.getString('saved_username') ?? '';
    } catch (e) {
      _showErrorDialog('无法获取登录信息，请重新登录', context: context);
      return;
    }
    if (token.isEmpty) {
      _showErrorDialog('未登录或登录信息失效，请重新登录', context: context);
      return;
    }

    // 拼接下载链接和文件名
    final url = 'https://www.eaipchina.cn/eaip/packageFile/BASELINE/$version/EAIP$version.$packageVersion/EAIP$version.$packageVersion\_Web.zip?token=$token';
    final fileName = saveFileName ?? 'EAIP$version.$packageVersion\_Web.zip';
    // 创建新的下载任务
    final task = DownloadTask(
      version: version,
      packageVersion: packageVersion,
      isDownloading: true,
      onCancelled: () {
        // 只有主动取消时才弹出“下载已取消”
        // 这里不做任何事，主动取消时在外部调用 cancel(showCancelledSnackBar: true, context: context)
      }
    );
    currentTask.value = task;

    // 开始下载
    _startDownload(context, url, fileName, task);
  }
  // 根据平台选择不同的更新URL
  static String get _updateUrl {
    if (Platform.isWindows) {
      return 'https://gitee.com/KNA7022/eaipchinaviewerupdate/raw/master/version_windows.json';
    } else if (Platform.isAndroid) {
      return 'https://gitee.com/KNA7022/eaipchinaviewerupdate/raw/master/version_android.json';
    } else {
      // 其他平台使用通用版本文件
      return 'https://gitee.com/KNA7022/eaipchinaviewerupdate/raw/master/version.json';
    }
  }
  
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
  
  Future<void> downloadAndInstallUpdate(BuildContext context, String updateUrl) async {
    // 验证更新URL
    if (updateUrl.isEmpty) {
      _showErrorDialog('无法获取下载地址');
      return;
    }
    
    // Windows平台直接打开下载链接
    if (Platform.isWindows) {
      await _handleWindowsUpdate(context, updateUrl);
      return;
    }
    
    // Android平台使用APK下载安装逻辑
    if (Platform.isAndroid) {
      await _handleAndroidUpdate(context, updateUrl);
      return;
    }
    
    // 其他平台暂不支持自动更新
    _showErrorDialog('当前平台暂不支持自动更新，请手动下载');
  }
  
  Future<void> _handleWindowsUpdate(BuildContext context, String updateUrl) async {
    try {
      // Windows平台直接打开下载链接
      final Uri uri = Uri.parse(updateUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        // 显示提示对话框
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('更新提示'),
              content: const Text(
                '已为您打开下载页面，请下载新版本并手动安装。\n\n'
                '安装完成后，建议重启应用以确保更新生效。'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      } else {
        _showErrorDialog('无法打开下载链接，请手动复制链接到浏览器下载');
      }
    } catch (e) {
      print('Windows更新处理失败: $e');
      _showErrorDialog('打开下载链接失败，请手动下载更新');
    }
  }
  
  Future<void> _handleAndroidUpdate(BuildContext context, String apkUrl) async {
    
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
  
  void _showErrorDialog(String message, {BuildContext? context}) {
    final ctx = context ?? navigatorKey.currentContext;
    if (ctx == null) {
      print('无法显示错误对话框：$message');
      return;
    }
    
    showDialog(
      context: ctx,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('错误'),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('确定'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  void _closeProgressDialog(BuildContext context) {
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
                        if (Theme.of(context).platform == TargetPlatform.android) {
                          // Android设备上，尝试直接打开设置
                          await openAppSettings();
                        } else {
                          // 其他平台，给出提示
                          _showErrorDialog('请手动下载并安装更新');
                        }
                      }
                    },
                  ),
                ],
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

  Future<void> _startDownload(BuildContext context, String url, String fileName, DownloadTask task) async {
    try {
      Directory directory;
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
      } else {
        directory = await getApplicationDocumentsDirectory();
      }
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      final client = http.Client();
      StreamSubscription? subscription;
      
      try {
        final request = http.Request('GET', Uri.parse(url));
        final response = await client.send(request);
        if (response.statusCode == 200) {
          final contentLength = response.contentLength ?? 0;
          final sink = file.openWrite();
          int receivedBytes = 0;

          subscription = response.stream.listen(
            (bytes) async {
              if (task.isCancelled) {
                subscription?.cancel();
                sink.close();
                try {
                  if (await file.exists()) {
                    await file.delete();
                  }
                } catch (e) {
                  print('删除文件失败: $e');
                }
                client.close();
                return;
              }

              sink.add(bytes);
              receivedBytes += bytes.length;
              if (contentLength > 0) {
                task.progress = receivedBytes / contentLength;
                currentTask.value = task;
              }
            },
            onDone: () async {
              await sink.flush();
              await sink.close();

              if (!task.isCancelled) {
                if (await file.exists() && await file.length() > 0) {
                  task.isDownloading = false;
                  currentTask.value = task;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('航图包下载完成: $fileName')),
                  );
                }
              }
            },
            onError: (error) async {
              print('下载错误: $error');
              if (!task.isCancelled) {
                task.isDownloading = false;
                currentTask.value = task;
                _showErrorDialog('下载失败: $error', context: context);
              }
              subscription?.cancel();
              await sink.close();
              try {
                if (await file.exists()) {
                  await file.delete();
                }
              } catch (e) {
                print('删除文件失败: $e');
              }
            },
            cancelOnError: true,
          );

          // 监听取消状态
          void checkCancellation() async {
            if (task.isCancelled) {
              subscription?.cancel();
              sink.close();
              try {
                if (await file.exists()) {
                  await file.delete();
                }
              } catch (e) {
                print('删除文件失败: $e');
              }
              client.close();
            }
          }
          
          // 定期检查是否被取消
          Timer.periodic(const Duration(milliseconds: 500), (timer) {
            if (task.isCancelled || !task.isDownloading) {
              checkCancellation();
              timer.cancel();
            }
          });
        } else {
          throw Exception('服务器返回错误: ${response.statusCode}');
        }
      } catch (e) {
        print('下载错误: $e');
        subscription?.cancel();
        if (!task.isCancelled) {
          task.isDownloading = false;
          currentTask.value = task;
          _showErrorDialog('下载失败: $e', context: context);
        }
      }
    } catch (e) {
      print('下载错误: $e');
      if (!task.isCancelled) {
        task.isDownloading = false;
        currentTask.value = task;
        _showErrorDialog('下载失败: $e', context: context);
      }
    }
  }
}
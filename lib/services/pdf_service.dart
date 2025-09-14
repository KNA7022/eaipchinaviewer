import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:internet_file/internet_file.dart';
import 'package:internet_file/storage_io.dart';
import '../services/auth_service.dart';

class PdfService {
  static const int maxRetries = 3;
  
  // 为了兼容性，添加downloadPdf方法
  Future<String> downloadPdf(String url, String title) async {
    return await downloadAndSavePdf(url);
  }
  
  Future<String> downloadAndSavePdf(
    String url, {
    void Function(int current, int total)? onProgress,
    String? version,
  }) async {
    final filename = _generateFileName(url);
    final dir = await _getVersionDirectory(version);
    final file = File('${dir.path}/$filename');

    if (await file.exists()) {
      return file.path;
    }

    try {
      int currentRetries = 0;
      while (currentRetries < maxRetries) {
        try {
          // 获取认证头信息
          final headers = await getRequestHeaders();
          
          // 使用internet_file包下载PDF文件
          await InternetFile.get(
            url,
            headers: headers,
            storage: InternetFileStorageIO(),
            storageAdditional: InternetFileStorageIO().additional(
              filename: filename,
              location: dir.path,
            ),
            progress: (received, total) {
              onProgress?.call(received, total);
            },
          );
          
          // Add a small delay to allow the file system to update its metadata.
          await Future.delayed(Duration(milliseconds: 500));
          if (await file.exists()) {
            print('flutter: PDF文件下载完成，延迟后文件大小: ${await file.length()} 字节');
          }
          return file.path;
        } catch (e) {
          currentRetries++;
          if (currentRetries >= maxRetries) {
            rethrow;
          }
          // Optional: Add a delay before retrying
          await Future.delayed(Duration(seconds: 2));
        }
      }
      // This line should ideally not be reached if rethrow is used above, but as a fallback
      throw Exception('Failed to download PDF after multiple retries');
    } catch (e) {
      // 如果下载失败，删除可能部分下载的文件
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  String _generateFileName(String url) {
    final hash = md5.convert(utf8.encode(url)).toString();
    return 'pdf_$hash.pdf';
  }

  Future<Directory> _getDocumentsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory('${dir.path}/pdfs');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }
    return pdfDir;
  }

  // 获取指定版本的缓存目录
  Future<Directory> _getVersionDirectory(String? version) async {
    final baseDir = await _getDocumentsDirectory();
    if (version == null || version.isEmpty) {
      // 如果没有版本信息，使用默认目录
      return baseDir;
    }
    
    // 从版本名称中提取版本号，如 EAIP2025-02.V1.5 -> 2025-02
    String versionFolder = version;
    final versionMatch = RegExp(r'EAIP(\d{4}-\d{2})').firstMatch(version);
    if (versionMatch != null) {
      versionFolder = versionMatch.group(1)!;
    }
    
    final versionDir = Directory('${baseDir.path}/$versionFolder');
    if (!await versionDir.exists()) {
      await versionDir.create(recursive: true);
    }
    return versionDir;
  }

  Future<Map<String, String>> getRequestHeaders() async {
    final authService = AuthService();
    final authData = await authService.getAuthData();
    final token = authData['token'];
    final userId = authData['userId'];

    return {
      'Accept': 'application/pdf',
      'Accept-Ranges': 'bytes',
      'Connection': 'keep-alive',
      'Content-Type': 'application/pdf',
      'Host': 'www.eaipchina.cn',
      'Origin': 'https://www.eaipchina.cn',
      'Referer': 'https://www.eaipchina.cn/',
      'token': token ?? '',
      'Cookie': 'userId=$userId; username=$token',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
    };
  }

  // 检查PDF是否已缓存
  Future<bool> isPdfCached(String url, {String? version}) async {
    final filename = _generateFileName(url);
    final dir = await _getVersionDirectory(version);
    final file = File('${dir.path}/$filename');
    return await file.exists();
  }

  // 获取缓存文件路径
  Future<String?> getCachedFilePath(String url, {String? version}) async {
    final filename = _generateFileName(url);
    final dir = await _getVersionDirectory(version);
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  // 获取缓存文件大小
  Future<int> getCachedFileSize(String url, {String? version}) async {
    final filename = _generateFileName(url);
    final dir = await _getVersionDirectory(version);
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  // 清理过期航图缓存
  Future<void> cleanExpiredCache(String? currentVersion, {List<dynamic>? versionList}) async {
    try {
      final baseDir = await _getDocumentsDirectory();
      if (!await baseDir.exists()) {
        return;
      }

      // 获取有效版本号集合
      Set<String> validVersions = {};
      
      if (versionList != null && versionList.isNotEmpty) {
        for (final version in versionList) {
          try {
            final dataStatus = version['dataStatus'];
            final dataName = version['dataName'];
            
            // 只保留当前版本和未来版本的缓存
            if (dataStatus == 'CURRENTLY_ISSUE' || dataStatus == 'NEXT_ISSUE') {
              if (dataName != null) {
                // 从版本名称中提取版本号，如 EAIP2025-02.V1.5 -> 2025-02
                final versionMatch = RegExp(r'EAIP(\d{4}-\d{2})').firstMatch(dataName);
                if (versionMatch != null) {
                  validVersions.add(versionMatch.group(1)!);
                }
              }
            }
          } catch (e) {
            print('解析版本信息失败: $e');
          }
        }
      }

      print('有效版本列表: $validVersions');

      // 遍历缓存目录中的所有子目录
      final entities = baseDir.listSync();
      int deletedFolders = 0;
      int totalSize = 0;

      for (final entity in entities) {
        if (entity is Directory) {
          final folderName = entity.path.split(Platform.pathSeparator).last;
          
          // 检查是否为版本文件夹（格式如 2025-02）
          if (RegExp(r'^\d{4}-\d{2}$').hasMatch(folderName)) {
            bool shouldDelete = false;
            
            if (validVersions.isNotEmpty) {
              // 如果有版本列表，删除不在有效版本列表中的文件夹
              shouldDelete = !validVersions.contains(folderName);
            } else {
              // 如果没有版本列表，删除超过30天的文件夹
              final folderStat = await entity.stat();
              final daysSinceModified = DateTime.now().difference(folderStat.modified).inDays;
              shouldDelete = daysSinceModified > 30;
            }
            
            if (shouldDelete) {
              try {
                // 计算文件夹大小
                final folderSize = await _calculateDirectorySize(entity);
                
                // 删除整个版本文件夹
                await entity.delete(recursive: true);
                deletedFolders++;
                totalSize += folderSize;
                print('删除过期版本缓存文件夹: $folderName');
              } catch (e) {
                print('删除文件夹 $folderName 时出错: $e');
              }
            }
          }
        } else if (entity is File && entity.path.endsWith('.pdf')) {
          // 处理根目录下的旧版本PDF文件（兼容旧缓存结构）
          try {
            final fileStat = await entity.stat();
            final daysSinceModified = DateTime.now().difference(fileStat.modified).inDays;
            
            if (daysSinceModified > 30) {
              final fileSize = await entity.length();
              await entity.delete();
              totalSize += fileSize;
              print('删除根目录下的旧缓存文件: ${entity.path}');
            }
          } catch (e) {
            print('处理根目录文件 ${entity.path} 时出错: $e');
          }
        }
      }

      if (deletedFolders > 0 || totalSize > 0) {
        final sizeInMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);
        print('清理完成：删除了 $deletedFolders 个过期版本文件夹，释放空间 ${sizeInMB}MB');
      } else {
        print('没有发现需要清理的过期缓存');
      }
    } catch (e) {
      print('清理过期PDF缓存失败: $e');
    }
  }

  // 计算目录大小
  Future<int> _calculateDirectorySize(Directory directory) async {
    int totalSize = 0;
    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
    } catch (e) {
      print('计算目录大小失败: $e');
    }
    return totalSize;
  }

  // 获取缓存目录中的所有PDF文件信息
  Future<List<Map<String, dynamic>>> getCacheFileInfo() async {
    try {
      final dir = await _getDocumentsDirectory();
      if (!await dir.exists()) {
        return [];
      }

      final files = dir.listSync();
      final List<Map<String, dynamic>> fileInfoList = [];

      for (final file in files) {
        if (file is File && file.path.endsWith('.pdf')) {
          try {
            final fileStat = await file.stat();
            final fileSize = await file.length();
            
            fileInfoList.add({
              'path': file.path,
              'name': file.path.split('/').last,
              'size': fileSize,
              'modified': fileStat.modified,
              'daysSinceModified': DateTime.now().difference(fileStat.modified).inDays,
            });
          } catch (e) {
            print('获取文件信息失败 ${file.path}: $e');
          }
        }
      }

      return fileInfoList;
    } catch (e) {
      print('获取缓存文件信息失败: $e');
      return [];
    }
  }
}

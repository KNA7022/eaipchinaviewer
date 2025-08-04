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
  }) async {
    final filename = _generateFileName(url);
    final dir = await _getDocumentsDirectory();
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
}

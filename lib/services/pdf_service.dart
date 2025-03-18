import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../services/auth_service.dart';

class PdfService {
  static const int maxRetries = 3;
  
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

    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;

    try {
      final request = await client.getUrl(Uri.parse(url));
      final headers = await getRequestHeaders();
      headers.forEach((key, value) => request.headers.set(key, value));
      
      final response = await request.close();
      final total = response.contentLength;
      var received = 0;
      
      final output = file.openWrite();
      await for (final chunk in response) {
        received += chunk.length;
        output.add(chunk);
        onProgress?.call(received, total);
      }
      await output.close();
      
      return file.path;
    } finally {
      client.close();
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

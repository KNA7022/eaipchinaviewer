import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';  // 添加这一行
import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class CaptchaImage extends StatefulWidget {
  final Function(String) onCaptchaIdGenerated;

  const CaptchaImage({
    super.key,
    required this.onCaptchaIdGenerated,
  });

  @override
  State<CaptchaImage> createState() => _CaptchaImageState();
}

class _CaptchaImageState extends State<CaptchaImage> {
  static const baseUrl = 'https://www.eaipchina.cn/eaip';
  final ApiService _apiService = ApiService();
  Uint8List? _imageBytes;
  String? _imageUrl;
  String? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCaptcha();
  }

  Future<http.Client> _getClient() async {
    HttpClient client = HttpClient()
      ..badCertificateCallback = 
          ((X509Certificate cert, String host, int port) => true);
    return IOClient(client);
  }

  Future<void> _loadCaptcha() async {
    setState(() => _isLoading = true);
    
    try {
      final captchaId = DateTime.now().millisecondsSinceEpoch.toString();
      widget.onCaptchaIdGenerated(captchaId);
      
      // 使用自定义client发送请求
      final client = await _getClient();
      final response = await client.get(
        Uri.parse('$baseUrl/login/captcha?captchaId=$captchaId'),
        headers: _apiService.headers,
      );
      
      if (response.statusCode == 200) {
        // 直接使用响应的二进制数据作为图片源
        _imageBytes = response.bodyBytes;
        _imageUrl = null; // 不再使用URL直接加载
        setState(() {});
      } else {
        throw Exception('验证码获取失败: ${response.statusCode}');
      }
    } catch (e) {
      print('加载验证码失败: $e');
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Colors.red)),
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                _loadCaptcha();
              },
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _loadCaptcha,
      child: _imageBytes != null
          ? Image.memory(
              _imageBytes!,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: TextButton(
                    onPressed: _loadCaptcha,
                    child: const Text('加载失败，点击重试'),
                  ),
                );
              },
            )
          : const Center(child: Text('点击加载验证码')),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/captcha_image.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();
  String _captchaId = '';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('尝试登录: ${_usernameController.text}'); // 用于调试
      print('验证码ID: $_captchaId'); // 用于调试
      
      final api = ApiService();
      final result = await api.login(
        _usernameController.text,
        _passwordController.text,
        _captchaController.text,
        _captchaId,
      );

      print('登录结果: $result'); // 用于调试

      if (result != null && result['retCode'] == 200) {
        final token = result['data']['token'];
        final userUuid = result['data']['eaipUserUuid'];
        
        // 保存凭证
        final authService = AuthService();
        await authService.saveAuthData(token, userUuid);
        
        // 初始化API服务
        final api = ApiService();
        await api.initializeWithAuth(token, userUuid);
        
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        setState(() {
          _errorMessage = result?['retMsg'] ?? '登录失败，请检查用户名和密码';
          _captchaController.clear();
          _refreshCaptcha();
        });
      }
    } catch (e) {
      print('登录异常: $e'); // 用于调试
      setState(() {
        _errorMessage = '网络错误，请重试';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _refreshCaptcha() {
    setState(() {
      _captchaId = DateTime.now().millisecondsSinceEpoch.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: '用户名'),
              validator: (value) => value?.isEmpty ?? true ? '请输入用户名' : null,
            ),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true,
              validator: (value) => value?.isEmpty ?? true ? '请输入密码' : null,
            ),
            const SizedBox(height: 20),
            CaptchaImage(
              onCaptchaIdGenerated: (id) => _captchaId = id,
            ),
            TextFormField(
              controller: _captchaController,
              decoration: const InputDecoration(labelText: '验证码'),
              validator: (value) => value?.isEmpty ?? true ? '请输入验证码' : null,
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}

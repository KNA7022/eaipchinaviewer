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
          // 清除导航堆栈并跳转到主页
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/home',
            (Route<dynamic> route) => false,
          );
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
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo和标题
                  const Icon(
                    Icons.flight,
                    size: 64,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'EAIP中国航图查看器',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  
                  // 登录表单
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) => value?.isEmpty ?? true ? '请输入用户名' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            decoration: const InputDecoration(
                              labelText: '密码',
                              prefixIcon: Icon(Icons.lock),
                              border: OutlineInputBorder(),
                            ),
                            obscureText: true,
                            validator: (value) => value?.isEmpty ?? true ? '请输入密码' : null,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _captchaController,
                                  decoration: const InputDecoration(
                                    labelText: '验证码',
                                    prefixIcon: Icon(Icons.security),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) => value?.isEmpty ?? true ? '请输入验证码' : null,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Card(
                                elevation: 2,
                                child: CaptchaImage(
                                  onCaptchaIdGenerated: (id) => _captchaId = id,
                                ),
                              ),
                            ],
                          ),
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: theme.colorScheme.onPrimary,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text('登 录'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // 底部版权信息
                  const SizedBox(height: 24),
                  Text(
                    '© 2025 EAIP中国航图查看器',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

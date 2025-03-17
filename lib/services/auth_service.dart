import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const _usernameKey = 'saved_username';
  static const _passwordKey = 'saved_password';
  static const _rememberMeKey = 'remember_me';

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) != null;
  }

  Future<void> saveAuthData(String token, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
  }

  Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
  }

  Future<void> saveCredentials(String username, String password, bool rememberMe) async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString(_usernameKey, username);
      await prefs.setString(_passwordKey, password);
    } else {
      await prefs.remove(_usernameKey);
      await prefs.remove(_passwordKey);
    }
    await prefs.setBool(_rememberMeKey, rememberMe);
  }

  Future<Map<String, dynamic>> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'username': prefs.getString(_usernameKey) ?? '',
      'password': prefs.getString(_passwordKey) ?? '',
      'rememberMe': prefs.getBool(_rememberMeKey) ?? false,
    };
  }

  // 添加获取凭证的方法
  Future<Map<String, String?>> getAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token': prefs.getString(_tokenKey),
      'userId': prefs.getString(_userIdKey),
    };
  }
}

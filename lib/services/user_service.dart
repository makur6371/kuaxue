import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static const String _baseUrl = 'https://makur.top/kuaxue-api';
  static const String _tokenKey = 'auth_token';
  static const String _usernameKey = 'auth_username';
  static const String _nicknameKey = 'auth_nickname';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  String? _token;
  String? _username;
  String? _nickname;

  String? get token => _token;
  String? get username => _username;
  String? get nickname => _nickname;
  bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  /// 从本地加载已保存的登录状态
  Future<bool> loadSavedAuth() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _username = prefs.getString(_usernameKey);
    _nickname = prefs.getString(_nicknameKey);

    if (_token == null || _token!.isEmpty) return false;

    // 验证 token 是否仍然有效
    try {
      final response = await _dio.get(
        '/api/auth/me',
        options: Options(headers: _authHeader()),
      );
      if (response.statusCode == 200) {
        final user = response.data['user'];
        _nickname = user['nickname'] ?? _username;
        return true;
      }
    } catch (_) {}
    // token 无效，清除
    await logout();
    return false;
  }

  /// 注册
  Future<String?> register(String username, String password, {String? nickname}) async {
    try {
      final response = await _dio.post('/api/auth/register', data: {
        'username': username,
        'password': password,
        if (nickname != null) 'nickname': nickname,
      });
      await _saveAuth(response.data);
      return null; // 成功
    } on DioException catch (e) {
      return _extractError(e);
    }
  }

  /// 登录
  Future<String?> login(String username, String password) async {
    try {
      final response = await _dio.post('/api/auth/login', data: {
        'username': username,
        'password': password,
      });
      await _saveAuth(response.data);
      return null; // 成功
    } on DioException catch (e) {
      return _extractError(e);
    }
  }

  /// 修改密码
  Future<String?> changePassword(String oldPassword, String newPassword) async {
    try {
      await _dio.post(
        '/api/auth/change-password',
        data: {'oldPassword': oldPassword, 'newPassword': newPassword},
        options: Options(headers: _authHeader()),
      );
      return null;
    } on DioException catch (e) {
      return _extractError(e);
    }
  }

  /// 退出登录
  Future<void> logout() async {
    _token = null;
    _username = null;
    _nickname = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_nicknameKey);
  }

  Future<void> _saveAuth(Map<String, dynamic> data) async {
    _token = data['token'];
    _username = data['user']['username'];
    _nickname = data['user']['nickname'] ?? _username;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, _token!);
    await prefs.setString(_usernameKey, _username!);
    await prefs.setString(_nicknameKey, _nickname!);
  }

  Map<String, String> _authHeader() => {
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  String _extractError(DioException e) {
    if (e.response?.data is Map) {
      return e.response?.data['error'] ?? '请求失败';
    }
    return '网络错误，请检查连接';
  }
}

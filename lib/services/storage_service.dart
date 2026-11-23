import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/api_config.dart';

class StorageService {
  static const _keyApiConfig = 'api_config';
  static const _keyThemeMode = 'theme_mode';
  static const _keyTtsSettings = 'tts_settings';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // API 配置
  Future<void> saveApiConfig(ApiConfig config) async {
    await _prefs.setString(_keyApiConfig, jsonEncode(config.toJson()));
  }

  ApiConfig loadApiConfig() {
    final json = _prefs.getString(_keyApiConfig);
    if (json == null) return const ApiConfig();
    return ApiConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  // 主题模式
  Future<void> saveThemeMode(String mode) async {
    await _prefs.setString(_keyThemeMode, mode);
  }

  String loadThemeMode() {
    return _prefs.getString(_keyThemeMode) ?? 'system';
  }

  // TTS 设置
  Future<void> saveTtsSettings(Map<String, dynamic> settings) async {
    await _prefs.setString(_keyTtsSettings, jsonEncode(settings));
  }

  Map<String, dynamic> loadTtsSettingsMap() {
    final json = _prefs.getString(_keyTtsSettings);
    if (json == null) return {};
    return jsonDecode(json) as Map<String, dynamic>;
  }
}

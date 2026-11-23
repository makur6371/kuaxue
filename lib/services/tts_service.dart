import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/api_config.dart';
import 'retry_interceptor.dart';

class TTSService {
  final Dio _dio = Dio();
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Completer<void>? _playCompleter;

  static const _voices = [
    'mimo_default', '冰糖', '茉莉', '苏打', '白桦',
    'Mia', 'Chloe', 'Milo', 'Dean',
  ];

  static List<String> get availableVoices => _voices;

  bool get isPlaying => _isPlaying;

  TTSService() {
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 60);

    _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _playCompleter?.complete();
      _playCompleter = null;
    });
  }

  /// 朗读文本
  Future<void> speak({
    required ApiConfig config,
    required String text,
    String voice = '冰糖',
    double speed = 0.5,
  }) async {
    final clean = _stripMarkdown(text);
    if (clean.trim().isEmpty) return;

    await stop();
    _isPlaying = true;
    _playCompleter = Completer<void>();

    try {
      // 调用 mimo TTS API
      final response = await _dio.post(
        '${config.baseUrl}/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': 'mimo-v2.5-tts',
          'messages': [
            {'role': 'user', 'content': '请朗读以下内容'},
            {'role': 'assistant', 'content': clean},
          ],
          'modalities': ['text', 'audio'],
          'audio': {
            'voice': voice,
            'format': 'mp3',
          },
        },
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List;
      if (choices.isEmpty) {
        _isPlaying = false;
        return;
      }

      final message = choices[0]['message'] as Map<String, dynamic>;
      final audio = message['audio'] as Map<String, dynamic>?;
      if (audio == null || audio['data'] == null) {
        _isPlaying = false;
        return;
      }

      final audioData = audio['data'] as String;
      final bytes = base64Decode(audioData);

      // 写入临时文件播放
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tts_temp.mp3');
      await file.writeAsBytes(bytes);

      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      _isPlaying = false;
      _playCompleter?.completeError(e);
      _playCompleter = null;
      rethrow;
    }
  }

  /// 等待播放完成
  Future<void> waitForCompletion() async {
    if (!_isPlaying) return;
    await _playCompleter?.future;
  }

  /// 停止朗读
  Future<void> stop() async {
    _isPlaying = false;
    _playCompleter?.complete();
    _playCompleter = null;
    await _player.stop();
  }

  /// 清理 Markdown 标记，保留纯文本
  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), '数学公式')
        .replaceAll(RegExp(r'\$[^$]+\$'), '数学公式')
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        .replaceAll(RegExp(r'```[\s\S]*?```'), '代码块')
        .replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'^\s*[-*+]\s', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*>\s', multiLine: true), '')
        .replaceAll(RegExp(r'---+'), '')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  void dispose() {
    _player.dispose();
  }
}

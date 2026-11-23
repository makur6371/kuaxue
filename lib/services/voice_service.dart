import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../models/api_config.dart';

enum VoiceErrorType { networkError, serverError, authError, audioTooShort, emptyResult, fileError, unknown }

class VoiceException implements Exception {
  final String message;
  final VoiceErrorType type;
  VoiceException(this.message, this.type);
  @override
  String toString() => message;
}

class VoiceService {
  AudioRecorder? _recorder;
  String? _currentPath;

  AudioRecorder _getRecorder() {
    _recorder ??= AudioRecorder();
    return _recorder!;
  }

  Future<bool> hasPermission() async {
    return await _getRecorder().hasPermission();
  }

  Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    _currentPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _getRecorder().start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _currentPath!,
    );
  }

  Future<String?> stopRecording() async {
    final path = await _getRecorder().stop();
    final resultPath = path ?? _currentPath;
    if (resultPath == null) return null;

    final file = File(resultPath);
    for (int i = 0; i < 10; i++) {
      if (await file.exists() && await file.length() > 0) {
        return resultPath;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> cancelRecording() async {
    await _getRecorder().stop();
    // 删除录音文件
    if (_currentPath != null) {
      try {
        final file = File(_currentPath!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      _currentPath = null;
    }
  }

  Future<bool> isRecording() async {
    return await _getRecorder().isRecording();
  }

  Future<String> transcribe({
    required ApiConfig config,
    required String audioPath,
    int maxRetries = 1,
  }) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw VoiceException('录音文件不存在', VoiceErrorType.fileError);
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw VoiceException('录音文件为空，请重试', VoiceErrorType.fileError);
    }

    if (bytes.length < 1000) {
      throw VoiceException('录音太短，请长按说话更久一些', VoiceErrorType.audioTooShort);
    }

    DioException? lastError;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final dio = Dio();
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: 'audio.wav'),
          'model': 'FunAudioLLM/SenseVoiceSmall',
        });

        final response = await dio.post(
          '${config.baseUrl}/audio/transcriptions',
          options: Options(
            headers: {'Authorization': 'Bearer ${config.apiKey}'},
            sendTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
          data: formData,
        );

        final data = response.data as Map<String, dynamic>;
        final text = data['text'] as String? ?? '';
        if (text.trim().isEmpty) {
          throw VoiceException('未识别到语音内容', VoiceErrorType.emptyResult);
        }
        return text;
      } on DioException catch (e) {
        lastError = e;
        if (e.response?.statusCode == 401) {
          throw VoiceException('API Key 无效，请检查设置', VoiceErrorType.authError);
        }
        if (e.response?.statusCode != null && e.response!.statusCode! >= 500) {
          // 服务端错误，可以重试
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt + 1));
            continue;
          }
          throw VoiceException('语音识别服务暂时不可用', VoiceErrorType.serverError);
        }
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt + 1));
            continue;
          }
          throw VoiceException('网络超时，请检查网络连接', VoiceErrorType.networkError);
        }
        if (e.type == DioExceptionType.connectionError) {
          throw VoiceException('网络连接失败，请检查网络', VoiceErrorType.networkError);
        }
        // 其他错误，重试
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        throw VoiceException('语音识别失败，请重试', VoiceErrorType.unknown);
      } catch (e) {
        if (e is VoiceException) rethrow;
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt + 1));
          continue;
        }
        throw VoiceException('语音识别失败: $e', VoiceErrorType.unknown);
      }
    }
    throw VoiceException('语音识别失败', VoiceErrorType.unknown);
  }

  void dispose() {
    _recorder?.dispose();
    _recorder = null;
  }
}

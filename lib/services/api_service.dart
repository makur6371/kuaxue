import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/api_config.dart';
import '../models/message.dart';
import 'prompt_service.dart';
import 'retry_interceptor.dart';

class _SSEEvent {
  final String? text;
  final List<Map<String, dynamic>>? toolCalls;
  _SSEEvent({this.text, this.toolCalls});
}

class SendMessageResult {
  final Stream<String> textStream;
  final Future<List<Map<String, dynamic>>> Function() getToolCalls;
  SendMessageResult(this.textStream, this.getToolCalls);
}

class _ToolCallBuilder {
  String id;
  String name;
  final StringBuffer argumentsBuffer = StringBuffer();
  _ToolCallBuilder({required this.id, required this.name});
}

class ApiService {
  final Dio _dio = Dio();
  ApiService() {
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
  }

  // Function Calling 工具定义
  static const List<Map<String, dynamic>> _tools = [
    {
      'type': 'function',
      'function': {
        'name': 'create_subject',
        'description': '创建一个新的学习科目文件夹',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': '科目名称'},
            'icon': {'type': 'string', 'description': '科目图标 emoji'},
            'color': {'type': 'string', 'description': '科目颜色 hex 值'},
          },
          'required': ['name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_subject',
        'description': '删除一个学习科目文件夹',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': '要删除的科目名称'},
          },
          'required': ['name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'rename_subject',
        'description': '重命名一个学习科目文件夹',
        'parameters': {
          'type': 'object',
          'properties': {
            'old_name': {'type': 'string', 'description': '原科目名称'},
            'new_name': {'type': 'string', 'description': '新科目名称'},
          },
          'required': ['old_name', 'new_name'],
        },
      },
    },
  ];

  Future<SendMessageResult> sendMessage({
    required ApiConfig config,
    required List<Message> messages,
    List<String>? imagePaths,
  }) async {
    final contents = <Map<String, dynamic>>[];

    // System prompt
    contents.add({
      'role': 'system',
      'content': PromptService.getSystemPrompt(config),
    });

    // 压缩历史消息
    final historyMessages = <Map<String, dynamic>>[];
    for (final msg in messages) {
      final content = <Map<String, dynamic>>[];

      if (msg.imagePaths != null && msg.imagePaths!.isNotEmpty) {
        for (final path in msg.imagePaths!) {
          content.add({
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$path'},
          });
        }
      }

      content.add({'type': 'text', 'text': msg.content});

      historyMessages.add({
        'role': msg.role == MessageRole.user ? 'user' : 'assistant',
        'content': content.length == 1 ? msg.content : content,
      });
    }

    // 上下文压缩
    final compressed = PromptService.compressHistory(historyMessages);
    contents.addAll(compressed);

    // 添加当前图片
    if (imagePaths != null && imagePaths.isNotEmpty) {
      final content = <Map<String, dynamic>>[];
      for (final path in imagePaths) {
        content.add({
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$path'},
        });
      }
      contents.add({'role': 'user', 'content': content});
    }

    // 有图片时用视觉模型
    final hasImage = contents.any((m) {
      final c = m['content'];
      if (c is List) return c.any((e) => e is Map && e['type'] == 'image_url');
      return false;
    });
    final model = hasImage ? config.visionModel : config.chatModel;

    // 构建请求体
    final requestData = <String, dynamic>{
      'model': model,
      'messages': contents,
      'stream': true,
      'max_tokens': 4096,
    };

    // 非视觉模型才加 tools（视觉模型一般不支持 function calling）
    if (!hasImage) {
      requestData['tools'] = _tools;
      requestData['tool_choice'] = 'auto';
    }

    final response = await _dio.post(
      '${config.baseUrl}/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
      data: requestData,
    );

    final rawStream = response.data.stream as Stream<List<int>>;
    final sseStream = _parseSSE(rawStream);

    // 分离文本和 tool calls
    final toolCallsCompleter = Completer<List<Map<String, dynamic>>>();
    final textController = StreamController<String>();

    sseStream.listen(
      (event) {
        if (event.text != null) {
          textController.add(event.text!);
        }
        if (event.toolCalls != null && !toolCallsCompleter.isCompleted) {
          toolCallsCompleter.complete(event.toolCalls!);
        }
      },
      onDone: () {
        if (!toolCallsCompleter.isCompleted) {
          toolCallsCompleter.complete([]);
        }
        textController.close();
      },
      onError: (e) {
        if (!toolCallsCompleter.isCompleted) {
          toolCallsCompleter.completeError(e);
        }
        textController.addError(e);
        textController.close();
      },
    );

    return SendMessageResult(
      textController.stream,
      () => toolCallsCompleter.future,
    );
  }

  /// 返回：(文本内容, function calls 列表)
  /// function calls 在流式结束后通过第二个元素返回
  Stream<_SSEEvent> _parseSSE(Stream<List<int>> stream) async* {
    String buffer = '';
    // 累积 function call 片段
    final Map<int, _ToolCallBuilder> toolCallBuilders = {};

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') {
          // 流结束，如果有累积的 function call，发出
          if (toolCallBuilders.isNotEmpty) {
            final calls = <Map<String, dynamic>>[];
            for (final builder in toolCallBuilders.values) {
              calls.add({
                'id': builder.id,
                'name': builder.name,
                'arguments': builder.argumentsBuffer.toString(),
              });
            }
            yield _SSEEvent(toolCalls: calls);
          }
          return;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          // 普通文本内容
          if (delta.containsKey('content') && delta['content'] != null) {
            yield _SSEEvent(text: delta['content'] as String);
          }

          // function call 片段
          if (delta.containsKey('tool_calls')) {
            final toolCalls = delta['tool_calls'] as List;
            for (final tc in toolCalls) {
              final index = tc['index'] as int? ?? 0;
              final fn = tc['function'] as Map<String, dynamic>?;

              if (!toolCallBuilders.containsKey(index)) {
                toolCallBuilders[index] = _ToolCallBuilder(
                  id: tc['id'] as String? ?? '',
                  name: fn?['name'] as String? ?? '',
                );
              }

              final builder = toolCallBuilders[index]!;
              // 更新 id（有时第一个 chunk 才有）
              if (tc['id'] != null) builder.id = tc['id'] as String;
              if (fn != null) {
                if (fn['name'] != null) builder.name = fn['name'] as String;
                if (fn['arguments'] != null) {
                  builder.argumentsBuffer.write(fn['arguments'] as String);
                }
              }
            }
          }
        } catch (_) {}
      }
    }
  }

  Future<String> analyzeImage({
    required ApiConfig config,
    required String base64Image,
    required String prompt,
  }) async {
    final response = await _dio.post(
      '${config.baseUrl}/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'model': config.visionModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
              },
              {'type': 'text', 'text': prompt},
            ],
          }
        ],
        'max_tokens': 4096,
      },
    );

    final data = response.data as Map<String, dynamic>;
    return data['choices'][0]['message']['content'] as String;
  }
}

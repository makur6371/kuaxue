import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import '../models/api_config.dart';
import 'retry_interceptor.dart';
import '../models/memory.dart';
import '../models/message.dart';
import '../models/subject.dart';
import '../models/todo.dart';
import '../services/memory_service.dart';
import '../services/prompt_service.dart';

/// 流式 LLM 响应（支持逐 token 输出）
class _StreamingLLMResponse {
  final Stream<String> textStream;
  final Future<List<Map<String, dynamic>>> getToolCalls;
  _StreamingLLMResponse({required this.textStream, required this.getToolCalls});
}

/// Agent 执行结果
class AgentResult {
  final Stream<String> textStream;
  final int iterations;
  final List<String> actions; // 执行过的动作记录

  AgentResult({
    required this.textStream,
    required this.iterations,
    required this.actions,
  });
}

/// Agent Loop 核心服务
/// 实现 Thought → Action → Observation → Reflection 循环
class AgentService {
  static const int _maxIterations = 5;

  final Dio _dio = Dio();
  AgentService() {
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
    {
      'type': 'function',
      'function': {
        'name': 'list_subjects',
        'description': '获取所有科目的列表',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    // 日程待办工具
    {
      'type': 'function',
      'function': {
        'name': 'create_todo',
        'description': '创建一条待办事项',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': '待办标题'},
            'description': {'type': 'string', 'description': '待办详情描述'},
            'due_date': {'type': 'string', 'description': '截止日期 ISO 格式，如 2026-06-16T14:00:00'},
            'priority': {'type': 'integer', 'description': '优先级 0=普通 1=重要 2=紧急'},
            'subject_id': {'type': 'string', 'description': '关联的科目ID'},
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'complete_todo',
        'description': '标记一条待办为已完成',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': '待办标题（模糊匹配）'},
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'delete_todo',
        'description': '删除一条待办事项',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': '待办标题（模糊匹配）'},
          },
          'required': ['title'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_todos',
        'description': '获取所有待办事项的列表',
        'parameters': {
          'type': 'object',
          'properties': {},
        },
      },
    },
    // 复习卡片工具
    {
      'type': 'function',
      'function': {
        'name': 'create_review_card',
        'description': '创建一张复习卡片，用于间隔重复记忆。适合将重要知识点、易错题目、公式定理等加入复习。',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': '卡片标题，如知识点名称或题目关键词'},
            'content': {'type': 'string', 'description': '卡片内容，包含知识点详解、解题思路、答案等'},
            'subject_id': {'type': 'string', 'description': '关联的科目ID（可选）'},
          },
          'required': ['title', 'content'],
        },
      },
    },
  ];

  /// 执行 Agent Loop
  /// [onAction] 回调：每次执行工具时通知 UI（用于显示执行状态）
  Future<AgentResult> run({
    required ApiConfig config,
    required List<Message> messages,
    required List<Subject> currentSubjects,
    List<Todo>? currentTodos,
    required Future<String?> Function(String name, Map<String, dynamic> args) onExecuteTool,
    void Function(String action)? onAction,
    MemoryService? memoryService,
  }) async {
    final actions = <String>[];
    int iteration = 0;

    // RAG：检索相关记忆（文档块 + 对话摘要，向量相似度自然排序）
    String memoryContext = '';
    if (memoryService != null && messages.isNotEmpty) {
      try {
        final lastUserMsg = messages.lastWhere(
          (m) => m.role == MessageRole.user,
          orElse: () => messages.last,
        );
        final memories = await memoryService.retrieve(
          config: config,
          query: lastUserMsg.content,
          topK: 5,
        );
        if (memories.isNotEmpty) {
          final sb = StringBuffer('\n\n## 相关知识\n');
          for (final m in memories) {
            sb.writeln('- ${m.content}');
          }
          memoryContext = sb.toString();
        }
      } catch (_) {}
    }

    // Token 预算管理：system prompt + RAG + history 总量控制
    const totalBudget = 8000;
    final systemPrompt = PromptService.getSystemPrompt(config);
    final systemTokens = PromptService.estimateTokens(systemPrompt);
    final ragTokens = PromptService.estimateTokens(memoryContext);
    // RAG 内容截断到总预算的 30%
    final ragBudget = (totalBudget * 0.3).toInt();
    if (ragTokens > ragBudget && memoryContext.isNotEmpty) {
      final ratio = ragBudget / ragTokens;
      final cutLen = (memoryContext.length * ratio).toInt();
      memoryContext = memoryContext.substring(0, cutLen);
    }
    // 历史消息使用剩余预算
    final historyBudget = max(2000, totalBudget - systemTokens - PromptService.estimateTokens(memoryContext));

    // 构建完整消息列表（含 system prompt）
    final fullMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt + memoryContext},
      ...PromptService.compressHistory(_messagesToApi(messages), maxTokens: historyBudget),
    ];

    // 流式输出控制器：创建在循环外，所有迭代共享同一个 stream
    final controller = StreamController<String>();

    // 注入当前科目和待办到上下文（循环外，只注入一次）
    final subjectContext = _buildSubjectContext(currentSubjects);
    final todoContext = _buildTodoContext(currentTodos ?? []);
    final fullContext = [subjectContext, todoContext].where((s) => s.isNotEmpty).join('\n\n');
    if (fullContext.isNotEmpty) {
      if (fullMessages.length > 1 && fullMessages[1]['role'] == 'system') {
        fullMessages[1] = {
          'role': 'system',
          'content': '${fullMessages[1]['content']}\n\n$fullContext',
        };
      }
    }

    // Agent Loop
    while (iteration < _maxIterations) {
      iteration++;

      // 流式请求
      final streaming = await _callLLMStream(config, fullMessages);

      // 流式消费：实时转发 token 到 controller，同时收集完整文本
      final collected = StringBuffer();
      final toolCalls = await _consumeStreamProxy(
        streaming,
        controller,
        collected,
        isFirstIteration: iteration == 1,
      );

      if (toolCalls.isEmpty) {
        // 无工具调用 → 流已实时输出完毕，关闭 controller 并返回
        final finalText = collected.toString();
        if (memoryService != null && messages.isNotEmpty) {
          _storeConversationMemory(
            config: config,
            memoryService: memoryService,
            messages: messages,
            response: finalText,
            actions: actions,
          );
        }
        if (!controller.isClosed) controller.close();
        return AgentResult(
          textStream: controller.stream,
          iterations: iteration,
          actions: actions,
        );
      } else {
        // 有工具调用 → 执行后继续循环（中间迭代的文本不输出到 UI）
        final toolResults = <Map<String, dynamic>>[];
        for (final call in toolCalls) {
          final name = call['name'] as String;
          final argsStr = call['arguments'] as String;
          final args = argsStr.isNotEmpty
              ? jsonDecode(argsStr) as Map<String, dynamic>
              : <String, dynamic>{};
          onAction?.call('$name(${args.values.join(", ")})');
          final result = await onExecuteTool(name, args);
          actions.add('$name → ${result ?? "完成"}');
          toolResults.add({
            'tool_call_id': call['id'] ?? '',
            'role': 'tool',
            'content': result ?? '操作已执行',
          });
        }
        fullMessages.add({
          'role': 'assistant',
          'content': collected.toString(),
          'tool_calls': toolCalls.map((tc) => {
            'id': tc['id'],
            'type': 'function',
            'function': {
              'name': tc['name'],
              'arguments': tc['arguments'],
            },
          }).toList(),
        });
        fullMessages.addAll(toolResults);
        continue;
      }
    }

    // 超过最大轮次
    if (!controller.isClosed) controller.close();
    return AgentResult(
      textStream: controller.stream,
      iterations: iteration,
      actions: actions,
    );
  }

  /// 流式消费代理：实时转发 token 到输出 controller，同时收集完整文本
  /// 返回值：该次迭代的工具调用列表（为空表示纯文本回复）
  Future<List<Map<String, dynamic>>> _consumeStreamProxy(
    _StreamingLLMResponse streaming,
    StreamController<String> outputController,
    StringBuffer collected, {
    bool isFirstIteration = true,
  }) async {
    final completer = Completer<List<Map<String, dynamic>>>();

    streaming.textStream.listen(
      (token) {
        collected.write(token);
        if (isFirstIteration && !outputController.isClosed) {
          outputController.add(token);
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.complete([]);
      },
      onDone: () async {
        // 文本流结束，获取工具调用
        final calls = await streaming.getToolCalls;
        if (!completer.isCompleted) completer.complete(calls);
      },
    );

    return completer.future;
  }

  /// 调用 LLM
  Future<_LLMResponse> _callLLM(
    ApiConfig config,
    List<Map<String, dynamic>> messages,
  ) async {
    // 判断是否需要用视觉模型
    final hasImage = messages.any((m) {
      final c = m['content'];
      if (c is List) return c.any((e) => e is Map && e['type'] == 'image_url');
      return false;
    });
    final model = hasImage ? config.visionModel : config.chatModel;

    final requestData = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': 4096,
    };

    // 非视觉模型才加 tools
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
      ),
      data: requestData,
    );

    final data = response.data as Map<String, dynamic>;
    final choice = data['choices'][0];
    final message = choice['message'] as Map<String, dynamic>;

    return _LLMResponse(
      text: message['content'] as String? ?? '',
      toolCalls: _parseToolCalls(message),
      finishReason: choice['finish_reason'] as String? ?? '',
    );
  }

  /// 流式调用 LLM（逐 token 输出）
  Future<_StreamingLLMResponse> _callLLMStream(
    ApiConfig config,
    List<Map<String, dynamic>> messages,
  ) async {
    final hasImage = messages.any((m) {
      final c = m['content'];
      if (c is List) return c.any((e) => e is Map && e['type'] == 'image_url');
      return false;
    });
    final model = hasImage ? config.visionModel : config.chatModel;

    final requestData = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': 4096,
      'stream': true,
    };

    if (!hasImage) {
      requestData['tools'] = _tools;
      requestData['tool_choice'] = 'auto';
    }

    final response = await _dio.post<ResponseBody>(
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

    final controller = StreamController<String>();
    final toolCallsCompleter = Completer<List<Map<String, dynamic>>>();
    final toolCallBuilders = <String, _ToolCallBuilder>{};
    String accumulated = '';

    response.data!.stream
        .map((bytes) => utf8.decode(bytes))
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (!line.startsWith('data: ')) return;
        final data = line.substring(6).trim();
        if (data == '[DONE]') {
          final calls = toolCallBuilders.values
              .map((b) => {
                    'id': b.id,
                    'name': b.name,
                    'arguments': b.arguments.toString(),
                  })
              .toList();
          if (!toolCallsCompleter.isCompleted) {
            toolCallsCompleter.complete(calls);
          }
          controller.close();
          return;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) return;
          final delta = choices[0]['delta'] as Map<String, dynamic>? ?? {};

          // 文本 token
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            accumulated += content;
            controller.add(content);
          }

          // 工具调用片段
          final toolCalls = delta['tool_calls'] as List?;
          if (toolCalls != null) {
            for (final tc in toolCalls) {
              final idx = (tc['index'] as int).toString();
              final fn = tc['function'] as Map<String, dynamic>?;
              if (!toolCallBuilders.containsKey(idx)) {
                toolCallBuilders[idx] = _ToolCallBuilder(
                  id: tc['id'] as String? ?? '',
                  name: fn?['name'] as String? ?? '',
                );
              }
              final args = fn?['arguments'] as String?;
              if (args != null) {
                toolCallBuilders[idx]!.arguments.write(args);
              }
            }
          }
        } catch (_) {}
      },
      onError: (e) {
        if (!toolCallsCompleter.isCompleted) {
          toolCallsCompleter.complete([]);
        }
        controller.addError(e);
        controller.close();
      },
      onDone: () {
        if (!toolCallsCompleter.isCompleted) {
          toolCallsCompleter.complete([]);
        }
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );

    return _StreamingLLMResponse(
      textStream: controller.stream,
      getToolCalls: toolCallsCompleter.future,
    );
  }

  List<Map<String, dynamic>> _parseToolCalls(Map<String, dynamic> message) {
    if (!message.containsKey('tool_calls') || message['tool_calls'] == null) {
      return [];
    }
    final toolCalls = message['tool_calls'] as List;
    return toolCalls.map((tc) {
      final fn = tc['function'] as Map<String, dynamic>;
      return {
        'id': tc['id'] as String? ?? '',
        'name': fn['name'] as String? ?? '',
        'arguments': fn['arguments'] as String? ?? '{}',
      };
    }).toList();
  }

  Future<_ParsedResponse> _parseResponse(_LLMResponse response) async {
    return _ParsedResponse(
      text: response.text,
      toolCalls: response.toolCalls,
    );
  }

  List<Map<String, dynamic>> _messagesToApi(List<Message> messages) {
    return messages.map((msg) {
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
      return {
        'role': msg.role == MessageRole.user ? 'user' : 'assistant',
        'content': content.length == 1 ? msg.content : content,
      };
    }).toList();
  }

  String _buildSubjectContext(List<Subject> subjects) {
    if (subjects.isEmpty) return '当前没有科目。';
    final sb = StringBuffer('当前科目列表：\n');
    for (final s in subjects) {
      sb.writeln('- ${s.icon ?? "📚"} ${s.name} (id: ${s.id})');
    }
    return sb.toString();
  }

  String _buildTodoContext(List<Todo> todos) {
    if (todos.isEmpty) return '';
    final pending = todos.where((t) => !t.isDone).toList();
    if (pending.isEmpty) return '当前没有未完成的待办。';
    final sb = StringBuffer('当前未完成待办：\n');
    for (final t in pending) {
      final due = t.dueDate != null ? '，截止 ${t.dueDate!.month}/${t.dueDate!.day}' : '';
      final pri = t.priority == 2 ? ' [紧急]' : t.priority == 1 ? ' [重要]' : '';
      sb.writeln('- ${t.title}$due$pri');
    }
    return sb.toString();
  }

  /// 存入对话摘要记忆（异步，不阻塞返回）
  void _storeConversationMemory({
    required ApiConfig config,
    required MemoryService memoryService,
    required List<Message> messages,
    required String response,
    required List<String> actions,
  }) {
    // 异步执行，不阻塞
    Future(() async {
      try {
        // 取最后几轮对话生成摘要
        final recentMsgs = messages.length > 4
            ? messages.sublist(messages.length - 4)
            : messages;

        final summary = StringBuffer();
        for (final msg in recentMsgs) {
          final prefix = msg.role == MessageRole.user ? '用户' : '助手';
          final content = msg.content.length > 200
              ? '${msg.content.substring(0, 200)}...'
              : msg.content;
          summary.writeln('$prefix: $content');
        }
        if (actions.isNotEmpty) {
          summary.writeln('执行操作: ${actions.join(", ")}');
        }

        await memoryService.store(
          config: config,
          type: 'conversation_summary',
          content: summary.toString(),
          metadata: {
            'message_count': messages.length,
            'action_count': actions.length,
          },
        );

        // 清理过多的记忆
        final count = await memoryService.count();
        if (count > 600) {
          await memoryService.prune(keepRecent: 500);
        }
      } catch (_) {}
    });
  }
}

class _LLMResponse {
  final String text;
  final List<Map<String, dynamic>> toolCalls;
  final String finishReason;
  _LLMResponse({required this.text, required this.toolCalls, required this.finishReason});
}

class _ParsedResponse {
  final String text;
  final List<Map<String, dynamic>> toolCalls;
  _ParsedResponse({required this.text, required this.toolCalls});
}

class _ToolCallBuilder {
  final String id;
  final String name;
  final StringBuffer arguments;
  _ToolCallBuilder({required this.id, required this.name})
      : arguments = StringBuffer();
}

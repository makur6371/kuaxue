import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/api_config.dart';
import '../models/document.dart';
import '../models/knowledge_card.dart';
import '../models/message.dart';
import '../models/review_card.dart';
import '../models/subject.dart';
import '../models/todo.dart';
import '../services/review_service.dart';
import '../services/agent_service.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../services/memory_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../services/voice_service.dart';
import '../services/notification_service.dart';

// Storage Service
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

// API Config
final apiConfigProvider = StateNotifierProvider<ApiConfigNotifier, ApiConfig>((ref) {
  return ApiConfigNotifier(ref.read(storageServiceProvider));
});

class ApiConfigNotifier extends StateNotifier<ApiConfig> {
  final StorageService _storage;

  ApiConfigNotifier(this._storage) : super(const ApiConfig()) {
    state = _storage.loadApiConfig();
  }

  Future<void> update(ApiConfig config) async {
    state = config;
    await _storage.saveApiConfig(config);
  }
}

// Chat Messages
final chatMessagesProvider =
    StateNotifierProvider<ChatNotifier, List<Message>>((ref) {
  return ChatNotifier(ref);
});

class ChatNotifier extends StateNotifier<List<Message>> {
  final Ref _ref;
  final _agentService = AgentService();
  final _apiService = ApiService();
  final _voiceService = VoiceService();
  final _uuid = const Uuid();

  ChatNotifier(this._ref) : super([]) {
    _loadHistory();
  }

  static const _pageSize = 100;
  bool _hasMore = true;

  Future<void> _loadHistory() async {
    final db = _ref.read(databaseServiceProvider);
    final count = await db.getChatMessageCount();
    final offset = count > _pageSize ? count - _pageSize : 0;
    final messages = await db.getChatMessages(limit: _pageSize, offset: offset);
    _hasMore = offset > 0;
    if (messages.isNotEmpty) {
      state = messages;
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore) return;
    final db = _ref.read(databaseServiceProvider);
    final older = await db.getChatMessages(limit: _pageSize, offset: state.length);
    if (older.length < _pageSize) _hasMore = false;
    if (older.isNotEmpty) {
      state = [...older, ...state];
    }
  }

  void _persistMessage(Message msg) {
    _ref.read(databaseServiceProvider).insertChatMessage(msg);
  }

  Future<void> sendMessage(String content, {List<String>? imagePaths}) async {
    final config = _ref.read(apiConfigProvider);
    if (!config.isConfigured) {
      _appendSystemMsg('请先在设置中配置 API Key');
      return;
    }

    // 添加用户消息
    final userMsg = Message(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: content,
      imagePaths: imagePaths,
      createdAt: DateTime.now(),
    );
    state = [...state, userMsg];
    _persistMessage(userMsg);

    // 添加 AI 消息占位
    final aiMsg = Message(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
      createdAt: DateTime.now(),
    );
    state = [...state, aiMsg];

    try {
      final subjects = _ref.read(subjectsProvider);
      final todos = _ref.read(todosProvider);
      final memoryService = _ref.read(memoryServiceProvider);

      final result = await _agentService.run(
        config: config,
        messages: state.where((m) => m.role != MessageRole.system).toList(),
        currentSubjects: subjects,
        currentTodos: todos,
        onExecuteTool: _executeTool,
        memoryService: memoryService,
        onAction: (action) {
          // 在 AI 消息中显示当前正在执行的动作
          final current = _getMsgContent(aiMsg.id);
          _updateMessage(aiMsg.id, '$current\n⏳ $action...', isStreaming: true);
        },
      );

      // Agent Loop 完成，流式输出最终回复
      String finalText = '';
      await for (final token in result.textStream) {
        finalText += token;
        _updateMessage(aiMsg.id, finalText, isStreaming: true);
      }

      // 拼接动作记录（如果有多个迭代）
      String display = finalText;
      if (result.iterations > 1 && result.actions.isNotEmpty) {
        final actionLog = result.actions.map((a) => '✓ $a').join('\n');
        display = '📋 **执行了 ${result.actions.length} 步操作：**\n$actionLog\n\n---\n\n$finalText';
      }

      _updateMessage(aiMsg.id, display, isStreaming: false);
      // 持久化最终 AI 消息
      _persistMessage(aiMsg.copyWith(content: display, isStreaming: false));
    } catch (e) {
      final errStr = e.toString();
      final msg = errStr.contains('400')
          ? '对话内容过长，请清空聊天记录后重试'
          : '请求失败: $errStr';
      _updateMessage(aiMsg.id, msg, isStreaming: false);
      _persistMessage(aiMsg.copyWith(content: msg, isStreaming: false));
    }
  }

  /// 执行工具调用
  Future<String?> _executeTool(String name, Map<String, dynamic> args) async {
    try {
    final subjectsNotifier = _ref.read(subjectsProvider.notifier);
    final subjects = _ref.read(subjectsProvider);

    switch (name) {
      case 'create_subject':
        final subjectName = args['name'] as String? ?? '';
        final icon = args['icon'] as String? ?? '📚';
        final color = args['color'] as String? ?? '#88D8B0';
        if (subjectName.isNotEmpty) {
          await subjectsNotifier.add(subjectName, icon: icon, color: color);
          return '已创建科目「$subjectName」$icon';
        }
        return '错误：科目名称为空';

      case 'delete_subject':
        final subjectName = args['name'] as String? ?? '';
        final match = subjects.where((s) =>
            s.name == subjectName || s.name.contains(subjectName));
        if (match.isNotEmpty) {
          await subjectsNotifier.delete(match.first.id);
          return '已删除科目「${match.first.name}」';
        }
        return '未找到科目「$subjectName」，当前科目：${subjects.map((s) => s.name).join("、")}';

      case 'rename_subject':
        final oldName = args['old_name'] as String? ?? '';
        final newName = args['new_name'] as String? ?? '';
        final match = subjects.where((s) =>
            s.name == oldName || s.name.contains(oldName));
        if (match.isNotEmpty && newName.isNotEmpty) {
          await subjectsNotifier.update(match.first.copyWith(name: newName));
          return '已将「${match.first.name}」重命名为「$newName」';
        }
        return '未找到科目「$oldName」';

      case 'list_subjects':
        if (subjects.isEmpty) return '当前没有科目';
        return subjects.map((s) => '${s.icon ?? "📚"} ${s.name}').join('\n');

      // 待办管理
      case 'create_todo':
        final title = args['title'] as String? ?? '';
        if (title.isEmpty) return '错误：待办标题为空';
        final dueDateStr = args['due_date'] as String?;
        final priorityRaw = args['priority'];
        final priority = priorityRaw is int ? priorityRaw : int.tryParse(priorityRaw?.toString() ?? '') ?? 0;
        final subjectId = args['subject_id'] as String?;
        final description = args['description'] as String?;
        DateTime? dueDate;
        if (dueDateStr != null && dueDateStr.isNotEmpty) {
          dueDate = DateTime.tryParse(dueDateStr);
          if (dueDate == null) {
            // 尝试解析常见格式如 "2026-06-16 14:00"
            dueDate = DateTime.tryParse(dueDateStr.replaceAll(' ', 'T'));
          }
        }
        final todo = Todo(
          id: const Uuid().v4(),
          title: title,
          description: description,
          dueDate: dueDate,
          priority: priority,
          subjectId: subjectId,
          createdAt: DateTime.now(),
        );
        await _ref.read(todosProvider.notifier).add(todo);
        return '已创建待办「$title」${dueDate != null ? "，截止 ${dueDate.month}/${dueDate.day} ${dueDate.hour}:${dueDate.minute.toString().padLeft(2, '0')}" : ""}';

      case 'complete_todo':
        final title = args['title'] as String? ?? '';
        final todos = _ref.read(todosProvider);
        final match = todos.where((t) =>
            !t.isDone && (t.title == title || t.title.contains(title)));
        if (match.isNotEmpty) {
          await _ref.read(todosProvider.notifier).toggleDone(match.first.id);
          return '已完成待办「${match.first.title}」';
        }
        return '未找到未完成的待办「$title」';

      case 'delete_todo':
        final title = args['title'] as String? ?? '';
        final todos = _ref.read(todosProvider);
        final match = todos.where((t) =>
            t.title == title || t.title.contains(title));
        if (match.isNotEmpty) {
          await _ref.read(todosProvider.notifier).delete(match.first.id);
          return '已删除待办「${match.first.title}」';
        }
        return '未找到待办「$title」';

      case 'list_todos':
        final todos = _ref.read(todosProvider);
        if (todos.isEmpty) return '当前没有待办事项';
        final pending = todos.where((t) => !t.isDone).toList();
        final done = todos.where((t) => t.isDone).toList();
        final sb = StringBuffer();
        if (pending.isNotEmpty) {
          sb.writeln('📋 未完成：');
          for (final t in pending) {
            final due = t.dueDate != null ? ' (截止 ${t.dueDate!.month}/${t.dueDate!.day})' : '';
            final pri = t.priority == 2 ? ' 🔴' : t.priority == 1 ? ' 🟡' : '';
            sb.writeln('  - ${t.title}$due$pri');
          }
        }
        if (done.isNotEmpty) {
          sb.writeln('✅ 已完成：');
          for (final t in done) {
            sb.writeln('  - ${t.title}');
          }
        }
        return sb.toString().trim();

      // 复习卡片
      case 'create_review_card':
        final title = args['title'] as String? ?? '';
        final content = args['content'] as String? ?? '';
        if (title.isEmpty || content.isEmpty) return '错误：标题或内容为空';
        final subjectId = args['subject_id'] as String?;
        await _ref.read(reviewCardsProvider.notifier).add(
          title: title,
          content: content,
          subjectId: subjectId,
          source: 'chat',
          createTodo: false,
        );
        return '已创建复习卡片「$title」';

      default:
        return '未知工具: $name';
    }
    } catch (e) {
      return '工具执行出错: $e';
    }
  }

  void _updateMessage(String id, String content, {required bool isStreaming}) {
    state = [
      for (final msg in state)
        if (msg.id == id)
          msg.copyWith(content: content, isStreaming: isStreaming)
        else
          msg,
    ];
  }

  String _getMsgContent(String id) {
    for (final msg in state) {
      if (msg.id == id) return msg.content;
    }
    return '';
  }

  void _appendSystemMsg(String content) {
    state = [
      ...state,
      Message(
        id: _uuid.v4(),
        role: MessageRole.system,
        content: content,
        createdAt: DateTime.now(),
      ),
    ];
  }

  Future<String?> pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null) return null;

    final bytes = await File(image.path).readAsBytes();
    return base64Encode(bytes);
  }

  Future<List<String>> pickMultipleImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    final result = <String>[];
    for (final image in images) {
      final bytes = await File(image.path).readAsBytes();
      result.add(base64Encode(bytes));
    }
    return result;
  }

  void clearChat() {
    state = [];
    _ref.read(databaseServiceProvider).clearChatMessages();
  }

  // 语音录制
  Future<void> checkMicPermission() async {
    await _voiceService.hasPermission();
  }

  Future<bool> startVoiceRecording() async {
    final hasPermission = await _voiceService.hasPermission();
    if (!hasPermission) return false;
    await _voiceService.startRecording();
    return true;
  }

  Future<void> cancelVoiceRecording() async {
    await _voiceService.cancelRecording();
  }

  Future<void> stopVoiceRecordingAndSend() async {
    final path = await _voiceService.stopRecording();
    if (path == null) return;

    // 先添加一条"正在识别语音..."的系统消息
    final loadingMsg = Message(
      id: _uuid.v4(),
      role: MessageRole.system,
      content: '正在识别语音...',
      createdAt: DateTime.now(),
    );
    state = [...state, loadingMsg];

    try {
      final config = _ref.read(apiConfigProvider);
      final text = await _voiceService.transcribe(
        config: config,
        audioPath: path,
      );

      // 移除加载消息
      state = state.where((m) => m.id != loadingMsg.id).toList();

      if (text.isNotEmpty) {
        // 用识别出的文字发送消息
        sendMessage(text);
      } else {
        state = [
          ...state,
          Message(
            id: _uuid.v4(),
            role: MessageRole.system,
            content: '语音识别结果为空',
            createdAt: DateTime.now(),
          ),
        ];
      }
    } on VoiceException catch (e) {
      state = state.where((m) => m.id != loadingMsg.id).toList();
      String hint = '';
      if (e.type == VoiceErrorType.networkError) {
        hint = '\n请检查网络连接后重试';
      } else if (e.type == VoiceErrorType.authError) {
        hint = '\n请在设置中检查 API Key';
      } else if (e.type == VoiceErrorType.audioTooShort) {
        hint = '\n请长按说话更久一些';
      }
      state = [
        ...state,
        Message(
          id: _uuid.v4(),
          role: MessageRole.system,
          content: '${e.message}$hint',
          createdAt: DateTime.now(),
        ),
      ];
    } catch (e) {
      state = state.where((m) => m.id != loadingMsg.id).toList();
      state = [
        ...state,
        Message(
          id: _uuid.v4(),
          role: MessageRole.system,
          content: '语音识别失败: $e',
          createdAt: DateTime.now(),
        ),
      ];
    }
  }

  Future<bool> isRecording() => _voiceService.isRecording();

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }
}

// 语音录制状态
final isRecordingProvider = StateProvider<bool>((ref) => false);

// 当前底部导航索引
final currentTabProvider = StateProvider<int>((ref) => 0);

// Theme Mode
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, String>((ref) {
  return ThemeModeNotifier(ref.read(storageServiceProvider));
});

class ThemeModeNotifier extends StateNotifier<String> {
  final StorageService _storage;

  ThemeModeNotifier(this._storage) : super('system') {
    state = _storage.loadThemeMode();
  }

  Future<void> setMode(String mode) async {
    state = mode;
    await _storage.saveThemeMode(mode);
  }
}

// Database Service
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

// Memory Service (RAG)
final memoryServiceProvider = Provider<MemoryService>((ref) {
  final dbService = ref.read(databaseServiceProvider);
  return MemoryService(dbService);
});

// 科目管理
final subjectsProvider =
    StateNotifierProvider<SubjectsNotifier, List<Subject>>((ref) {
  return SubjectsNotifier(ref.read(databaseServiceProvider));
});

class SubjectsNotifier extends StateNotifier<List<Subject>> {
  final DatabaseService _db;

  SubjectsNotifier(this._db) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _db.getSubjects();
  }

  Future<void> add(String name, {String? icon, String? color}) async {
    final subject = Subject(
      id: const Uuid().v4(),
      name: name,
      icon: icon,
      color: color,
      sortOrder: state.length,
      createdAt: DateTime.now(),
    );
    await _db.insertSubject(subject);
    state = [...state, subject];
  }

  Future<void> update(Subject subject) async {
    await _db.updateSubject(subject);
    state = [for (final s in state) if (s.id == subject.id) subject else s];
  }

  Future<void> delete(String id) async {
    await _db.deleteSubject(id);
    state = state.where((s) => s.id != id).toList();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final items = List<Subject>.from(state);
    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    for (int i = 0; i < items.length; i++) {
      final updated = items[i].copyWith(sortOrder: i);
      await _db.updateSubject(updated);
      items[i] = updated;
    }
    state = items;
  }
}

// 文档管理（按科目）
final documentsProvider = StateNotifierProvider.family<
    DocumentsNotifier, List<AppDocument>, String>((ref, subjectId) {
  return DocumentsNotifier(ref.read(databaseServiceProvider), subjectId);
});

class DocumentsNotifier extends StateNotifier<List<AppDocument>> {
  final DatabaseService _db;
  final String subjectId;

  DocumentsNotifier(this._db, this.subjectId) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _db.getDocuments(subjectId);
  }

  Future<void> add(AppDocument doc) async {
    await _db.insertDocument(doc);
    state = [doc, ...state];
  }

  Future<void> update(AppDocument doc) async {
    await _db.updateDocument(doc);
    state = [for (final d in state) if (d.id == doc.id) doc else d];
  }

  Future<void> delete(String id) async {
    await _db.deleteDocument(id);
    state = state.where((d) => d.id != id).toList();
  }

  Future<void> refresh() async {
    state = await _db.getDocuments(subjectId);
  }
}

// 科目文档数量
final subjectDocCountProvider = FutureProvider.family<int, String>((ref, subjectId) async {
  return ref.read(databaseServiceProvider).getDocumentCount(subjectId);
});

// 待办管理
final todosProvider =
    StateNotifierProvider<TodosNotifier, List<Todo>>((ref) {
  return TodosNotifier(ref.read(databaseServiceProvider));
});

class TodosNotifier extends StateNotifier<List<Todo>> {
  final DatabaseService _db;

  TodosNotifier(this._db) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _db.getTodos();
  }

  Future<void> add(Todo todo) async {
    await _db.insertTodo(todo);
    state = [todo, ...state];

    // 安排待办提醒（提前 1 小时）
    if (todo.dueDate != null) {
      NotificationService().scheduleTodoReminder(
        todo.dueDate!.subtract(const Duration(hours: 1)),
        todo.title,
      );
    }
  }

  Future<void> update(Todo todo) async {
    await _db.updateTodo(todo);
    state = [for (final t in state) if (t.id == todo.id) todo else t];
  }

  Future<void> toggleDone(String id) async {
    final todo = state.firstWhere((t) => t.id == id);
    final updated = todo.copyWith(
      isDone: !todo.isDone,
      completedAt: !todo.isDone ? DateTime.now() : null,
    );
    await _db.updateTodo(updated);
    state = [for (final t in state) if (t.id == id) updated else t];
  }

  Future<void> delete(String id) async {
    await _db.deleteTodo(id);
    state = state.where((t) => t.id != id).toList();
  }

  Future<void> refresh() async {
    state = await _db.getTodos();
  }
}

// 复习服务
final reviewServiceProvider = Provider<ReviewService>((ref) {
  return ReviewService(ref.read(databaseServiceProvider));
});

// 复习卡片管理
final reviewCardsProvider =
    StateNotifierProvider<ReviewCardsNotifier, List<ReviewCard>>((ref) {
  return ReviewCardsNotifier(ref.read(reviewServiceProvider), ref);
});

class ReviewCardsNotifier extends StateNotifier<List<ReviewCard>> {
  final ReviewService _service;
  final Ref _ref;

  ReviewCardsNotifier(this._service, this._ref) : super([]) {
    _load();
  }

  Future<void> _load() async {
    state = await _service.getAllCards();
  }

  Future<ReviewCard> add({
    required String title,
    required String content,
    String? subjectId,
    String source = 'manual',
    bool createTodo = true,
  }) async {
    final card = await _service.createCard(
      title: title,
      content: content,
      subjectId: subjectId,
      source: source,
    );
    state = [card, ...state];

    // 安排复习提醒（提前 30 分钟）
    NotificationService().scheduleReviewReminder(
      card.nextReview.subtract(const Duration(minutes: 30)),
      title,
    );

    // 自动创建复习待办
    if (createTodo) {
      final todo = Todo(
        id: const Uuid().v4(),
        title: '复习: $title',
        description: content.length > 100 ? '${content.substring(0, 100)}...' : content,
        dueDate: card.nextReview,
        subjectId: subjectId,
        createdAt: DateTime.now(),
      );
      await _ref.read(todosProvider.notifier).add(todo);
    }

    return card;
  }

  Future<void> review(String cardId, int rating) async {
    final card = state.firstWhere((c) => c.id == cardId);
    final updated = _service.review(card, rating);
    await _service.updateCard(updated);
    state = [for (final c in state) if (c.id == cardId) updated else c];
  }

  Future<void> delete(String id) async {
    await _service.deleteCard(id);
    state = state.where((c) => c.id != id).toList();
  }

  Future<void> refresh() async {
    state = await _service.getAllCards();
  }

  List<ReviewCard> getDue() {
    return state.where((c) => !c.nextReview.isAfter(DateTime.now())).toList();
  }
}

// 今日待复习数量
final dueReviewCountProvider = Provider<int>((ref) {
  final cards = ref.watch(reviewCardsProvider);
  return cards.where((c) => !c.nextReview.isAfter(DateTime.now())).length;
});

// 知识卡片管理
final knowledgeCardsProvider = StateNotifierProvider.family<
    KnowledgeCardsNotifier, List<KnowledgeCard>, String>((ref, subjectId) {
  return KnowledgeCardsNotifier(ref.read(databaseServiceProvider), subjectId);
});

class KnowledgeCardsNotifier extends StateNotifier<List<KnowledgeCard>> {
  final DatabaseService _db;
  final String subjectId;

  KnowledgeCardsNotifier(this._db, this.subjectId) : super([]) {
    _load();
  }

  Future<void> _load() async {
    final maps = await _db.getKnowledgeCards(subjectId);
    state = maps.map((m) => KnowledgeCard(
      id: m['id'] as String,
      subjectId: m['subject_id'] as String,
      title: m['title'] as String,
      content: m['content'] as String,
      tags: m['tags'] != null ? List<String>.from(jsonDecode(m['tags'] as String)) : [],
      source: m['source'] as String? ?? 'manual',
      createdAt: DateTime.parse(m['created_at'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    )).toList();
  }

  Future<void> add({
    required String title,
    required String content,
    List<String> tags = const [],
    String source = 'manual',
  }) async {
    final id = const Uuid().v4();
    await _db.insertKnowledgeCard(
      id: id,
      subjectId: subjectId,
      title: title,
      content: content,
      tags: tags,
      source: source,
    );
    await _load();
  }

  Future<void> update({
    required String id,
    required String title,
    required String content,
    List<String> tags = const [],
  }) async {
    await _db.updateKnowledgeCard(
      id: id,
      title: title,
      content: content,
      tags: tags,
    );
    await _load();
  }

  Future<void> delete(String id) async {
    await _db.deleteKnowledgeCard(id);
    state = state.where((c) => c.id != id).toList();
  }

  Future<void> refresh() async {
    await _load();
  }
}

// 导出服务
final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService(ref.read(databaseServiceProvider));
});

// TTS 语音服务
final ttsServiceProvider = Provider<TTSService>((ref) {
  return TTSService();
});

// TTS 设置
class TtsSettings {
  final bool enabled;
  final double speed;   // 0.0 - 1.0
  final String voice;

  const TtsSettings({
    this.enabled = true,
    this.speed = 0.5,
    this.voice = '冰糖',
  });

  TtsSettings copyWith({bool? enabled, double? speed, String? voice}) {
    return TtsSettings(
      enabled: enabled ?? this.enabled,
      speed: speed ?? this.speed,
      voice: voice ?? this.voice,
    );
  }
}

final ttsSettingsProvider = StateNotifierProvider<TtsSettingsNotifier, TtsSettings>((ref) {
  return TtsSettingsNotifier(ref.read(storageServiceProvider));
});

class TtsSettingsNotifier extends StateNotifier<TtsSettings> {
  final StorageService _storage;

  TtsSettingsNotifier(this._storage) : super(const TtsSettings()) {
    _load();
  }

  void _load() {
    final map = _storage.loadTtsSettingsMap();
    if (map.isNotEmpty) {
      state = TtsSettings(
        enabled: map['enabled'] as bool? ?? true,
        speed: (map['speed'] as num?)?.toDouble() ?? 0.5,
        voice: map['voice'] as String? ?? '冰糖',
      );
    }
  }

  Future<void> update(TtsSettings settings) async {
    state = settings;
    await _storage.saveTtsSettings({
      'enabled': settings.enabled,
      'speed': settings.speed,
      'voice': settings.voice,
    });
  }
}

// 网络状态
final connectivityProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map((results) {
    return results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
  });
});

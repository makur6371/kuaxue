import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/document.dart';
import '../models/message.dart';
import '../models/review_card.dart';
import '../models/subject.dart';
import '../models/todo.dart';

class DatabaseService {
  static Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'kuaxue.db');
    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createDocumentsTable(db);
        }
        if (oldVersion < 3) {
          await _createTodosTable(db);
        }
        if (oldVersion < 4) {
          await _createReviewCardsTable(db);
        }
        if (oldVersion < 5) {
          await _createChatMessagesTable(db);
          await _createKnowledgeCardsTable(db);
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE subjects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT,
        color TEXT,
        sort_order INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await _createDocumentsTable(db);
    await _createTodosTable(db);
    await _createReviewCardsTable(db);
    await _createChatMessagesTable(db);
    await _createKnowledgeCardsTable(db);
  }

  Future<void> _createDocumentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        subject_id TEXT NOT NULL,
        file_path TEXT NOT NULL,
        thumbnail_path TEXT,
        file_size INTEGER DEFAULT 0,
        description TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_documents_subject ON documents(subject_id)',
    );
  }

  Future<void> _createTodosTable(Database db) async {
    await db.execute('''
      CREATE TABLE todos (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        due_date TEXT,
        is_done INTEGER DEFAULT 0,
        priority INTEGER DEFAULT 0,
        subject_id TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_todos_due ON todos(due_date)');
    await db.execute('CREATE INDEX idx_todos_done ON todos(is_done)');
  }

  Future<void> _createReviewCardsTable(Database db) async {
    await db.execute('''
      CREATE TABLE review_cards (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        subject_id TEXT,
        source TEXT DEFAULT 'manual',
        ease_factor REAL DEFAULT 2.5,
        interval INTEGER DEFAULT 0,
        repetitions INTEGER DEFAULT 0,
        next_review TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_reviewed_at TEXT,
        FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_review_next ON review_cards(next_review)');
    await db.execute('CREATE INDEX idx_review_subject ON review_cards(subject_id)');
  }

  Future<void> _createChatMessagesTable(Database db) async {
    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        content_type TEXT DEFAULT 'markdown',
        image_paths TEXT,
        tool_name TEXT,
        tool_result TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_chat_created ON chat_messages(created_at)');
  }

  Future<void> _createKnowledgeCardsTable(Database db) async {
    await db.execute('''
      CREATE TABLE knowledge_cards (
        id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        tags TEXT,
        source TEXT DEFAULT 'manual',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (subject_id) REFERENCES subjects(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_knowledge_subject ON knowledge_cards(subject_id)');
  }

  // 科目 CRUD
  Future<List<Subject>> getSubjects() async {
    final db = await database;
    final maps = await db.query('subjects', orderBy: 'sort_order ASC, created_at DESC');
    return maps.map((m) => Subject(
      id: m['id'] as String,
      name: m['name'] as String,
      icon: m['icon'] as String?,
      color: m['color'] as String?,
      sortOrder: m['sort_order'] as int,
      createdAt: DateTime.parse(m['created_at'] as String),
    )).toList();
  }

  Future<void> insertSubject(Subject subject) async {
    final db = await database;
    await db.insert('subjects', {
      'id': subject.id,
      'name': subject.name,
      'icon': subject.icon,
      'color': subject.color,
      'sort_order': subject.sortOrder,
      'created_at': subject.createdAt.toIso8601String(),
    });
  }

  Future<void> updateSubject(Subject subject) async {
    final db = await database;
    await db.update(
      'subjects',
      {
        'name': subject.name,
        'icon': subject.icon,
        'color': subject.color,
        'sort_order': subject.sortOrder,
      },
      where: 'id = ?',
      whereArgs: [subject.id],
    );
  }

  Future<void> deleteSubject(String id) async {
    final db = await database;
    // documents 有 ON DELETE CASCADE，无需手动删除
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }

  // 文档 CRUD
  Future<List<AppDocument>> getDocuments(String subjectId) async {
    final db = await database;
    final maps = await db.query(
      'documents',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => AppDocument(
      id: m['id'] as String,
      name: m['name'] as String,
      type: m['type'] as String,
      subjectId: m['subject_id'] as String,
      filePath: m['file_path'] as String,
      thumbnailPath: m['thumbnail_path'] as String?,
      fileSize: m['file_size'] as int? ?? 0,
      description: m['description'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
    )).toList();
  }

  Future<int> getDocumentCount(String subjectId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM documents WHERE subject_id = ?',
      [subjectId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> insertDocument(AppDocument doc) async {
    final db = await database;
    await db.insert('documents', {
      'id': doc.id,
      'name': doc.name,
      'type': doc.type,
      'subject_id': doc.subjectId,
      'file_path': doc.filePath,
      'thumbnail_path': doc.thumbnailPath,
      'file_size': doc.fileSize,
      'description': doc.description,
      'created_at': doc.createdAt.toIso8601String(),
    });
  }

  Future<void> updateDocument(AppDocument doc) async {
    final db = await database;
    await db.update(
      'documents',
      {
        'name': doc.name,
        'description': doc.description,
      },
      where: 'id = ?',
      whereArgs: [doc.id],
    );
  }

  Future<void> deleteDocument(String id) async {
    final db = await database;
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  // 待办 CRUD
  Future<List<Todo>> getTodos() async {
    final db = await database;
    final maps = await db.query('todos', orderBy: 'is_done ASC, priority DESC, due_date ASC, created_at DESC');
    return maps.map(_todoFromMap).toList();
  }

  Future<List<Todo>> getTodosBySubject(String subjectId) async {
    final db = await database;
    final maps = await db.query(
      'todos',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'is_done ASC, due_date ASC',
    );
    return maps.map(_todoFromMap).toList();
  }

  Future<void> insertTodo(Todo todo) async {
    final db = await database;
    await db.insert('todos', _todoToMap(todo));
  }

  Future<void> updateTodo(Todo todo) async {
    final db = await database;
    await db.update(
      'todos',
      _todoToMap(todo),
      where: 'id = ?',
      whereArgs: [todo.id],
    );
  }

  Future<void> deleteTodo(String id) async {
    final db = await database;
    await db.delete('todos', where: 'id = ?', whereArgs: [id]);
  }

  Map<String, dynamic> _todoToMap(Todo todo) => {
    'id': todo.id,
    'title': todo.title,
    'description': todo.description,
    'due_date': todo.dueDate?.toIso8601String(),
    'is_done': todo.isDone ? 1 : 0,
    'priority': todo.priority,
    'subject_id': todo.subjectId,
    'created_at': todo.createdAt.toIso8601String(),
    'completed_at': todo.completedAt?.toIso8601String(),
  };

  Todo _todoFromMap(Map<String, dynamic> m) => Todo(
    id: m['id'] as String,
    title: m['title'] as String,
    description: m['description'] as String?,
    dueDate: m['due_date'] != null ? DateTime.tryParse(m['due_date'] as String) : null,
    isDone: (m['is_done'] as int) == 1,
    priority: m['priority'] as int? ?? 0,
    subjectId: m['subject_id'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
    completedAt: m['completed_at'] != null ? DateTime.tryParse(m['completed_at'] as String) : null,
  );

  // 复习卡片 CRUD
  Future<List<ReviewCard>> getReviewCards() async {
    final db = await database;
    final maps = await db.query('review_cards', orderBy: 'next_review ASC');
    return maps.map(_reviewCardFromMap).toList();
  }

  Future<List<ReviewCard>> getDueReviewCards({String? subjectId}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    String? where;
    List<dynamic>? whereArgs;
    if (subjectId != null) {
      where = 'next_review <= ? AND subject_id = ?';
      whereArgs = [now, subjectId];
    } else {
      where = 'next_review <= ?';
      whereArgs = [now];
    }
    final maps = await db.query(
      'review_cards',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'next_review ASC',
    );
    return maps.map(_reviewCardFromMap).toList();
  }

  Future<void> insertReviewCard(ReviewCard card) async {
    final db = await database;
    await db.insert('review_cards', _reviewCardToMap(card));
  }

  Future<void> updateReviewCard(ReviewCard card) async {
    final db = await database;
    await db.update(
      'review_cards',
      _reviewCardToMap(card),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  Future<void> deleteReviewCard(String id) async {
    final db = await database;
    await db.delete('review_cards', where: 'id = ?', whereArgs: [id]);
  }

  Map<String, dynamic> _reviewCardToMap(ReviewCard c) => {
    'id': c.id,
    'title': c.title,
    'content': c.content,
    'subject_id': c.subjectId,
    'source': c.source,
    'ease_factor': c.easeFactor,
    'interval': c.interval,
    'repetitions': c.repetitions,
    'next_review': c.nextReview.toIso8601String(),
    'created_at': c.createdAt.toIso8601String(),
    'last_reviewed_at': c.lastReviewedAt?.toIso8601String(),
  };

  ReviewCard _reviewCardFromMap(Map<String, dynamic> m) => ReviewCard(
    id: m['id'] as String,
    title: m['title'] as String,
    content: m['content'] as String,
    subjectId: m['subject_id'] as String?,
    source: m['source'] as String? ?? 'manual',
    easeFactor: (m['ease_factor'] as num?)?.toDouble() ?? 2.5,
    interval: m['interval'] as int? ?? 0,
    repetitions: m['repetitions'] as int? ?? 0,
    nextReview: DateTime.parse(m['next_review'] as String),
    createdAt: DateTime.parse(m['created_at'] as String),
    lastReviewedAt: m['last_reviewed_at'] != null ? DateTime.tryParse(m['last_reviewed_at'] as String) : null,
  );

  // 聊天消息 CRUD
  Future<List<Message>> getChatMessages({int? limit, int? offset}) async {
    final db = await database;
    final maps = await db.query(
      'chat_messages',
      orderBy: 'created_at ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map(_messageFromMap).toList();
  }

  Future<int> getChatMessageCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as c FROM chat_messages');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> insertChatMessage(Message msg) async {
    final db = await database;
    await db.insert('chat_messages', _messageToMap(msg));
  }

  Future<void> clearChatMessages() async {
    final db = await database;
    await db.delete('chat_messages');
  }

  Map<String, dynamic> _messageToMap(Message m) => {
    'id': m.id,
    'role': m.role.name,
    'content': m.content,
    'content_type': m.contentType.name,
    'image_paths': m.imagePaths != null ? jsonEncode(m.imagePaths) : null,
    'tool_name': m.toolName,
    'tool_result': m.toolResult != null ? jsonEncode(m.toolResult) : null,
    'created_at': m.createdAt.toIso8601String(),
  };

  Message _messageFromMap(Map<String, dynamic> m) => Message(
    id: m['id'] as String,
    role: MessageRole.values.byName(m['role'] as String),
    content: m['content'] as String,
    contentType: ContentType.values.byName(m['content_type'] as String? ?? 'markdown'),
    imagePaths: m['image_paths'] != null
        ? List<String>.from(jsonDecode(m['image_paths'] as String))
        : null,
    toolName: m['tool_name'] as String?,
    toolResult: m['tool_result'] != null
        ? Map<String, dynamic>.from(jsonDecode(m['tool_result'] as String))
        : null,
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  // 知识卡片 CRUD
  Future<List<Map<String, dynamic>>> getKnowledgeCards(String subjectId) async {
    final db = await database;
    return db.query(
      'knowledge_cards',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> insertKnowledgeCard({
    required String id,
    required String subjectId,
    required String title,
    required String content,
    List<String>? tags,
    String source = 'manual',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('knowledge_cards', {
      'id': id,
      'subject_id': subjectId,
      'title': title,
      'content': content,
      'tags': tags != null ? jsonEncode(tags) : null,
      'source': source,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateKnowledgeCard({
    required String id,
    required String title,
    required String content,
    List<String>? tags,
  }) async {
    final db = await database;
    await db.update(
      'knowledge_cards',
      {
        'title': title,
        'content': content,
        'tags': tags != null ? jsonEncode(tags) : null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteKnowledgeCard(String id) async {
    final db = await database;
    await db.delete('knowledge_cards', where: 'id = ?', whereArgs: [id]);
  }

  // 搜索（转义 LIKE 通配符）
  String _escapeLike(String s) => s.replaceAll('%', '\\%').replaceAll('_', '\\_');

  Future<List<Message>> searchChatMessages(String query) async {
    final db = await database;
    final escaped = _escapeLike(query);
    final maps = await db.query(
      'chat_messages',
      where: 'content LIKE ? ESCAPE \'\\\' ',
      whereArgs: ['%$escaped%'],
      orderBy: 'created_at DESC',
      limit: 50,
    );
    return maps.map(_messageFromMap).toList();
  }

  Future<List<Map<String, dynamic>>> searchKnowledgeCards(String query) async {
    final db = await database;
    final escaped = _escapeLike(query);
    return db.query(
      'knowledge_cards',
      where: 'title LIKE ? ESCAPE \'\\\' OR content LIKE ? ESCAPE \'\\\' OR tags LIKE ? ESCAPE \'\\\' ',
      whereArgs: ['%$escaped%', '%$escaped%', '%$escaped%'],
      orderBy: 'updated_at DESC',
      limit: 50,
    );
  }

  Future<List<AppDocument>> searchDocuments(String query) async {
    final db = await database;
    final maps = await db.query(
      'documents',
      where: 'name LIKE ? OR description LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'created_at DESC',
      limit: 50,
    );
    return maps.map((m) => AppDocument(
      id: m['id'] as String,
      name: m['name'] as String,
      type: m['type'] as String,
      subjectId: m['subject_id'] as String,
      filePath: m['file_path'] as String,
      thumbnailPath: m['thumbnail_path'] as String?,
      fileSize: m['file_size'] as int? ?? 0,
      description: m['description'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
    )).toList();
  }
}

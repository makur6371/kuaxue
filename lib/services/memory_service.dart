import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/api_config.dart';
import '../models/memory.dart';
import '../services/database_service.dart';
import '../services/embedding_service.dart';

class MemoryService {
  final DatabaseService _dbService;
  late final EmbeddingService _embeddingService;
  final _uuid = const Uuid();
  bool _initialized = false;
  Future<void>? _initFuture;

  MemoryService(this._dbService) {
    _embeddingService = EmbeddingService(dbService: _dbService);
  }

  /// 初始化 memory 表（幂等，自动确保只执行一次）
  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initFuture ??= _doInit();
    await _initFuture;
    _initialized = true;
  }

  Future<void> _doInit() async {
    final db = await _dbService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        subject_id TEXT,
        metadata TEXT,
        embedding TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memories_subject ON memories(subject_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memories_created ON memories(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memories_subject_created ON memories(subject_id, created_at)',
    );
  }

  /// 存入记忆
  Future<void> store({
    required ApiConfig config,
    required String type,
    required String content,
    String? subjectId,
    Map<String, dynamic>? metadata,
  }) async {
    await _ensureInit();
    final embedding = await _embeddingService.embed(
      config: config,
      text: content,
    );

    final db = await _dbService.database;
    await db.insert('memories', {
      'id': _uuid.v4(),
      'type': type,
      'content': content,
      'subject_id': subjectId,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'embedding': jsonEncode(embedding),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 存入记忆（使用已生成的 embedding，避免重复调用 API）
  Future<void> storeRaw({
    required String type,
    required String content,
    String? subjectId,
    required List<double> embedding,
    Map<String, dynamic>? metadata,
  }) async {
    await _ensureInit();
    final db = await _dbService.database;
    await db.insert('memories', {
      'id': _uuid.v4(),
      'type': type,
      'content': content,
      'subject_id': subjectId,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
      'embedding': jsonEncode(embedding),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// 检索相关记忆（混合检索：向量相似度 + 关键词匹配 + 重排序）
  Future<List<Memory>> retrieve({
    required ApiConfig config,
    required String query,
    int topK = 5,
    String? filterType,
    String? filterSubjectId,
    double minScore = 0.2,
  }) async {
    await _ensureInit();
    final queryEmbedding = await _embeddingService.embed(
      config: config,
      text: query,
    );

    final db = await _dbService.database;
    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (filterType != null) {
      whereClause += ' AND type = ?';
      whereArgs.add(filterType);
    }
    if (filterSubjectId != null) {
      whereClause += ' AND subject_id = ?';
      whereArgs.add(filterSubjectId);
    }

    // 1. 向量相似度检索
    final rows = await db.query(
      'memories',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
      limit: 200,
    );

    final vectorScored = <String, _ScoredMemory>{};
    for (final row in rows) {
      final embedding = List<double>.from(
        jsonDecode(row['embedding'] as String) as List,
      );
      final score = _cosineSimilarity(queryEmbedding, embedding);
      if (score >= minScore) {
        final mem = Memory(
          id: row['id'] as String,
          type: row['type'] as String,
          content: row['content'] as String,
          subjectId: row['subject_id'] as String?,
          metadata: row['metadata'] as String?,
          embedding: embedding,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
        vectorScored[mem.id] = _ScoredMemory(memory: mem, score: score);
      }
    }

    // 2. 关键词检索（合并为单次 OR 查询，避免逐词查询爆炸）
    final keywords = _tokenize(query);
    final keywordScored = <String, double>{};
    if (keywords.isNotEmpty) {
      // 限制查询词数，避免 SQL 过长
      final queryKw = keywords.length > 8 ? keywords.sublist(0, 8) : keywords;
      final likeConditions = List.filled(queryKw.length, 'content LIKE ?').join(' OR ');
      final likeArgs = queryKw.map((kw) => '%$kw%').toList();

      final kwRows = await db.query(
        'memories',
        columns: ['id', 'content'],
        where: '$whereClause AND ($likeConditions)',
        whereArgs: [...whereArgs, ...likeArgs],
        limit: 100,
      );
      for (final row in kwRows) {
        final id = row['id'] as String;
        final content = row['content'] as String;
        double score = 0;
        for (final kw in queryKw) {
          final matches = kw.allMatches(content).length;
          score += matches / (content.length / 100).clamp(1, double.infinity);
        }
        keywordScored[id] = score;
      }
      // 归一化关键词分数到 [0, 1]
      if (keywordScored.isNotEmpty) {
        final maxKw = keywordScored.values.reduce((a, b) => a > b ? a : b);
        if (maxKw > 0) {
          keywordScored.updateAll((_, v) => v / maxKw);
        }
      }
    }

    // 3. 融合重排序：0.7 * 向量分 + 0.3 * 关键词分
    final allIds = <String>{
      ...vectorScored.keys,
      ...keywordScored.keys,
    };

    final merged = <_ScoredMemory>[];
    for (final id in allIds) {
      final vecScore = vectorScored[id]?.score ?? 0.0;
      final kwScore = keywordScored[id] ?? 0.0;
      // 无向量结果的纯关键词命中，阈值放低
      if (vecScore < minScore && kwScore < 0.1) continue;
      final combined = 0.7 * vecScore + 0.3 * kwScore;
      final mem = vectorScored[id]?.memory;
      if (mem != null) {
        merged.add(_ScoredMemory(memory: mem, score: combined));
      }
    }

    merged.sort((a, b) => b.score.compareTo(a.score));
    return merged.take(topK).map((s) => s.memory).toList();
  }

  /// 简单中文分词：按标点/空格切分，保留 ≥2 字的词
  List<String> _tokenize(String text) {
    final tokens = text
        .replaceAll(RegExp(r'[，。？！、；：""''（）\[\]【】\s\.,?!;:\(\)\[\]]+'), ' ')
        .split(' ')
        .where((t) => t.length >= 2)
        .toList();
    // 对中文额外做 2-gram 切分（提高召回）
    final ngrams = <String>[];
    for (final token in tokens) {
      if (_containsCJK(token) && token.length > 2) {
        for (int i = 0; i < token.length - 1; i++) {
          ngrams.add(token.substring(i, i + 2));
        }
      }
    }
    return [...tokens, ...ngrams].toSet().toList();
  }

  bool _containsCJK(String s) {
    return s.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);
  }

  /// 获取记忆总数
  Future<int> count({String? type}) async {
    await _ensureInit();
    final db = await _dbService.database;
    final result = await db.rawQuery(
      type != null
          ? 'SELECT COUNT(*) as c FROM memories WHERE type = ?'
          : 'SELECT COUNT(*) as c FROM memories',
      type != null ? [type] : [],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 清除旧记忆（保留最近 N 条）
  Future<void> prune({int keepRecent = 500}) async {
    await _ensureInit();
    final db = await _dbService.database;
    await db.rawDelete('''
      DELETE FROM memories WHERE id NOT IN (
        SELECT id FROM memories ORDER BY created_at DESC LIMIT ?
      )
    ''', [keepRecent]);
  }

  /// 删除指定科目的记忆
  Future<void> deleteBySubject(String subjectId) async {
    final db = await _dbService.database;
    await db.delete('memories', where: 'subject_id = ?', whereArgs: [subjectId]);
  }

  /// 查询指定文档的已索引片段数（用于显示索引状态）
  Future<int> countByDocId(String docId) async {
    await _ensureInit();
    final db = await _dbService.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as c FROM memories WHERE type = 'document_chunk' AND metadata LIKE ?",
      ['%"docId":"$docId"%'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 删除指定文档的所有记忆片段
  Future<void> deleteByDocId(String docId) async {
    await _ensureInit();
    final db = await _dbService.database;
    await db.delete(
      'memories',
      where: "type = 'document_chunk' AND metadata LIKE ?",
      whereArgs: ['%"docId":"$docId"%'],
    );
  }

  /// 删除指定文档中不含指定版本的记忆片段（用于原子化 reprocess）
  Future<void> deleteByDocIdExceptVersion(String docId, int version) async {
    await _ensureInit();
    final db = await _dbService.database;
    // 删除该文档的旧版本（不含当前 version 的）
    await db.rawDelete(
      "DELETE FROM memories WHERE type = 'document_chunk' AND metadata LIKE ? AND metadata NOT LIKE ?",
      ['%"docId":"$docId"%', '%"version":$version%'],
    );
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}

class _ScoredMemory {
  final Memory memory;
  final double score;
  _ScoredMemory({required this.memory, required this.score});
}

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../models/api_config.dart';
import 'database_service.dart';
import 'retry_interceptor.dart';

class EmbeddingService {
  final DatabaseService? _dbService;
  final Dio _dio = Dio();
  bool _initialized = false;
  Future<void>? _initFuture;

  EmbeddingService({DatabaseService? dbService}) : _dbService = dbService {
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initFuture ??= _doInit();
    await _initFuture;
    _initialized = true;
  }

  Future<void> _doInit() async {
    if (_dbService == null) return;
    final db = await _dbService!.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS embedding_cache (
        content_hash TEXT PRIMARY KEY,
        embedding TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  String _hash(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }

  Future<List<double>?> _getCache(String hash) async {
    if (_dbService == null) return null;
    await _ensureInit();
    final db = await _dbService!.database;
    final rows = await db.query(
      'embedding_cache',
      columns: ['embedding'],
      where: 'content_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return List<double>.from(jsonDecode(rows.first['embedding'] as String) as List);
  }

  Future<void> _setCache(String hash, List<double> embedding) async {
    if (_dbService == null) return;
    await _ensureInit();
    final db = await _dbService!.database;
    await db.insert(
      'embedding_cache',
      {
        'content_hash': hash,
        'embedding': jsonEncode(embedding),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取文本的 embedding 向量（自动缓存）
  Future<List<double>> embed({
    required ApiConfig config,
    required String text,
    String model = 'BAAI/bge-m3',
  }) async {
    final hash = _hash(text);
    final cached = await _getCache(hash);
    if (cached != null) return cached;

    final response = await _dio.post(
      '${config.baseUrl}/embeddings',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'model': model,
        'input': text,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final embeddings = data['data'] as List;
    final result = List<double>.from(embeddings[0]['embedding'] as List);
    await _setCache(hash, result);
    return result;
  }

  /// 批量获取 embedding（自动缓存，仅对未命中的文本调用 API）
  Future<List<List<double>>> embedBatch({
    required ApiConfig config,
    required List<String> texts,
    String model = 'BAAI/bge-m3',
  }) async {
    final hashes = texts.map(_hash).toList();
    final results = List<List<double>?>.filled(texts.length, null);
    final uncachedIndices = <int>[];
    final uncachedTexts = <String>[];

    // 1. 查缓存
    for (int i = 0; i < texts.length; i++) {
      final cached = await _getCache(hashes[i]);
      if (cached != null) {
        results![i] = cached;
      } else {
        uncachedIndices.add(i);
        uncachedTexts.add(texts[i]);
      }
    }

    // 2. 未命中的调 API
    if (uncachedTexts.isNotEmpty) {
      final response = await _dio.post(
        '${config.baseUrl}/embeddings',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'input': uncachedTexts,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final embeddingsList = data['data'] as List;
      embeddingsList.sort((a, b) => (a['index'] as int).compareTo(b['index'] as int));

      for (int j = 0; j < uncachedIndices.length; j++) {
        final embedding = List<double>.from(embeddingsList[j]['embedding'] as List);
        results![uncachedIndices[j]] = embedding;
        await _setCache(hashes[uncachedIndices[j]], embedding);
      }
    }

    return results!.map((e) => e!).toList();
  }

  /// 余弦相似度
  static double cosineSimilarity(List<double> a, List<double> b) {
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

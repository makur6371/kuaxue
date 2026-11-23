import 'dart:io';
import 'dart:math';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:docx_to_text/docx_to_text.dart';
import '../models/api_config.dart';
import '../models/document.dart';
import 'database_service.dart';
import 'embedding_service.dart';
import 'memory_service.dart';

class DocumentProcessor {
  late final EmbeddingService _embeddingService;

  DocumentProcessor({DatabaseService? dbService})
      : _embeddingService = EmbeddingService(dbService: dbService);

  /// 从文件提取纯文本
  Future<String> extractText(String filePath, String type) async {
    switch (type) {
      case 'txt':
        return File(filePath).readAsString();
      case 'pdf':
        return _extractPdf(filePath);
      case 'doc':
      case 'docx':
        return _extractDocx(filePath);
      default:
        return '';
    }
  }

  String _extractPdf(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    final document = sf.PdfDocument(inputBytes: bytes);
    final text = sf.PdfTextExtractor(document).extractText();
    document.dispose();
    return text;
  }

  String _extractDocx(String filePath) {
    final bytes = File(filePath).readAsBytesSync();
    return docxToText(bytes);
  }

  /// 递归文本分块：按段落→句子→换行→空格→字符逐级切分
  /// 优先保持自然边界，类似 langchain_dart 的 RecursiveTextSplitter
  List<String> chunkText(String text, {int chunkSize = 500, int overlap = 80}) {
    if (text.trim().isEmpty) return [];
    if (text.length <= chunkSize) return [text.trim()];

    // 分隔符优先级：双换行(段落) → 句号/问号/感叹号 → 换行 → 分号/逗号 → 空格 → 硬切
    final separators = [
      '\n\n',
      '。',
      '？',
      '！',
      '.',
      '?',
      '!',
      '\n',
      '；',
      ';',
      '，',
      ',',
      ' ',
    ];

    return _recursiveSplit(text, separators, chunkSize, overlap);
  }

  List<String> _recursiveSplit(
    String text,
    List<String> separators,
    int chunkSize,
    int overlap,
  ) {
    if (text.length <= chunkSize) return [text.trim()];

    // 找到第一个能切分的分隔符
    String? activeSep;
    List<String>? splits;
    for (final sep in separators) {
      if (!text.contains(sep)) continue;
      final parts = text.split(sep);
      // 检查切分后是否有意义（不是每段都超长）
      final useful = parts.any((p) => p.length <= chunkSize);
      if (useful) {
        activeSep = sep;
        splits = parts;
        break;
      }
    }

    // 所有分隔符都无法有效切分 → 硬切
    if (splits == null || activeSep == null) {
      return _hardSplit(text, chunkSize, overlap);
    }

    // 合并小块，在合并阶段直接嵌入重叠
    final chunks = <String>[];
    final buffer = StringBuffer();
    String lastSaved = ''; // 记录上一个已保存 chunk 的内容，用于 overlap

    for (int i = 0; i < splits.length; i++) {
      final part = splits[i];
      final candidate = buffer.isEmpty
          ? part
          : '$buffer$activeSep$part';

      if (candidate.length <= chunkSize) {
        if (buffer.isNotEmpty) buffer.write(activeSep);
        buffer.write(part);
      } else {
        // 当前 buffer 已满，保存
        if (buffer.isNotEmpty) {
          final chunk = buffer.toString().trim();
          if (chunk.isNotEmpty) {
            chunks.add(chunk);
            lastSaved = buffer.toString();
          }
        }
        // 新块以 overlap 开头（上一个已保存 chunk 的尾部）
        buffer.clear();
        if (overlap > 0 && lastSaved.isNotEmpty) {
          final tailLen = lastSaved.length > overlap ? overlap : lastSaved.length;
          buffer.write(lastSaved.substring(lastSaved.length - tailLen));
        }

        if (part.length > chunkSize) {
          // 单个 part 超长 → 递归切分，把当前 tail 作为前缀拼入第一块
          final subSeparators = separators.sublist(separators.indexOf(activeSep) + 1);
          final subChunks = subSeparators.isNotEmpty
              ? _recursiveSplit(part, subSeparators, chunkSize, overlap)
              : _hardSplit(part, chunkSize, overlap);
          if (subChunks.isNotEmpty && buffer.isNotEmpty) {
            final prefix = buffer.toString();
            final mergedFirst = '$prefix$activeSep${subChunks[0]}';
            if (mergedFirst.length <= chunkSize) {
              subChunks[0] = mergedFirst;
            } else {
              final p = prefix.trim();
              if (p.isNotEmpty) chunks.add(p);
            }
          }
          chunks.addAll(subChunks);
          buffer.clear();
        } else {
          buffer.write(part);
        }
      }
    }
    if (buffer.isNotEmpty) {
      final chunk = buffer.toString().trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
    }

    // 安全截断：overlap 前缀可能导致个别 chunk 略超 chunkSize，截断到上限
    final hardLimit = chunkSize + overlap;
    for (int i = 0; i < chunks.length; i++) {
      if (chunks[i].length > hardLimit) {
        chunks[i] = chunks[i].substring(0, hardLimit);
      }
    }

    return chunks;
  }

  /// 硬切：按字符强制切分
  List<String> _hardSplit(String text, int chunkSize, int overlap) {
    final chunks = <String>[];
    int start = 0;
    while (start < text.length) {
      final end = min(start + chunkSize, text.length);
      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      if (end >= text.length) break;
      start += chunkSize - overlap;
    }
    return chunks;
  }

  /// 处理文档：提取→分块→向量化→存储
  /// [version] 可选版本标记，用于原子化 reprocess
  Future<int> processDocument({
    required ApiConfig config,
    required MemoryService memoryService,
    required AppDocument doc,
    void Function(double progress)? onProgress,
    int? version,
  }) async {
    // 1. 提取文本
    final text = await extractText(doc.filePath, doc.type);
    if (text.trim().isEmpty) return 0;

    // 2. 分块
    final chunks = chunkText(text);
    if (chunks.isEmpty) return 0;

    // 3. 批量向量化（每批 10 条，避免 API 限流）
    const batchSize = 10;
    for (int i = 0; i < chunks.length; i += batchSize) {
      final end = min(i + batchSize, chunks.length);
      final batch = chunks.sublist(i, end);
      final embeddings = await _embeddingService.embedBatch(
        config: config,
        texts: batch,
      );

      // 4. 存入 memories，type=document_chunk
      for (int j = 0; j < batch.length; j++) {
        final meta = <String, dynamic>{
          'docId': doc.id,
          'docName': doc.name,
          'chunkIndex': i + j,
          'totalChunks': chunks.length,
        };
        if (version != null) meta['version'] = version;
        await memoryService.storeRaw(
          type: 'document_chunk',
          content: batch[j],
          subjectId: doc.subjectId,
          embedding: embeddings[j],
          metadata: meta,
        );
      }

      onProgress?.call(end / chunks.length);
    }

    return chunks.length;
  }

  /// 重新处理文档（原子化）：先建新索引，成功后再删旧索引
  Future<int> reprocessDocument({
    required ApiConfig config,
    required MemoryService memoryService,
    required AppDocument doc,
    void Function(double progress)? onProgress,
  }) async {
    final version = DateTime.now().millisecondsSinceEpoch;
    // 1. 处理新索引（带 version 标记）
    final count = await processDocument(
      config: config,
      memoryService: memoryService,
      doc: doc,
      onProgress: onProgress,
      version: version,
    );
    // 2. 成功后删旧索引（不含当前 version 的）
    await memoryService.deleteByDocIdExceptVersion(doc.id, version);
    return count;
  }

  /// 批量重新处理多个文档
  Future<Map<String, int>> reprocessAll({
    required ApiConfig config,
    required MemoryService memoryService,
    required List<AppDocument> docs,
    void Function(String docName, double progress)? onProgress,
  }) async {
    final results = <String, int>{};
    for (int i = 0; i < docs.length; i++) {
      final doc = docs[i];
      try {
        final count = await reprocessDocument(
          config: config,
          memoryService: memoryService,
          doc: doc,
          onProgress: (p) => onProgress?.call(doc.name, p),
        );
        results[doc.name] = count;
      } catch (e) {
        results[doc.name] = -1; // -1 表示失败
      }
    }
    return results;
  }

  /// 判断文档类型是否支持索引
  static bool isIndexable(String type) {
    return ['txt', 'pdf', 'doc', 'docx'].contains(type);
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/document.dart';
import '../models/subject.dart';
import '../providers/app_provider.dart';
import '../services/document_processor.dart';
import '../screens/exam_recognition_screen.dart';
import '../screens/knowledge_card_edit_screen.dart';
import '../screens/classroom_screen.dart';
import '../screens/review_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class SubjectDetailScreen extends ConsumerStatefulWidget {
  final Subject subject;

  const SubjectDetailScreen({super.key, required this.subject});

  @override
  ConsumerState<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends ConsumerState<SubjectDetailScreen> {
  final _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider(widget.subject.id));
    final knowledgeCards = ref.watch(knowledgeCardsProvider(widget.subject.id));
    final color = _parseColor(widget.subject.color ?? '#88D8B0');

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.subject.icon ?? '📚', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(widget.subject.name),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) => _handleMenu(v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'review', child: Text('开始复习')),
              const PopupMenuItem(value: 'classroom', child: Text('AI 课堂')),
              const PopupMenuItem(value: 'exam', child: Text('试题拍照识别')),
              const PopupMenuItem(value: 'reindex', child: Text('重建文档索引')),
              const PopupMenuItem(value: 'rename', child: Text('重命名科目')),
              const PopupMenuItem(value: 'delete', child: Text('删除科目')),
            ],
          ),
        ],
      ),
      body: documents.isEmpty && knowledgeCards.isEmpty
          ? _buildEmptyState(color)
          : _buildContentList(documents, knowledgeCards, color),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUploadSheet(color),
        backgroundColor: color,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_outlined, size: 64, color: color.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            '还没有文档',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.text.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮上传',
            style: TextStyle(
              fontSize: 14,
              color: context.textSec.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickAndUpload(ImageSource.camera),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('拍照'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _pickAndUpload(ImageSource.gallery),
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('相册'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _pickAndUploadFile,
                icon: const Icon(Icons.file_present, size: 18),
                label: const Text('文件'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContentList(List<AppDocument> docs, List<dynamic> knowledgeCards, Color color) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        // 文档列表
        if (docs.isNotEmpty) ...[
          _buildSectionHeader('文档', '${docs.length}', color),
          ...docs.map((doc) => _buildDocumentCard(doc, color)),
        ],
        // 知识卡片列表
        if (knowledgeCards.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader('知识卡片', '${knowledgeCards.length}', color),
          ...knowledgeCards.map((card) => _buildKnowledgeCardTile(card, color)),
        ],
        if (docs.isEmpty && knowledgeCards.isNotEmpty)
          _buildEmptyState(color),
      ],
    );
  }

  Widget _buildSectionHeader(String title, String count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3, height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textSec)),
          const SizedBox(width: 4),
          Text(count, style: TextStyle(fontSize: 12, color: context.textSec.withOpacity(0.6))),
        ],
      ),
    );
  }

  Widget _buildKnowledgeCardTile(dynamic card, Color color) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => KnowledgeCardEditScreen(
              subjectId: widget.subject.id,
              card: card,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    card.title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (card.source == 'chat')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('AI', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              card.content,
              style: TextStyle(fontSize: 12, color: context.textSec, height: 1.5),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (card.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: card.tags.map<Widget>((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(tag, style: TextStyle(fontSize: 10, color: color)),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentCard(AppDocument doc, Color color) {
    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(doc),
      onDismissed: (_) => _deleteDoc(doc),
      child: GlassCard(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        child: InkWell(
          onTap: () => _viewDocument(doc),
          onLongPress: DocumentProcessor.isIndexable(doc.type)
              ? () => _showDocContextMenu(doc)
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: [
              // 缩略图或类型图标
              _buildThumbnail(doc, color),
              const SizedBox(width: 12),
              // 文件信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          doc.typeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (['txt', 'pdf', 'doc', 'docx'].contains(doc.type)) ...[
                          const SizedBox(width: 6),
                          _buildIndexBadge(doc),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          _formatFileSize(doc.fileSize),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSec,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MM-dd HH:mm').format(doc.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSec,
                          ),
                        ),
                      ],
                    ),
                    if (doc.description != null && doc.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          doc.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSec.withOpacity(0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.textSec, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndexBadge(AppDocument doc) {
    return _IndexBadge(docId: doc.id);
  }

  Widget _buildThumbnail(AppDocument doc, Color color) {
    if (doc.type == 'image' && doc.thumbnailPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(doc.thumbnailPath!),
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildTypeIcon(doc, color),
        ),
      );
    }
    return _buildTypeIcon(doc, color);
  }

  Widget _buildTypeIcon(AppDocument doc, Color color) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(doc.typeIcon, style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  void _showUploadSheet(Color color) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassCard(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '上传文档',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.camera_alt, size: 22, color: AppColors.primary),
              ),
              title: const Text('拍照'),
              subtitle: const Text('拍摄试题、笔记、PPT'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.photo_library, size: 22, color: AppColors.primary),
              ),
              title: const Text('从相册选择'),
              subtitle: const Text('选择已有图片'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.file_present, size: 22, color: AppColors.primary),
              ),
              title: const Text('选择文件'),
              subtitle: const Text('PDF、Word、Excel 等'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndUploadFile();
              },
            ),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.document_scanner, size: 22, color: AppColors.primary),
              ),
              title: const Text('试题拍照识别'),
              subtitle: const Text('AI 分析试题知识点'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExamRecognitionScreen(
                      subjectId: widget.subject.id,
                      subjectName: widget.subject.name,
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 1, indent: 60),
            ListTile(
              leading: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lightbulb_outline, size: 22, color: AppColors.primary),
              ),
              title: const Text('新建知识卡片'),
              subtitle: const Text('手动创建知识点'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KnowledgeCardEditScreen(
                      subjectId: widget.subject.id,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (image == null) return;

    if (!mounted) return;

    // 让用户输入描述
    final description = await _showDescriptionDialog();
    if (!mounted) return;

    // 复制文件到应用目录
    final appDir = await getApplicationDocumentsDirectory();
    final docDir = Directory('${appDir.path}/documents/${widget.subject.id}');
    await docDir.create(recursive: true);

    final ext = image.path.split('.').last;
    final docId = const Uuid().v4();
    final fileName = '${docId}.$ext';
    final savedPath = '${docDir.path}/$fileName';

    await File(image.path).copy(savedPath);

    // 缩略图直接用原图路径（图片类型）
    final doc = AppDocument(
      id: docId,
      name: image.name,
      type: 'image',
      subjectId: widget.subject.id,
      filePath: savedPath,
      thumbnailPath: savedPath,
      fileSize: await File(savedPath).length(),
      description: description,
      createdAt: DateTime.now(),
    );

    await ref.read(documentsProvider(widget.subject.id).notifier).add(doc);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已上传「${doc.name}」'), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'zip', 'rar'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    if (!mounted) return;

    final description = await _showDescriptionDialog();
    if (!mounted) return;

    final appDir = await getApplicationDocumentsDirectory();
    final docDir = Directory('${appDir.path}/documents/${widget.subject.id}');
    await docDir.create(recursive: true);

    final ext = file.extension ?? 'bin';
    final docId = const Uuid().v4();
    final fileName = '${docId}.$ext';
    final savedPath = '${docDir.path}/$fileName';

    await File(file.path!).copy(savedPath);

    final doc = AppDocument(
      id: docId,
      name: file.name,
      type: ext,
      subjectId: widget.subject.id,
      filePath: savedPath,
      thumbnailPath: null,
      fileSize: file.size,
      description: description,
      createdAt: DateTime.now(),
    );

    await ref.read(documentsProvider(widget.subject.id).notifier).add(doc);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已上传「${doc.name}」'), duration: const Duration(seconds: 1)),
      );
    }

    // 自动处理支持的文档类型
    if (['txt', 'pdf', 'doc', 'docx'].contains(doc.type)) {
      _processDocument(doc);
    }
  }

  void _processDocument(AppDocument doc) async {
    if (!mounted) return;
    final memoryService = ref.read(memoryServiceProvider);

    // 去重：已索引的文档跳过
    final existing = await memoryService.countByDocId(doc.id);
    if (existing > 0) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在分析文档内容...'), duration: Duration(seconds: 2)),
    );
    try {
      final config = ref.read(apiConfigProvider);
      final dbService = ref.read(databaseServiceProvider);
      final processor = DocumentProcessor(dbService: dbService);
      final chunkCount = await processor.processDocument(
        config: config,
        memoryService: memoryService,
        doc: doc,
      );
      if (mounted && chunkCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${doc.name}」已加入知识库（$chunkCount 个片段）'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文档分析失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  Future<String?> _showDescriptionDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('添加描述（可选）'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: '例如：期中考试复习资料',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('跳过'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _viewDocument(AppDocument doc) {
    if (doc.type == 'image') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _ImageViewerScreen(doc: doc),
        ),
      );
    } else {
      OpenFilex.open(doc.filePath);
    }
  }

  Future<bool?> _confirmDelete(AppDocument doc) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除文档'),
        content: Text('确定要删除「${doc.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _deleteDoc(AppDocument doc) async {
    try {
      await File(doc.filePath).delete(recursive: true);
      if (doc.thumbnailPath != null && doc.thumbnailPath != doc.filePath) {
        await File(doc.thumbnailPath!).delete(recursive: true);
      }
    } catch (_) {}
    // 清除文档在向量库中的索引片段
    ref.read(memoryServiceProvider).deleteByDocId(doc.id);
    ref.read(documentsProvider(widget.subject.id).notifier).delete(doc.id);
  }

  void _showDocContextMenu(AppDocument doc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('重新索引'),
              subtitle: const Text('用新策略重新处理文档'),
              onTap: () {
                Navigator.pop(ctx);
                _reprocessSingleDocument(doc);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('打开文件'),
              onTap: () {
                Navigator.pop(ctx);
                _viewDocument(doc);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _reindexAllDocuments() async {
    final documents = ref.read(documentsProvider(widget.subject.id));
    final indexable = documents.where((d) => DocumentProcessor.isIndexable(d.type)).toList();
    if (indexable.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可索引的文档'), duration: Duration(seconds: 2)),
        );
      }
      return;
    }

    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重建文档索引'),
        content: Text('将重新处理 ${indexable.length} 个文档，旧索引会被替换。继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final config = ref.read(apiConfigProvider);
    final memoryService = ref.read(memoryServiceProvider);
    final processor = DocumentProcessor(dbService: ref.read(databaseServiceProvider));

    // 显示进度
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在重建索引（0/${indexable.length}）...'), duration: const Duration(seconds: 60)),
      );
    }

    int done = 0;
    int totalChunks = 0;
    for (final doc in indexable) {
      try {
        final count = await processor.reprocessDocument(
          config: config,
          memoryService: memoryService,
          doc: doc,
        );
        totalChunks += count;
      } catch (_) {}
      done++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('索引完成：$done 个文档，$totalChunks 个片段'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _reprocessSingleDocument(AppDocument doc) async {
    if (!mounted) return;
    final config = ref.read(apiConfigProvider);
    final memoryService = ref.read(memoryServiceProvider);
    final processor = DocumentProcessor(dbService: ref.read(databaseServiceProvider));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在重新索引「${doc.name}」...'), duration: const Duration(seconds: 30)),
    );

    try {
      final count = await processor.reprocessDocument(
        config: config,
        memoryService: memoryService,
        doc: doc,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${doc.name}」已重新索引（$count 个片段）'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新索引失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _handleMenu(String action) {
    switch (action) {
      case 'review':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReviewScreen(
              subjectId: widget.subject.id,
              subjectName: widget.subject.name,
            ),
          ),
        );
        break;
      case 'classroom':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ClassroomScreen(
              subjectId: widget.subject.id,
            ),
          ),
        );
        break;
      case 'exam':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExamRecognitionScreen(
              subjectId: widget.subject.id,
              subjectName: widget.subject.name,
            ),
          ),
        );
        break;
      case 'rename':
        _showRenameDialog();
        break;
      case 'delete':
        _confirmDeleteSubject();
        break;
      case 'reindex':
        _reindexAllDocuments();
        break;
    }
  }

  void _showRenameDialog() {
    final ctrl = TextEditingController(text: widget.subject.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('重命名科目'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                ref.read(subjectsProvider.notifier).update(
                  widget.subject.copyWith(name: name),
                );
                Navigator.pop(ctx);
                Navigator.pop(context); // 返回上一页
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSubject() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除科目'),
        content: Text('确定要删除「${widget.subject.name}」吗？所有文档也会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(subjectsProvider.notifier).delete(widget.subject.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

// 文档索引状态标签
class _IndexBadge extends ConsumerStatefulWidget {
  final String docId;
  const _IndexBadge({required this.docId});

  @override
  ConsumerState<_IndexBadge> createState() => _IndexBadgeState();
}

class _IndexBadgeState extends ConsumerState<_IndexBadge> {
  Future<int>? _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(memoryServiceProvider).countByDocId(widget.docId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '已索引 ${snapshot.data}',
            style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w500),
          ),
        );
      },
    );
  }
}

// 图片查看器
class _ImageViewerScreen extends StatelessWidget {
  final AppDocument doc;
  const _ImageViewerScreen({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(doc.name, style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.file(File(doc.filePath)),
        ),
      ),
    );
  }
}

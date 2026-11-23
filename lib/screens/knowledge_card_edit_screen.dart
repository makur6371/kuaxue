import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/knowledge_card.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

class KnowledgeCardEditScreen extends ConsumerStatefulWidget {
  final String subjectId;
  final KnowledgeCard? card; // null = 新建

  const KnowledgeCardEditScreen({
    super.key,
    required this.subjectId,
    this.card,
  });

  @override
  ConsumerState<KnowledgeCardEditScreen> createState() => _KnowledgeCardEditScreenState();
}

class _KnowledgeCardEditScreenState extends ConsumerState<KnowledgeCardEditScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late TextEditingController _tagsCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.card?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.card?.content ?? '');
    _tagsCtrl = TextEditingController(
      text: widget.card?.tags.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.card != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑知识卡片' : '新建知识卡片'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '知识点名称',
            ),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _contentCtrl,
            decoration: const InputDecoration(
              labelText: '内容',
              hintText: '知识点详解、解题思路、公式定理等...',
              alignLabelWithHint: true,
            ),
            maxLines: null,
            minLines: 8,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: '标签（可选）',
              hintText: '用逗号分隔，如：重点, 公式, 考试',
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save, size: 18),
                  label: Text(isEditing ? '保存修改' : '创建卡片'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          if (!isEditing) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _saveAndReview,
              icon: const Icon(Icons.school, size: 18),
              label: const Text('创建并加入复习'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _parseTags() {
    return _tagsCtrl.text
        .split(RegExp(r'[,，]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题和内容不能为空'), duration: Duration(seconds: 1)),
      );
      return;
    }

    setState(() => _saving = true);
    final notifier = ref.read(knowledgeCardsProvider(widget.subjectId).notifier);

    if (widget.card != null) {
      await notifier.update(
        id: widget.card!.id,
        title: title,
        content: content,
        tags: _parseTags(),
      );
    } else {
      await notifier.add(
        title: title,
        content: content,
        tags: _parseTags(),
        source: 'manual',
      );
    }

    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text(widget.card != null ? '已保存' : '已创建'), duration: const Duration(seconds: 1)),
      );
    }
  }

  Future<void> _saveAndReview() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标题和内容不能为空'), duration: Duration(seconds: 1)),
      );
      return;
    }

    setState(() => _saving = true);

    // 创建知识卡片
    final notifier = ref.read(knowledgeCardsProvider(widget.subjectId).notifier);
    await notifier.add(
      title: title,
      content: content,
      tags: _parseTags(),
      source: 'manual',
    );

    // 同时创建复习卡片
    await ref.read(reviewCardsProvider.notifier).add(
      title: title,
      content: content,
      subjectId: widget.subjectId,
      source: 'manual',
    );

    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('已创建并加入复习队列'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除知识卡片'),
        content: Text('确定删除「${widget.card!.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(knowledgeCardsProvider(widget.subjectId).notifier).delete(widget.card!.id);
              if (mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

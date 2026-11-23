import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/subject.dart';
import '../providers/app_provider.dart';
import '../screens/exam_recognition_screen.dart';
import '../screens/subject_detail_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class DocumentScreen extends ConsumerStatefulWidget {
  const DocumentScreen({super.key});

  @override
  ConsumerState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends ConsumerState<DocumentScreen> {
  final _subjectNameCtrl = TextEditingController();

  // 预设科目颜色
  static const _presetColors = [
    '#88D8B0', '#FF6B6B', '#4ECDC4', '#45B7D1',
    '#96CEB4', '#FFEAA7', '#DDA0DD', '#98D8C8',
    '#F7DC6F', '#BB8FCE', '#85C1E9', '#F1948A',
  ];

  // 预设科目图标
  static const _presetIcons = [
    '📐', '📚', '🔬', '🧪', '🌍', '💻', '🎨', '🎵',
    '📊', '📝', '🔤', '🧮', '📖', '🎓', '✏️', '📏',
  ];

  @override
  void dispose() {
    _subjectNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref.watch(subjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('文档管理'),
      ),
      body: subjects.isEmpty
          ? _buildEmptyState()
          : _buildSubjectList(subjects),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_outlined,
            size: 64,
            color: AppColors.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有科目',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.text.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮添加第一个科目',
            style: TextStyle(
              fontSize: 14,
              color: context.textSec.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddSubjectSheet,
            icon: const Icon(Icons.add),
            label: const Text('添加科目'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectList(List<Subject> subjects) {
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          itemCount: subjects.length,
          itemBuilder: (context, index) {
            final subject = subjects[index];
            return _buildSubjectCard(subject, index);
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: _showAddSubjectSheet,
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectCard(Subject subject, int index) {
    final color = _parseColor(subject.color ?? '#88D8B0');

    return Dismissible(
      key: Key(subject.id),
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
      confirmDismiss: (_) => _confirmDelete(subject),
      onDismissed: (_) => ref.read(subjectsProvider.notifier).delete(subject.id),
      child: GlassCard(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SubjectDetailScreen(subject: subject),
            ),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    subject.icon ?? '📚',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '创建于 ${DateFormat('yyyy-MM-dd').format(subject.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSec,
                      ),
                    ),
                  ],
                ),
              ),
              _buildDocCount(subject.id, color),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: context.textSec,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocCount(String subjectId, Color color) {
    final countAsync = ref.watch(subjectDocCountProvider(subjectId));
    return countAsync.when(
      data: (count) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$count 文档',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      loading: () => const SizedBox(width: 20, height: 20),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Color _parseColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  Future<bool?> _confirmDelete(Subject subject) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除科目'),
        content: Text('确定要删除"${subject.name}"吗？科目下的所有文档也将被删除。'),
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

  void _showEditSubjectSheet(Subject subject) {
    final nameCtrl = TextEditingController(text: subject.name);
    String selectedIcon = subject.icon ?? _presetIcons[0];
    String selectedColor = subject.color ?? _presetColors[0];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return GlassCard(
            margin: const EdgeInsets.all(12),
            padding: EdgeInsets.fromLTRB(20, 20, 20,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '编辑科目',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '科目名称',
                      hintText: '例如：高等数学、大学英语',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 20),
                  const Text('选择图标', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presetIcons.map((icon) {
                      final isSelected = icon == selectedIcon;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedIcon = icon),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.2)
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.glassBorder,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text('选择颜色', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presetColors.map((colorHex) {
                      final color = _parseColor(colorHex);
                      final isSelected = colorHex == selectedColor;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = colorHex),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(
                                    color: color.withOpacity(0.5),
                                    blurRadius: 8,
                                  )]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('请输入科目名称'), duration: Duration(seconds: 1)),
                        );
                        return;
                      }
                      ref.read(subjectsProvider.notifier).update(
                        subject.copyWith(
                          name: name,
                          icon: selectedIcon,
                          color: selectedColor,
                        ),
                      );
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddSubjectSheet() {
    _subjectNameCtrl.clear();
    String selectedIcon = _presetIcons[0];
    String selectedColor = _presetColors[0];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return GlassCard(
            margin: const EdgeInsets.all(12),
            padding: EdgeInsets.fromLTRB(20, 20, 20,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '添加科目',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _subjectNameCtrl,
                    decoration: const InputDecoration(
                      labelText: '科目名称',
                      hintText: '例如：高等数学、大学英语',
                    ),
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 20),
                  const Text('选择图标', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presetIcons.map((icon) {
                      final isSelected = icon == selectedIcon;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedIcon = icon),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.2)
                                : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.glassBorder,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text('选择颜色', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presetColors.map((colorHex) {
                      final color = _parseColor(colorHex);
                      final isSelected = colorHex == selectedColor;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = colorHex),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(
                                    color: color.withOpacity(0.5),
                                    blurRadius: 8,
                                  )]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final name = _subjectNameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('请输入科目名称'), duration: Duration(seconds: 1)),
                        );
                        return;
                      }
                      ref.read(subjectsProvider.notifier).add(
                        name,
                        icon: selectedIcon,
                        color: selectedColor,
                      );
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/todo.dart';
import '../providers/app_provider.dart';
import '../screens/review_screen.dart';
import '../theme/app_theme.dart';


class SchedulePanel extends ConsumerWidget {
  final bool isEmbedded;
  final bool compact; // 紧凑模式：只显示摘要 + 最近几条
  const SchedulePanel({super.key, this.isEmbedded = false, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todosProvider);
    final dueCount = ref.watch(dueReviewCountProvider);

    final content = Column(
      children: [
        if (!isEmbedded)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        // 标题栏
        Padding(
          padding: EdgeInsets.fromLTRB(20, isEmbedded ? 8 : 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                '智能日程',
                style: TextStyle(
                  fontSize: compact ? 16 : 18,
                  fontWeight: FontWeight.bold,
                  color: context.text,
                ),
              ),
              const Spacer(),
              if (!compact)
                IconButton(
                  icon: Icon(Icons.add_circle_outline, color: AppColors.primary),
                  onPressed: () => _showAddDialog(context, ref),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 紧凑模式摘要
        if (compact) _buildSummary(todos, dueCount),
        // 复习卡片
        if (dueCount > 0 && !compact) _buildReviewCard(context, dueCount),
        if (dueCount > 0 && compact) _buildCompactReviewCard(context, dueCount),
        // 列表
        Expanded(
          child: todos.isEmpty && dueCount == 0
              ? _buildEmptyState(context)
              : compact
                  ? _buildCompactList(context, ref, todos)

                  : _buildGroupedList(context, ref, todos),
        ),
        // 紧凑模式底部按钮
        if (compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddDialog(context, ref),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (isEmbedded) return content;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: SafeArea(child: content),
    );
  }

  // ── 紧凑模式摘要 ──

  Widget _buildSummary(List<Todo> todos, int dueCount) {
    final pendingCount = todos.where((t) => !t.isDone).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(
        children: [
          _summaryChip('$pendingCount 项待办', Icons.checklist),
          if (dueCount > 0) ...[
            const SizedBox(width: 8),
            _summaryChip('$dueCount 张复习', Icons.school),
          ],
        ],
      ),
    );
  }

  Widget _summaryChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildCompactReviewCard(BuildContext context, int dueCount) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.school, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('今日复习 $dueCount 张', style: TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ── 紧凑列表（最多 5 条，不含已完成） ──

  Widget _buildCompactList(BuildContext context, WidgetRef ref, List<Todo> todos) {
    final pending = todos.where((t) => !t.isDone).toList()
      ..sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });

    final display = pending.take(5).toList();

    if (display.isEmpty) {
      return Center(
        child: Text('暂无待办', style: TextStyle(fontSize: 13, color: context.textSec)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      itemCount: display.length,
      itemBuilder: (ctx, i) => _buildTodoCard(context, display[i], ref, compact: true),
    );
  }

  // ── 复习卡片（完整版） ──

  Widget _buildReviewCard(BuildContext context, int dueCount) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewScreen()));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withOpacity(0.12),
              AppColors.primary.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.school, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('今日复习', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('$dueCount 张卡片待复习',
                    style: TextStyle(fontSize: 12, color: context.textSec)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$dueCount',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppColors.primary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_outlined, size: 48, color: context.textSec.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text('暂无待办事项',
            style: TextStyle(fontSize: 15, color: context.textSec.withOpacity(0.6))),
          const SizedBox(height: 4),
          Text('点击 + 或对 AI 说\n"帮我创建待办"',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.textSec.withOpacity(0.4))),
        ],
      ),
    );
  }

  Widget _buildGroupedList(BuildContext context, WidgetRef ref, List<Todo> todos) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeek = today.add(const Duration(days: 7));

    final pending = todos.where((t) => !t.isDone).toList();
    final done = todos.where((t) => t.isDone).toList();

    final overdue = pending.where((t) => t.dueDate != null && t.dueDate!.isBefore(today)).toList();
    final todayTodos = pending.where((t) =>
        t.dueDate != null && !t.dueDate!.isBefore(today) && t.dueDate!.isBefore(tomorrow)).toList();
    final upcoming = pending.where((t) =>
        t.dueDate != null && !t.dueDate!.isBefore(tomorrow) && t.dueDate!.isBefore(nextWeek)).toList();
    final later = pending.where((t) => t.dueDate == null || !t.dueDate!.isBefore(nextWeek)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (overdue.isNotEmpty) ...[
          _buildSection(context, '已逾期', overdue, ref, color: Colors.redAccent),
          const SizedBox(height: 12),
        ],
        if (todayTodos.isNotEmpty) ...[
          _buildSection(context, '今天', todayTodos, ref),
          const SizedBox(height: 12),
        ],
        if (upcoming.isNotEmpty) ...[
          _buildSection(context, '近期', upcoming, ref),
          const SizedBox(height: 12),
        ],
        if (later.isNotEmpty) ...[
          _buildSection(context, '稍后', later, ref),
          const SizedBox(height: 12),
        ],
        if (done.isNotEmpty) ...[
          _buildSection(context, '已完成', done, ref, showDelete: true),
        ],
      ],
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Todo> items, WidgetRef ref, {Color? color, bool showDelete = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3, height: 14,
              decoration: BoxDecoration(
                color: color ?? AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? context.textSec)),
            const SizedBox(width: 4),
            Text('${items.length}',
              style: TextStyle(fontSize: 12, color: context.textSec.withOpacity(0.6))),
          ],
        ),
        const SizedBox(height: 6),
        ...items.map((todo) => _buildTodoCard(context, todo, ref, showDelete: showDelete)),
      ],
    );
  }

  Widget _buildTodoCard(BuildContext context, Todo todo, WidgetRef ref, {bool showDelete = false, bool compact = false}) {
    final priorityColor = todo.priority == 2
        ? Colors.redAccent
        : todo.priority == 1
            ? Colors.orange
            : null;

    return Dismissible(
      key: Key(todo.id),
      direction: showDelete ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(todosProvider.notifier).delete(todo.id),
      child: GestureDetector(
        onTap: () => ref.read(todosProvider.notifier).toggleDone(todo.id),
        child: Container(
          margin: EdgeInsets.only(bottom: compact ? 4 : 8),
          padding: compact ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8) : const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: todo.isDone ? AppColors.primary.withOpacity(0.08) : context.bubble,
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
            border: Border.all(
              color: todo.isDone
                  ? AppColors.primary.withOpacity(0.3)
                  : priorityColor?.withOpacity(0.4) ?? Colors.grey.withOpacity(0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(
                todo.isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                color: todo.isDone ? AppColors.primary : (priorityColor ?? context.textSec),
                size: compact ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13 : 14,
                        color: todo.isDone ? context.textSec : context.text,
                        decoration: todo.isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (todo.dueDate != null && !compact)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatDueDate(todo.dueDate!),
                          style: TextStyle(
                            fontSize: 11,
                            color: _isOverdue(todo.dueDate!) && !todo.isDone
                                ? Colors.redAccent
                                : context.textSec,
                          ),
                        ),
                      ),
                    if (todo.dueDate != null && compact)
                      Text(
                        _formatDueDate(todo.dueDate!),
                        style: TextStyle(fontSize: 10, color: context.textSec.withOpacity(0.7)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) {
      return '今天 ${DateFormat('HH:mm').format(date)}';
    } else if (dateDay == today.add(const Duration(days: 1))) {
      return '明天 ${DateFormat('HH:mm').format(date)}';
    } else if (dateDay.isBefore(today.add(const Duration(days: 7)))) {
      return DateFormat('EEEE HH:mm', 'zh_CN').format(date);
    }
    return DateFormat('MM/dd HH:mm').format(date);
  }

  bool _isOverdue(DateTime date) => date.isBefore(DateTime.now());

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('新建待办'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '待办内容'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.calendar_today, size: 20, color: AppColors.primary),
                title: Text(
                  selectedDate != null
                      ? DateFormat('yyyy-MM-dd HH:mm').format(selectedDate!)
                      : '设置截止时间（可选）',
                  style: TextStyle(
                    fontSize: 14,
                    color: selectedDate != null ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                ),
                trailing: selectedDate != null
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                        onPressed: () => setDialogState(() => selectedDate = null),
                      )
                    : null,
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null && ctx.mounted) {
                    final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                    setDialogState(() {
                      selectedDate = DateTime(
                        date.year, date.month, date.day,
                        time?.hour ?? 23, time?.minute ?? 59,
                      );
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                ref.read(todosProvider.notifier).add(Todo(
                  id: const Uuid().v4(),
                  title: title,
                  dueDate: selectedDate,
                  createdAt: DateTime.now(),
                ));
                Navigator.pop(ctx);
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }
}

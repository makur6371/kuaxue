import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/classroom.dart';
import '../providers/app_provider.dart';
import '../services/classroom_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

// Classroom Service Provider
final classroomServiceProvider = Provider<ClassroomService>((ref) {
  return ClassroomService();
});

class ClassroomScreen extends ConsumerStatefulWidget {
  final String? topic;
  final String? subjectId;
  final String? documentContent;

  const ClassroomScreen({
    super.key,
    this.topic,
    this.subjectId,
    this.documentContent,
  });

  @override
  ConsumerState<ClassroomScreen> createState() => _ClassroomScreenState();
}

class _ClassroomScreenState extends ConsumerState<ClassroomScreen> {
  final _topicController = TextEditingController();
  final _scrollController = ScrollController();

  // 课堂状态
  _Phase _phase = _Phase.input;
  String _topic = '';
  List<ClassroomScene> _scenes = [];
  int _currentSceneIndex = 0;

  // 每个场景的渲染内容
  final Map<int, List<_RenderedChunk>> _sceneChunks = {};

  // 当前场景的测验状态
  int? _selectedAnswer;
  String? _quizFeedback;
  bool _isStreaming = false;
  bool _isGeneratingOutline = false;
  String? _error;

  // TTS 状态
  bool _ttsEnabled = true;

  @override
  void initState() {
    super.initState();
    _ttsEnabled = ref.read(ttsSettingsProvider).enabled;
    if (widget.topic != null && widget.topic!.isNotEmpty) {
      _topicController.text = widget.topic!;
      _topic = widget.topic!;
      _generateOutline();
    }
  }

  @override
  void dispose() {
    _topicController.dispose();
    _scrollController.dispose();
    ref.read(ttsServiceProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _topic.isNotEmpty ? '🎓 $_topic' : '🎓 AI 课堂',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (_phase == _Phase.teaching) ...[
            IconButton(
              icon: Icon(
                _ttsEnabled ? Icons.volume_up : Icons.volume_off,
                color: _ttsEnabled ? AppColors.primary : null,
              ),
              tooltip: _ttsEnabled ? '关闭朗读' : '开启朗读',
              onPressed: () {
                setState(() => _ttsEnabled = !_ttsEnabled);
                if (!_ttsEnabled) {
                  ref.read(ttsServiceProvider).stop();
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '朗读设置',
              onPressed: _showTtsSettings,
            ),
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: '课程大纲',
              onPressed: _showOutlineDrawer,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.input:
        return _buildInputView();
      case _Phase.outline:
        return _buildOutlineView();
      case _Phase.teaching:
        return _buildTeachingView();
      case _Phase.done:
        return _buildDoneView();
    }
  }

  // ==================== 输入阶段 ====================

  Widget _buildInputView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school, size: 64, color: AppColors.primary.withOpacity(0.6)),
          const SizedBox(height: 24),
          Text(
            'AI 课堂',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: context.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '输入学习主题，开始互动课堂',
            style: TextStyle(fontSize: 14, color: context.textSec),
          ),
          const SizedBox(height: 32),
          GlassCard(
            child: TextField(
              controller: _topicController,
              decoration: InputDecoration(
                hintText: '例如：高中数学·导数、物理·牛顿运动定律',
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _startClassroom,
                ),
              ),
              onSubmitted: (_) => _startClassroom(),
              textInputAction: TextInputAction.go,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  void _startClassroom() {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) return;
    _topic = topic;
    _generateOutline();
  }

  Future<void> _generateOutline() async {
    setState(() {
      _isGeneratingOutline = true;
      _phase = _Phase.outline;
      _error = null;
    });

    try {
      final config = ref.read(apiConfigProvider);
      final service = ref.read(classroomServiceProvider);
      final scenes = await service.generateOutline(
        config: config,
        topic: _topic,
        documentContent: widget.documentContent,
      );

      if (scenes.isEmpty) {
        setState(() {
          _error = '未能生成课程大纲，请换个主题试试';
          _phase = _Phase.input;
          _isGeneratingOutline = false;
        });
        return;
      }

      setState(() {
        _scenes = scenes;
        _isGeneratingOutline = false;
      });
    } catch (e) {
      setState(() {
        _error = '生成大纲失败: $e';
        _phase = _Phase.input;
        _isGeneratingOutline = false;
      });
    }
  }

  // ==================== 大纲阶段 ====================

  Widget _buildOutlineView() {
    if (_isGeneratingOutline) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('正在生成课程大纲...'),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📋 课程大纲',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: context.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '共 ${_scenes.length} 个知识点',
            style: TextStyle(fontSize: 14, color: context.textSec),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _scenes.length,
              itemBuilder: (context, index) {
                return GlassCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.2),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      _scenes[index].title,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startTeaching,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('开始上课', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  void _startTeaching() {
    setState(() {
      _phase = _Phase.teaching;
      _currentSceneIndex = 0;
    });
    _teachCurrentScene();
  }

  // ==================== 教学阶段 ====================

  Widget _buildTeachingView() {
    final scene = _scenes[_currentSceneIndex];
    final chunks = _sceneChunks[_currentSceneIndex] ?? [];

    return Column(
      children: [
        // 进度条
        LinearProgressIndicator(
          value: (_currentSceneIndex + 1) / _scenes.length,
          backgroundColor: AppColors.primary.withOpacity(0.15),
          color: AppColors.primary,
          minHeight: 3,
        ),
        // 场景标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${_currentSceneIndex + 1}/${_scenes.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSec,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  scene.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 内容区
        Expanded(
          child: chunks.isEmpty && _isStreaming
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text('老师正在备课...'),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: chunks.length + (_isStreaming ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == chunks.length) {
                      return _buildTypingIndicator();
                    }
                    return _buildChunkWidget(chunks[index]);
                  },
                ),
        ),
        // 底部操作栏
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildChunkWidget(_RenderedChunk chunk) {
    switch (chunk.type) {
      case _ChunkType.teach:
        return _buildTeacherBubble(chunk.content!);
      case _ChunkType.studentAsk:
        return _buildStudentBubble(chunk.studentName!, chunk.content!);
      case _ChunkType.studentAnswer:
        return _buildTeacherBubble(chunk.content!);
      case _ChunkType.quiz:
        return _buildQuizWidget(chunk.quiz!);
    }
  }

  Widget _buildTeacherBubble(String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withOpacity(0.2),
            child: const Text('🧑‍🏫', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.all(12),
              child: MarkdownBody(
                data: content,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(fontSize: 14, height: 1.6, color: context.text),
                  code: TextStyle(
                    fontSize: 13,
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    fontFamily: 'monospace',
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  h1: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.text),
                  h2: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: context.text),
                  h3: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: context.text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentBubble(String name, String question) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.orange.withOpacity(0.2),
            child: const Text('🙋', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$name 提问：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    question,
                    style: TextStyle(fontSize: 14, color: context.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizWidget(ClassroomQuiz quiz) {
    final letters = ['A', 'B', 'C', 'D'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('❓', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  '随堂测验',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              quiz.question,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.text,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(quiz.options.length, (i) {
              final isSelected = _selectedAnswer == i;
              final isCorrect = i == quiz.correctIndex;
              final showResult = _selectedAnswer != null;

              Color? bgColor;
              Color? borderColor;
              if (showResult) {
                if (isCorrect) {
                  bgColor = Colors.green.withOpacity(0.1);
                  borderColor = Colors.green;
                } else if (isSelected && !isCorrect) {
                  bgColor = Colors.red.withOpacity(0.1);
                  borderColor = Colors.red;
                }
              } else if (isSelected) {
                bgColor = AppColors.primary.withOpacity(0.15);
                borderColor = AppColors.primary;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: _selectedAnswer == null ? () => _answerQuiz(i) : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bgColor ?? context.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: borderColor ?? context.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: showResult && isCorrect
                                ? Colors.green
                                : showResult && isSelected
                                    ? Colors.red
                                    : AppColors.primary.withOpacity(0.15),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            letters[i],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: showResult && (isCorrect || isSelected)
                                  ? Colors.white
                                  : context.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            quiz.options[i],
                            style: TextStyle(fontSize: 14, color: context.text),
                          ),
                        ),
                        if (showResult && isCorrect)
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        if (showResult && isSelected && !isCorrect)
                          const Icon(Icons.cancel, color: Colors.red, size: 20),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (_quizFeedback != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _selectedAnswer == quiz.correctIndex
                      ? Colors.green.withOpacity(0.08)
                      : Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _quizFeedback!,
                  style: TextStyle(fontSize: 13, color: context.text, height: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary.withOpacity(0.2),
            child: const Text('🧑‍🏫', style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      builder: (context, value, child) {
        final delay = index * 0.2;
        final opacity = ((value + delay) % 1.0);
        return Opacity(
          opacity: 0.3 + 0.7 * (1 - (opacity - 0.5).abs() * 2).clamp(0, 1),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final hasChunks = (_sceneChunks[_currentSceneIndex] ?? []).isNotEmpty;
    final canProceed = hasChunks && !_isStreaming;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: Row(
        children: [
          // 上一节
          if (_currentSceneIndex > 0)
            TextButton.icon(
              onPressed: _isStreaming ? null : _prevScene,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('上一节'),
            ),
          const Spacer(),
          // 保存到复习卡
          if (hasChunks && !_isStreaming)
            TextButton.icon(
              onPressed: _saveToReviewCard,
              icon: const Icon(Icons.bookmark_add, size: 18),
              label: const Text('保存复习卡'),
              style: TextButton.styleFrom(foregroundColor: AppColors.accent),
            ),
          const Spacer(),
          // 下一节 / 结束
          if (canProceed)
            ElevatedButton.icon(
              onPressed: _currentSceneIndex < _scenes.length - 1 ? _nextScene : _finishClassroom,
              icon: Icon(
                _currentSceneIndex < _scenes.length - 1
                    ? Icons.chevron_right
                    : Icons.check,
                size: 18,
              ),
              label: Text(_currentSceneIndex < _scenes.length - 1 ? '下一节' : '结束课堂'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 完成阶段 ====================

  Widget _buildDoneView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 24),
            Text(
              '课堂结束',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: context.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '完成了 ${_scenes.length} 个知识点的学习',
              style: TextStyle(fontSize: 15, color: context.textSec),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('返回', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 侧边栏大纲 ====================

  void _showOutlineDrawer() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '课程大纲',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.text,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _scenes.length,
                  itemBuilder: (ctx, index) {
                    final isDone = index < _currentSceneIndex;
                    final isCurrent = index == _currentSceneIndex;
                    return ListTile(
                      leading: Icon(
                        isDone
                            ? Icons.check_circle
                            : isCurrent
                                ? Icons.play_circle
                                : Icons.circle_outlined,
                        color: isDone
                            ? Colors.green
                            : isCurrent
                                ? AppColors.primary
                                : context.textSec,
                        size: 22,
                      ),
                      title: Text(
                        _scenes[index].title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                          color: isCurrent ? AppColors.primary : context.text,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _currentSceneIndex = index);
                        if (!_sceneChunks.containsKey(index)) {
                          _teachCurrentScene();
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== TTS 设置 ====================

  void _showTtsSettings() {
    final settings = ref.read(ttsSettingsProvider);
    double speed = settings.speed;
    String voice = settings.voice;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '朗读设置',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.text,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 音色选择
                  Text('音色', style: TextStyle(fontSize: 14, color: context.textSec)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TTSService.availableVoices.map((v) {
                      final selected = v == voice;
                      return ChoiceChip(
                        label: Text(v, style: TextStyle(fontSize: 13)),
                        selected: selected,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : context.text,
                        ),
                        onSelected: (_) => setSheetState(() => voice = v),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // 语速
                  Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text('语速', style: TextStyle(color: context.text)),
                      ),
                      Expanded(
                        child: Slider(
                          value: speed,
                          min: 0.1,
                          max: 1.0,
                          divisions: 9,
                          label: '${(speed * 10).round() / 10}',
                          activeColor: AppColors.primary,
                          onChanged: (v) => setSheetState(() => speed = v),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${(speed * 10).round() / 10}',
                          style: TextStyle(fontSize: 13, color: context.textSec),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 试听 + 保存
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final tts = ref.read(ttsServiceProvider);
                            final config = ref.read(apiConfigProvider);
                            await tts.speak(
                              config: config,
                              text: '你好，我是你的AI课堂老师，现在正在试听语音效果。',
                              voice: voice,
                              speed: speed,
                            );
                          },
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('试听'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ref.read(ttsSettingsProvider.notifier).update(
                                  settings.copyWith(speed: speed, voice: voice),
                                );
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==================== 教学逻辑 ====================

  Future<void> _teachCurrentScene() async {
    final index = _currentSceneIndex;
    setState(() {
      _isStreaming = true;
      _selectedAnswer = null;
      _quizFeedback = null;
      _sceneChunks[index] = [];
    });

    try {
      final config = ref.read(apiConfigProvider);
      final service = ref.read(classroomServiceProvider);
      final scene = _scenes[index];

      // 构建对话历史（之前的场景摘要）
      final history = <Map<String, dynamic>>[];
      for (int i = 0; i < index; i++) {
        final prevChunks = _sceneChunks[i] ?? [];
        final summary = prevChunks
            .where((c) => c.type == _ChunkType.teach)
            .map((c) => c.content)
            .join('\n')
            .take(500)
            .toString();
        if (summary.isNotEmpty) {
          history.add({
            'role': 'assistant',
            'content': '之前讲解了「${_scenes[i].title}」：\n$summary',
          });
        }
      }

      await for (final chunk in service.teachScene(
        config: config,
        scene: scene,
        topic: _topic,
        conversationHistory: history,
      )) {
        if (!mounted) return;

        setState(() {
          switch (chunk) {
            case TeachChunk(:final text):
              final chunks = _sceneChunks[index]!;
              if (chunks.isNotEmpty && chunks.last.type == _ChunkType.teach) {
                // 追加到上一个 teach chunk
                chunks.last = _RenderedChunk(
                  type: _ChunkType.teach,
                  content: chunks.last.content! + text,
                );
              } else {
                chunks.add(_RenderedChunk(type: _ChunkType.teach, content: text));
              }
            case StudentAskChunk(:final name, :final question):
              _sceneChunks[index]!.add(_RenderedChunk(
                type: _ChunkType.studentAsk,
                content: question,
                studentName: name,
              ));
            case StudentAnswerChunk(:final text):
              _sceneChunks[index]!.add(_RenderedChunk(
                type: _ChunkType.studentAnswer,
                content: text,
              ));
            case QuizChunk(:final quiz):
              _sceneChunks[index]!.add(_RenderedChunk(
                type: _ChunkType.quiz,
                quiz: quiz,
              ));
          }
        });

        // 自动滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sceneChunks[_currentSceneIndex] = [
          _RenderedChunk(
            type: _ChunkType.teach,
            content: '讲解出错: $e\n\n请点击"下一节"继续，或返回重试。',
          ),
        ];
      });
    }

    if (mounted) {
      setState(() => _isStreaming = false);
      // TTS 朗读讲解内容
      if (_ttsEnabled) {
        final chunks = _sceneChunks[index] ?? [];
        final teachText = chunks
            .where((c) => c.type == _ChunkType.teach)
            .map((c) => c.content!)
            .join('\n');
        if (teachText.isNotEmpty) {
          final tts = ref.read(ttsServiceProvider);
          final config = ref.read(apiConfigProvider);
          final settings = ref.read(ttsSettingsProvider);
          await tts.speak(
            config: config,
            text: teachText,
            voice: settings.voice,
            speed: settings.speed,
          );
        }
      }
    }
  }

  Future<void> _answerQuiz(int answerIndex) async {
    final chunks = _sceneChunks[_currentSceneIndex] ?? [];
    final quizChunk = chunks.lastWhere((c) => c.type == _ChunkType.quiz);
    final quiz = quizChunk.quiz!;

    setState(() => _selectedAnswer = answerIndex);

    final config = ref.read(apiConfigProvider);
    final service = ref.read(classroomServiceProvider);
    final feedback = await service.checkAnswer(
      config: config,
      quiz: quiz,
      userAnswer: answerIndex,
    );

    if (mounted) {
      setState(() => _quizFeedback = feedback);
    }
  }

  void _prevScene() {
    if (_currentSceneIndex > 0) {
      ref.read(ttsServiceProvider).stop();
      setState(() {
        _currentSceneIndex--;
        _selectedAnswer = null;
        _quizFeedback = null;
      });
    }
  }

  void _nextScene() {
    if (_currentSceneIndex < _scenes.length - 1) {
      ref.read(ttsServiceProvider).stop();
      setState(() {
        _currentSceneIndex++;
        _selectedAnswer = null;
        _quizFeedback = null;
      });
      if (!_sceneChunks.containsKey(_currentSceneIndex)) {
        _teachCurrentScene();
      }
    }
  }

  void _finishClassroom() {
    ref.read(ttsServiceProvider).stop();
    setState(() => _phase = _Phase.done);
  }

  Future<void> _saveToReviewCard() async {
    final chunks = _sceneChunks[_currentSceneIndex] ?? [];
    if (chunks.isEmpty) return;

    final scene = _scenes[_currentSceneIndex];

    // 收集本节的讲解内容
    final contentBuffer = StringBuffer();
    for (final chunk in chunks) {
      switch (chunk.type) {
        case _ChunkType.teach:
          contentBuffer.writeln(chunk.content);
        case _ChunkType.studentAsk:
          contentBuffer.writeln('\n**${chunk.studentName}提问：** ${chunk.content}');
        case _ChunkType.studentAnswer:
          contentBuffer.writeln('\n**回答：** ${chunk.content}');
        case _ChunkType.quiz:
          contentBuffer.writeln('\n**测验：** ${chunk.quiz!.question}');
          contentBuffer.writeln('答案：${String.fromCharCode(65 + chunk.quiz!.correctIndex)}');
          if (chunk.quiz!.explanation.isNotEmpty) {
            contentBuffer.writeln('解析：${chunk.quiz!.explanation}');
          }
      }
    }

    final cardsNotifier = ref.read(reviewCardsProvider.notifier);
    await cardsNotifier.add(
      title: '$_topic - ${scene.title}',
      content: contentBuffer.toString(),
      subjectId: widget.subjectId,
      source: 'classroom',
      createTodo: false,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存「${scene.title}」到复习卡'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}

// ==================== 内部数据类型 ====================

enum _Phase { input, outline, teaching, done }

enum _ChunkType { teach, studentAsk, studentAnswer, quiz }

class _RenderedChunk {
  final _ChunkType type;
  final String? content;
  final String? studentName;
  final ClassroomQuiz? quiz;

  _RenderedChunk({
    required this.type,
    this.content,
    this.studentName,
    this.quiz,
  });
}

// String extension for truncation
extension _StringTake on String {
  String take(int n) => length > n ? substring(0, n) : this;
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';
import '../providers/app_provider.dart';
import '../screens/exam_recognition_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/schedule_panel.dart';
import '../theme/app_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final VoidCallback? onSwipeRight;
  const ChatScreen({super.key, this.onSwipeRight});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  AnimationController? _pulseController;
  AnimationController? _dotsController;

  // 多图预览
  final List<_PendingImage> _pendingImages = [];

  // 日程面板
  bool _showSchedule = false;
  bool _scheduleExpanded = false;

  // 语音录制中（用于上滑取消判断）
  bool _isVoiceRecording = false;
  double _voiceStartY = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    // 预请求麦克风权限
    _preRequestMicPermission();
  }

  Future<void> _preRequestMicPermission() async {
    try {
      await ref.read(chatMessagesProvider.notifier).checkMicPermission();
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    _dotsController?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
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

  void _send() {
    final text = _controller.text.trim();
    final hasImages = _pendingImages.isNotEmpty;

    if (text.isEmpty && !hasImages) return;

    final sendText = text.isEmpty ? '请分析这些图片' : text;
    final imagePaths = hasImages
        ? _pendingImages.map((img) => img.base64).toList()
        : null;

    _controller.clear();
    setState(() => _pendingImages.clear());

    ref.read(chatMessagesProvider.notifier).sendMessage(sendText, imagePaths: imagePaths);
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final notifier = ref.read(chatMessagesProvider.notifier);
    final base64 = await notifier.pickImage();
    if (base64 != null && mounted) {
      setState(() {
        _pendingImages.add(_PendingImage(base64: base64, name: '图片${_pendingImages.length + 1}'));
      });
      _focusNode.requestFocus();
    }
  }

  Future<void> _pickMultipleImages() async {
    final notifier = ref.read(chatMessagesProvider.notifier);
    final images = await notifier.pickMultipleImages();
    if (images.isNotEmpty && mounted) {
      setState(() {
        for (int i = 0; i < images.length; i++) {
          _pendingImages.add(_PendingImage(
            base64: images[i],
            name: '图片${_pendingImages.length + 1}',
          ));
        }
      });
      _focusNode.requestFocus();
    }
  }

  void _removeImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider);
    final config = ref.watch(apiConfigProvider);
    final isOnline = ref.watch(connectivityProvider).maybeWhen(
      data: (v) => v,
      orElse: () => true,
    );

    ref.listen(chatMessagesProvider, (prev, next) {
      _scrollToBottom();
    });

    return Stack(
      children: [
        Column(
          children: [
            if (!config.isConfigured) _buildConfigWarning(),
            if (!isOnline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                color: Colors.orange.withOpacity(0.15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Text('无网络连接，可查看已有对话', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                  ],
                ),
              ),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v < -300) {
                    setState(() => _showSchedule = true);
                  } else if (v > 300) {
                    widget.onSwipeRight?.call();
                  }
                },
                child: Container(
                  color: context.bubble,
                  child: messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          addAutomaticKeepAlives: false,
                          itemCount: messages.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _buildLoadMoreButton();
                            }
                            return _buildMessageBubble(messages[index - 1]);
                          },
                        ),
                ),
              ),
            ),
            _buildInputBar(),
          ],
        ),
        if (_showSchedule) _buildScheduleOverlay(),
        // 日程面板入口按钮
        if (!_showSchedule)
          Positioned(
            right: 8,
            bottom: 80,
            child: GestureDetector(
              onTap: () => setState(() => _showSchedule = true),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.bubble,
                  shape: BoxShape.circle,
                  border: Border.all(color: context.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadMoreButton() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextButton(
          onPressed: () => ref.read(chatMessagesProvider.notifier).loadMore(),
          child: Text('加载更多', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ),
      ),
    );
  }

  Widget _buildConfigWarning() {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('请先配置 API Key')),
          TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.school_outlined,
            size: 64,
            color: AppColors.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Macura',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: context.text.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '你的 AI 学习伙伴',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExamRecognitionScreen()),
              ),
              icon: const Icon(Icons.document_scanner_outlined, size: 20),
              label: const Text('试题拍照识别'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSuggestionChip('分析两套试题的知识点'),
          const SizedBox(height: 8),
          _buildSuggestionChip('制定复习计划'),
          const SizedBox(height: 8),
          _buildSuggestionChip('解释这个概念'),
        ],
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () {
        _controller.text = text;
        _send();
      },
      backgroundColor: context.surface,
      side: const BorderSide(color: AppColors.glassBorder),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildMessageBubble(Message msg) {
    final isUser = msg.role == MessageRole.user;
    final isSystem = msg.role == MessageRole.system;

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // 气泡
        GestureDetector(
          onLongPress: isSystem ? null : () => _showCopyMenu(msg),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSystem
                  ? Colors.orange.withOpacity(0.1)
                  : isUser
                      ? (context.isDark ? AppColors.primary.withOpacity(0.2) : AppColors.bubbleUser)
                      : context.bubble,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser
                  ? null
                  : Border.all(color: context.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isSystem)
                  Text(
                    msg.content,
                    style: const TextStyle(color: Colors.orange, fontSize: 13),
                  )
                else if (isUser)
                  Text(msg.content, style: const TextStyle(fontSize: 15))
                else if (msg.isStreaming && msg.content.isEmpty)
                  _buildTypingIndicator()
                else
                  MarkdownBody(
                    data: msg.content,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 15, height: 1.5),
                      code: TextStyle(
                        fontSize: 13,
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: AppColors.primary.withOpacity(0.5),
                            width: 3,
                          ),
                        ),
                      ),
                      h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (msg.isStreaming && msg.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _buildTypingIndicator(),
                  ),
              ],
            ),
          ),
        ),

        // 操作按钮（非系统消息）
        if (!isSystem && !msg.isStreaming)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 复制
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 14, color: AppColors.textSecondary.withOpacity(0.5)),
                      const SizedBox(width: 4),
                      Text('复制', style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.5))),
                    ],
                  ),
                ),
                // AI 回复可保存为知识卡片
                if (!isUser) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _showSaveAsKnowledgeCard(msg),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lightbulb_outline, size: 14, color: AppColors.textSecondary.withOpacity(0.5)),
                        const SizedBox(width: 4),
                        Text('保存', style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.5))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTypingIndicator() {
    return AnimatedBuilder(
      animation: _dotsController!,
      builder: (ctx, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.33;
            final t = (_dotsController!.value - delay) % 1.0;
            final opacity = t < 0.5 ? (t * 2) : (1 - (t - 0.5) * 2);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.3 + opacity.clamp(0, 1) * 0.5),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }

  void _showCopyMenu(Message msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy, color: AppColors.primary),
              title: const Text('复制全文'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg.content));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                );
              },
            ),
            if (msg.role == MessageRole.assistant)
              ListTile(
                leading: const Icon(Icons.copy_all, color: AppColors.primary),
                title: const Text('复制为纯文本'),
                onTap: () {
                  final plain = msg.content
                      .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
                      .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
                      .replaceAll(RegExp(r'`(.*?)`'), r'$1')
                      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
                      .replaceAll(RegExp(r'^#+\s', multiLine: true), '')
                      .replaceAll(RegExp(r'^\s*[-*]\s', multiLine: true), '');
                  Clipboard.setData(ClipboardData(text: plain.trim()));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制纯文本'), duration: Duration(seconds: 1)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showSaveAsKnowledgeCard(Message msg) {
    final subjects = ref.read(subjectsProvider);
    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建科目'), duration: Duration(seconds: 1)),
      );
      return;
    }

    // 提取标题（取第一行或前30字）
    final lines = msg.content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final defaultTitle = lines.isNotEmpty
        ? (lines.first.length > 30 ? '${lines.first.substring(0, 30)}...' : lines.first)
        : '来自对话的知识点';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('保存为知识卡片', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ...subjects.map((s) => ListTile(
              leading: Text(s.icon ?? '📚', style: const TextStyle(fontSize: 22)),
              title: Text(s.name),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(knowledgeCardsProvider(s.id).notifier).add(
                  title: defaultTitle,
                  content: msg.content,
                  source: 'chat',
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已保存到「${s.name}」'), duration: const Duration(seconds: 1)),
                  );
                }
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static const _quickPrompts = [
    '查看大学物理复习进度',
    '帮我制定学习计划',
    '总结今天的学习内容',
    '设置明天的待办事项',
    '解释一下这个概念',
  ];

  Widget _buildInputBar() {
    final isRecording = ref.watch(isRecordingProvider);

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: AppColors.glassBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 多图预览
          if (_pendingImages.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.image, color: AppColors.primary, size: 24),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => _removeImage(i),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 快捷提示词
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => ActionChip(
                  label: Text(_quickPrompts[i], style: TextStyle(fontSize: 12, color: AppColors.primary)),
                  backgroundColor: AppColors.primary.withOpacity(0.08),
                  side: BorderSide(color: AppColors.primary.withOpacity(0.2)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: () {
                    _controller.text = _quickPrompts[i];
                    _focusNode.requestFocus();
                  },
                ),
              ),
            ),
          ),

          // 语音胶囊按钮
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onLongPressStart: (details) async {
                _voiceStartY = details.globalPosition.dy;
                final notifier = ref.read(chatMessagesProvider.notifier);
                final started = await notifier.startVoiceRecording();
                if (started) {
                  _isVoiceRecording = true;
                  ref.read(isRecordingProvider.notifier).state = true;
                  _pulseController?.repeat(reverse: true);
                  HapticFeedback.mediumImpact();
                }
              },
              onLongPressMoveUpdate: (details) {
                if (!_isVoiceRecording) return;
                // 上滑超过 80px 提示取消
                final dy = _voiceStartY - details.globalPosition.dy;
                if (dy > 80) {
                  // 上滑取消区域
                  HapticFeedback.lightImpact();
                }
              },
              onLongPressEnd: (details) async {
                if (!_isVoiceRecording) return;
                _isVoiceRecording = false;
                ref.read(isRecordingProvider.notifier).state = false;
                _pulseController?.stop();
                HapticFeedback.lightImpact();

                // 判断是否上滑取消
                final dy = _voiceStartY - details.globalPosition.dy;
                if (dy > 80) {
                  // 取消录音
                  ref.read(chatMessagesProvider.notifier).cancelVoiceRecording();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已取消录音'), duration: Duration(seconds: 1)),
                    );
                  }
                } else {
                  await ref.read(chatMessagesProvider.notifier).stopVoiceRecordingAndSend();
                  _scrollToBottom();
                }
              },
              child: AnimatedBuilder(
                animation: _pulseController!,
                builder: (ctx, child) {
                  final pulse = isRecording ? _pulseController!.value : 0.0;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: isRecording ? Colors.red.shade50 : AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isRecording ? Colors.red.shade300 : AppColors.primary.withOpacity(0.2),
                      ),
                      boxShadow: isRecording
                          ? [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.15 + pulse * 0.2),
                                blurRadius: 6 + pulse * 8,
                                spreadRadius: pulse * 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRecording ? Icons.stop_circle_outlined : Icons.mic,
                          size: 16,
                          color: isRecording ? Colors.red : AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isRecording ? '上滑取消 · 松开发送' : '长按语音输入',
                          style: TextStyle(
                            fontSize: 13,
                            color: isRecording ? Colors.red : AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // 输入行
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 图片按钮
                Container(
                  margin: const EdgeInsets.only(left: 4, bottom: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: GestureDetector(
                    onLongPress: _pickMultipleImages,
                    child: IconButton(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image_outlined, size: 20),
                      color: AppColors.primary,
                      tooltip: '单击选一张，长按多选',
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),

                // 输入框
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 140),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: '输入消息...',
                        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),

                // 发送按钮
                Container(
                  margin: const EdgeInsets.only(right: 2, bottom: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    color: Colors.white,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleOverlay() {
    final screenWidth = MediaQuery.of(context).size.width;
    final panelWidth = _scheduleExpanded ? screenWidth * 0.85 : screenWidth * 0.60;

    return GestureDetector(
      onTap: () => setState(() {
        _showSchedule = false;
        _scheduleExpanded = false;
      }),
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {},
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                setState(() {
                  _showSchedule = false;
                  _scheduleExpanded = false;
                });
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: panelWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(-4, 0),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 展开/收起按钮
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: Icon(
                        _scheduleExpanded ? Icons.chevron_right : Icons.chevron_left,
                        size: 20,
                        color: context.textSec,
                      ),
                      onPressed: () => setState(() => _scheduleExpanded = !_scheduleExpanded),
                      tooltip: _scheduleExpanded ? '收起' : '展开',
                    ),
                  ),
                  Expanded(
                    child: SchedulePanel(
                      compact: !_scheduleExpanded,
                      isEmbedded: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingImage {
  final String base64;
  final String name;
  const _PendingImage({required this.base64, required this.name});
}

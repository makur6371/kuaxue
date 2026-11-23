import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/review_card.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  final String? subjectId;
  final String? subjectName;

  const ReviewScreen({super.key, this.subjectId, this.subjectName});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  List<ReviewCard> _cards = [];
  int _currentIndex = 0;
  bool _showAnswer = false;
  int _rated = 0; // 已评分数
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
    _loadCards();
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  Future<void> _loadCards() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(reviewServiceProvider);
      final cards = await service.getDueCards(subjectId: widget.subjectId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  void _flipCard() {
    if (_showAnswer) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _showAnswer = !_showAnswer);
  }

  Future<void> _rate(int rating) async {
    if (_currentIndex >= _cards.length) return;
    final card = _cards[_currentIndex];
    await ref.read(reviewCardsProvider.notifier).review(card.id, rating);
    setState(() {
      _rated++;
      _showAnswer = false;
    });
    _flipController.reverse();

    if (_currentIndex < _cards.length - 1) {
      setState(() => _currentIndex++);
    } else {
      // 全部复习完成
      _showComplete();
    }
  }

  void _showComplete() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              '今日复习完成！',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '共复习 $_rated 张卡片',
              style: TextStyle(fontSize: 15, color: context.textSec),
            ),
            const SizedBox(height: 4),
            Text(
              '间隔重复让记忆更持久 💪',
              style: TextStyle(fontSize: 13, color: context.textSec),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.subjectName != null
        ? '${widget.subjectName} - 复习'
        : '智能复习';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_cards.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_currentIndex + 1} / ${_cards.length}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.textSec,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _cards.isEmpty
                  ? _buildEmpty()
                  : _buildReviewBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: context.textSec)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadCards, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_outlined, size: 64, color: AppColors.primary.withOpacity(0.5)),
          const SizedBox(height: 16),
          const Text(
            '暂无待复习卡片',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '在对话中对 AI 说\n"帮我把知识点加入复习"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: context.textSec.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewBody() {
    final card = _cards[_currentIndex];
    final progress = _cards.isEmpty ? 0.0 : (_currentIndex + 1) / _cards.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 24),
          // 卡片
          Expanded(
            child: GestureDetector(
              onTap: _flipCard,
              child: AnimatedBuilder(
                animation: _flipAnimation,
                builder: (context, child) {
                  final angle = _flipAnimation.value * pi;
                  final isFront = angle < pi / 2;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: isFront
                        ? _buildCardFront(card)
                        : Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..rotateY(pi),
                            child: _buildCardBack(card),
                          ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 操作提示
          if (!_showAnswer)
            Text(
              '点击卡片查看答案',
              style: TextStyle(
                fontSize: 13,
                color: context.textSec.withOpacity(0.6),
              ),
            ),
          // 评分按钮
          if (_showAnswer) _buildRatingButtons(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCardFront(ReviewCard card) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.bubble,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 来源标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _sourceLabel(card.source),
              style: TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // 标题
          Text(
            card.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // 内容预览（前几行）
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                card.content,
                style: TextStyle(
                  fontSize: 15,
                  color: context.textSec,
                  height: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Icon(
            Icons.touch_app,
            size: 20,
            color: context.textSec.withOpacity(0.4),
          ),
        ],
      ),
    );
  }

  Widget _buildCardBack(ReviewCard card) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.05),
            AppColors.primary.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            card.title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 40,
            height: 2,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.4),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                card.content,
                style: TextStyle(
                  fontSize: 15,
                  color: context.text,
                  height: 1.7,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingButtons() {
    return Column(
      children: [
        Text(
          '你记住了多少？',
          style: TextStyle(
            fontSize: 13,
            color: context.textSec,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _ratingBtn(1, '忘了', Colors.redAccent, Icons.close)),
            const SizedBox(width: 8),
            Expanded(child: _ratingBtn(2, '模糊', Colors.orange, Icons.help_outline)),
            const SizedBox(width: 8),
            Expanded(child: _ratingBtn(3, '记得', Colors.green, Icons.check)),
            const SizedBox(width: 8),
            Expanded(child: _ratingBtn(4, '很熟', AppColors.primary, Icons.star)),
          ],
        ),
      ],
    );
  }

  Widget _ratingBtn(int rating, String label, Color color, IconData icon) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _rate(rating),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'exam':
        return '📝 试题';
      case 'chat':
        return '💬 对话';
      default:
        return '✍️ 手动';
    }
  }
}

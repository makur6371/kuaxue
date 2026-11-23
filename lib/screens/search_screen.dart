import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'knowledge_card_edit_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  late TabController _tabCtrl;

  String _query = '';
  List<Message> _chatResults = [];
  List<Map<String, dynamic>> _cardResults = [];
  List<dynamic> _docResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _query = query.trim();
    });

    final db = ref.read(databaseServiceProvider);
    final results = await Future.wait([
      db.searchChatMessages(_query),
      db.searchKnowledgeCards(_query),
      db.searchDocuments(_query),
    ]);

    if (mounted) {
      setState(() {
        _chatResults = results[0] as List<Message>;
        _cardResults = results[1] as List<Map<String, dynamic>>;
        _docResults = results[2] as List<dynamic>;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: '搜索对话、知识卡片、文档...',
            hintStyle: TextStyle(color: context.textSec.withOpacity(0.5)),
            border: InputBorder.none,
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _query = '';
                        _chatResults = [];
                        _cardResults = [];
                        _docResults = [];
                      });
                    },
                  )
                : null,
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          onChanged: (v) => setState(() {}),
        ),
      ),
      body: _query.isEmpty
          ? _buildEmptyState()
          : _searching
              ? const Center(child: CircularProgressIndicator())
              : _buildResults(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: context.textSec.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('输入关键词搜索', style: TextStyle(fontSize: 15, color: context.textSec)),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final total = _chatResults.length + _cardResults.length + _docResults.length;
    if (total == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: context.textSec.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('未找到「$_query」相关结果', style: TextStyle(fontSize: 15, color: context.textSec)),
          ],
        ),
      );
    }

    return Column(
      children: [
        TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.textSec,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: '对话 (${_chatResults.length})'),
            Tab(text: '知识卡片 (${_cardResults.length})'),
            Tab(text: '文档 (${_docResults.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildChatResults(),
              _buildCardResults(),
              _buildDocResults(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatResults() {
    if (_chatResults.isEmpty) {
      return Center(child: Text('无对话结果', style: TextStyle(color: context.textSec)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _chatResults.length,
      itemBuilder: (ctx, i) {
        final msg = _chatResults[i];
        final isUser = msg.role == MessageRole.user;
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isUser ? Icons.person : Icons.smart_toy,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isUser ? '你' : 'AI',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(msg.createdAt),
                    style: TextStyle(fontSize: 11, color: context.textSec),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                msg.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.text, height: 1.4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardResults() {
    if (_cardResults.isEmpty) {
      return Center(child: Text('无知识卡片结果', style: TextStyle(color: context.textSec)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _cardResults.length,
      itemBuilder: (ctx, i) {
        final card = _cardResults[i];
        final subjectId = card['subject_id'] as String;
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => KnowledgeCardEditScreen(
                    subjectId: subjectId,
                    card: () {
                      final cards = ref.read(knowledgeCardsProvider(subjectId));
                      if (cards.isEmpty) return null;
                      return cards.firstWhere(
                        (c) => c.id == card['id'],
                        orElse: () => cards.first,
                      );
                    }(),
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        card['title'] as String,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  card['content'] as String,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.textSec, height: 1.4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDocResults() {
    if (_docResults.isEmpty) {
      return Center(child: Text('无文档结果', style: TextStyle(color: context.textSec)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _docResults.length,
      itemBuilder: (ctx, i) {
        final doc = _docResults[i];
        return GlassCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(doc.typeIcon, style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (doc.description != null && doc.description!.isNotEmpty)
                      Text(
                        doc.description!,
                        style: TextStyle(fontSize: 12, color: context.textSec),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month}/${dt.day}';
  }
}

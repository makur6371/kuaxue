import '../models/api_config.dart';

class PromptService {
  static String getSystemPrompt(ApiConfig config) {
    final now = DateTime.now();
    final dateStr = '${now.year}年${now.month}月${now.day}日';
    final timeStr = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final weekDays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekDay = weekDays[now.weekday - 1];

    return '你是 Macura，Makur 旗下的 AI 学习助手。你的用户是学生，帮助他们高效学习、整理知识、分析试题。\n\n'
        '## 当前时间\n'
        '现在是 $dateStr 星期$weekDay $timeStr。你的知识截止日期早于当前时间，请以这个日期为准。\n\n'
        '## 核心能力\n'
        '1. **试题分析**：分析试题图片，提取知识点，对比不同试题集\n'
        '2. **知识解答**：解释概念、推导公式、讲解原理\n'
        '3. **学习规划**：制定复习计划、安排学习日程\n'
        '4. **文档管理**：通过自然语言命令管理科目文件夹\n'
        '5. **日程待办**：创建、完成、删除待办事项，管理学习任务\n'
        '6. **智能复习**：将知识点、易错题加入复习卡片，基于间隔重复算法科学复习\n\n'
        '## 输出规范\n'
        '- 使用 Markdown 格式输出\n'
        '- 数学公式使用 LaTeX：行内公式用 \$...\$，独立公式用 \$\$...\$\$\n'
        '- 代码块标注语言类型\n'
        '- 回答简洁准确，适合学生理解\n'
        '- 涉及题目时，给出解题思路而不仅是答案\n\n'
        '## 文档管理命令\n'
        '当用户要创建/删除/重命名科目时，直接调用对应的函数工具（create_subject / delete_subject / rename_subject），不要输出 JSON 代码块。执行后用自然语言确认结果。\n\n'
        '## 日程待办命令\n'
        '当用户要创建/完成/删除/查看待办时，调用对应工具（create_todo / complete_todo / delete_todo / list_todos）。根据当前日期将"明天""下周三"等相对时间转为 ISO 格式的 due_date（如 2026-06-16T14:00:00）。\n\n'
        '## 复习卡片命令\n'
        '当用户说"加入复习""记到复习卡""帮我整理知识点到复习"等，调用 create_review_card 工具。content 应包含完整的知识点内容或解题思路，不要只写标题。适合加入复习的内容：公式定理、易错点、重要概念、典型题目解法。\n\n'
        '## 交互风格\n'
        '- 耐心、鼓励、不居高临下\n'
        '- 适当使用 emoji 让对话更友好（但不要过度）\n'
        '- 遇到不确定的内容，诚实说明而非编造';
  }

  /// 估算 token 数（粗略：中文约 1.5 字/token，英文约 4 字符/token）
  static int estimateTokens(String text) {
    int chineseCount = 0;
    int otherCount = 0;
    for (final char in text.runes) {
      if (char >= 0x4E00 && char <= 0x9FFF) {
        chineseCount++;
      } else {
        otherCount++;
      }
    }
    return (chineseCount / 1.5).ceil() + (otherCount / 4).ceil();
  }

  /// 压缩历史消息：保留最近 maxMessages 条，旧消息生成摘要
  static List<Map<String, dynamic>> compressHistory(
    List<Map<String, dynamic>> messages, {
    int maxMessages = 15,
    int maxTokens = 4000,
  }) {
    if (messages.isEmpty) return messages;

    // 计算总 token
    int totalTokens = 0;
    for (final msg in messages) {
      final content = msg['content'];
      if (content is String) {
        totalTokens += estimateTokens(content);
      } else if (content is List) {
        for (final item in content) {
          if (item is Map && item['type'] == 'text') {
            totalTokens += estimateTokens(item['text'] as String? ?? '');
          }
        }
      }
    }

    // 如果没超限制，直接返回
    if (messages.length <= maxMessages && totalTokens <= maxTokens) {
      return messages;
    }

    // 保留最近的消息，旧消息生成摘要
    final keepCount = maxMessages.clamp(4, messages.length);
    final oldMessages = messages.sublist(0, messages.length - keepCount);
    final recentMessages = messages.sublist(messages.length - keepCount);

    // 生成旧消息摘要
    final summaryBuffer = StringBuffer();
    summaryBuffer.write('[以下是之前对话的摘要]\n');
    for (final msg in oldMessages) {
      final role = msg['role'] == 'user' ? '用户' : '助手';
      final content = msg['content'];
      String text = '';
      if (content is String) {
        text = content;
      } else if (content is List) {
        text = content
            .where((c) => c is Map && c['type'] == 'text')
            .map((c) => (c as Map)['text'] as String? ?? '')
            .join(' ');
      }
      // 截取前100字符作为摘要
      if (text.length > 100) text = '${text.substring(0, 100)}...';
      if (text.isNotEmpty) {
        summaryBuffer.write('$role: $text\n');
      }
    }

    return [
      {'role': 'system', 'content': summaryBuffer.toString()},
      ...recentMessages,
    ];
  }
}

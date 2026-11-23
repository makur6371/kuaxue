import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database_service.dart';

class ExportService {
  final DatabaseService _db;
  ExportService(this._db);

  Future<File> exportKnowledgeCards(String subjectId, String subjectName) async {
    final cards = await _db.getKnowledgeCards(subjectId);

    final buffer = StringBuffer();
    buffer.writeln('# $subjectName - 知识卡片');
    buffer.writeln();
    buffer.writeln('导出时间: ${DateTime.now()}');
    buffer.writeln('卡片数量: ${cards.length}');
    buffer.writeln();

    for (final card in cards) {
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('## ${card['title']}');
      buffer.writeln();
      if (card['tags'] != null) {
        final tags = List<String>.from(jsonDecode(card['tags'] as String));
        if (tags.isNotEmpty) {
          buffer.writeln('标签: ${tags.join(', ')}');
          buffer.writeln();
        }
      }
      buffer.writeln(card['content']);
      buffer.writeln();
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/macura_${subjectName}_知识卡片.md');
    await file.writeAsString(buffer.toString(), encoding: utf8);
    return file;
  }

  Future<File> exportChatHistory() async {
    final messages = await _db.getChatMessages();

    final data = {
      'app': 'Macura',
      'exported_at': DateTime.now().toIso8601String(),
      'message_count': messages.length,
      'messages': messages.map((m) => {
        'role': m.role.name,
        'content': m.content,
        'created_at': m.createdAt.toIso8601String(),
      }).toList(),
    };

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/macura_chat_history.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
    );
    return file;
  }

  Future<File> exportAll() async {
    final subjects = await _db.getSubjects();
    final messages = await _db.getChatMessages();
    final todos = await _db.getTodos();

    final allCards = <Map<String, dynamic>>[];
    for (final s in subjects) {
      final cards = await _db.getKnowledgeCards(s.id);
      for (final c in cards) {
        allCards.add({...c, 'subject_name': s.name});
      }
    }

    final data = {
      'app': 'Macura',
      'exported_at': DateTime.now().toIso8601String(),
      'subjects': subjects.map((s) => {
        'id': s.id,
        'name': s.name,
        'icon': s.icon,
        'color': s.color,
      }).toList(),
      'chat_messages': messages.map((m) => {
        'role': m.role.name,
        'content': m.content,
        'created_at': m.createdAt.toIso8601String(),
      }).toList(),
      'knowledge_cards': allCards,
      'todos': todos.map((t) => {
        'title': t.title,
        'is_done': t.isDone,
        'due_date': t.dueDate?.toIso8601String(),
        'priority': t.priority,
      }).toList(),
    };

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/macura_backup.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
    );
    return file;
  }

  Future<void> shareFile(File file) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Macura 数据导出',
    );
  }
}

class KnowledgeCard {
  final String id;
  final String subjectId;
  final String title;
  final String content;
  final List<String> tags;
  final String source; // 'manual', 'chat', 'ai'
  final DateTime createdAt;
  final DateTime updatedAt;

  const KnowledgeCard({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.content,
    this.tags = const [],
    this.source = 'manual',
    required this.createdAt,
    required this.updatedAt,
  });

  KnowledgeCard copyWith({
    String? id,
    String? subjectId,
    String? title,
    String? content,
    List<String>? tags,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KnowledgeCard(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

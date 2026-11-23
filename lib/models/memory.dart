class Memory {
  final String id;
  final String type; // 'conversation_summary', 'document_chunk', 'reflection'
  final String content;
  final String? subjectId;
  final String? metadata; // JSON string for extra data
  final List<double> embedding;
  final DateTime createdAt;

  Memory({
    required this.id,
    required this.type,
    required this.content,
    this.subjectId,
    this.metadata,
    required this.embedding,
    required this.createdAt,
  });
}

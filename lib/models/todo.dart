import 'package:json_annotation/json_annotation.dart';

part 'todo.g.dart';

@JsonSerializable()
class Todo {
  final String id;
  final String title;
  final String? description;
  final DateTime? dueDate;
  final bool isDone;
  final int priority; // 0=普通, 1=重要, 2=紧急
  final String? subjectId;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Todo({
    required this.id,
    required this.title,
    this.description,
    this.dueDate,
    this.isDone = false,
    this.priority = 0,
    this.subjectId,
    required this.createdAt,
    this.completedAt,
  });

  Todo copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? dueDate,
    bool? isDone,
    int? priority,
    String? subjectId,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dueDate: dueDate ?? this.dueDate,
      isDone: isDone ?? this.isDone,
      priority: priority ?? this.priority,
      subjectId: subjectId ?? this.subjectId,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  factory Todo.fromJson(Map<String, dynamic> json) => _$TodoFromJson(json);
  Map<String, dynamic> toJson() => _$TodoToJson(this);
}

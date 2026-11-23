import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

enum MessageRole { user, assistant, system }

enum ContentType { text, markdown, html, json, image, toolCall, toolResult }

@JsonSerializable()
class Message {
  final String id;
  final MessageRole role;
  final String content;
  final ContentType contentType;
  final List<String>? imagePaths;
  final DateTime createdAt;
  final String? toolName;
  final Map<String, dynamic>? toolResult;
  final bool isStreaming;

  const Message({
    required this.id,
    required this.role,
    required this.content,
    this.contentType = ContentType.markdown,
    this.imagePaths,
    required this.createdAt,
    this.toolName,
    this.toolResult,
    this.isStreaming = false,
  });

  Message copyWith({
    String? id,
    MessageRole? role,
    String? content,
    ContentType? contentType,
    List<String>? imagePaths,
    DateTime? createdAt,
    String? toolName,
    Map<String, dynamic>? toolResult,
    bool? isStreaming,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      imagePaths: imagePaths ?? this.imagePaths,
      createdAt: createdAt ?? this.createdAt,
      toolName: toolName ?? this.toolName,
      toolResult: toolResult ?? this.toolResult,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);

  Map<String, dynamic> toJson() => _$MessageToJson(this);
}

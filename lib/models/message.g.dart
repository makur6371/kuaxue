// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
  id: json['id'] as String,
  role: $enumDecode(_$MessageRoleEnumMap, json['role']),
  content: json['content'] as String,
  contentType:
      $enumDecodeNullable(_$ContentTypeEnumMap, json['contentType']) ??
      ContentType.markdown,
  imagePaths: (json['imagePaths'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  createdAt: DateTime.parse(json['createdAt'] as String),
  toolName: json['toolName'] as String?,
  toolResult: json['toolResult'] as Map<String, dynamic>?,
  isStreaming: json['isStreaming'] as bool? ?? false,
);

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
  'id': instance.id,
  'role': _$MessageRoleEnumMap[instance.role]!,
  'content': instance.content,
  'contentType': _$ContentTypeEnumMap[instance.contentType]!,
  'imagePaths': instance.imagePaths,
  'createdAt': instance.createdAt.toIso8601String(),
  'toolName': instance.toolName,
  'toolResult': instance.toolResult,
  'isStreaming': instance.isStreaming,
};

const _$MessageRoleEnumMap = {
  MessageRole.user: 'user',
  MessageRole.assistant: 'assistant',
  MessageRole.system: 'system',
};

const _$ContentTypeEnumMap = {
  ContentType.text: 'text',
  ContentType.markdown: 'markdown',
  ContentType.html: 'html',
  ContentType.json: 'json',
  ContentType.image: 'image',
  ContentType.toolCall: 'toolCall',
  ContentType.toolResult: 'toolResult',
};

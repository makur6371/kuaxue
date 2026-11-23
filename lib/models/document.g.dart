// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppDocument _$AppDocumentFromJson(Map<String, dynamic> json) => AppDocument(
  id: json['id'] as String,
  name: json['name'] as String,
  type: json['type'] as String,
  subjectId: json['subjectId'] as String,
  filePath: json['filePath'] as String,
  thumbnailPath: json['thumbnailPath'] as String?,
  fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
  description: json['description'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$AppDocumentToJson(AppDocument instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': instance.type,
      'subjectId': instance.subjectId,
      'filePath': instance.filePath,
      'thumbnailPath': instance.thumbnailPath,
      'fileSize': instance.fileSize,
      'description': instance.description,
      'createdAt': instance.createdAt.toIso8601String(),
    };

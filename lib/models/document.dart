import 'package:json_annotation/json_annotation.dart';

part 'document.g.dart';

@JsonSerializable()
class AppDocument {
  final String id;
  final String name;
  final String type; // 'image', 'pdf', 'ppt', 'note', 'exam'
  final String subjectId;
  final String filePath;
  final String? thumbnailPath;
  final int fileSize;
  final String? description;
  final DateTime createdAt;

  const AppDocument({
    required this.id,
    required this.name,
    required this.type,
    required this.subjectId,
    required this.filePath,
    this.thumbnailPath,
    this.fileSize = 0,
    this.description,
    required this.createdAt,
  });

  AppDocument copyWith({
    String? id,
    String? name,
    String? type,
    String? subjectId,
    String? filePath,
    String? thumbnailPath,
    int? fileSize,
    String? description,
    DateTime? createdAt,
  }) {
    return AppDocument(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      subjectId: subjectId ?? this.subjectId,
      filePath: filePath ?? this.filePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      fileSize: fileSize ?? this.fileSize,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory AppDocument.fromJson(Map<String, dynamic> json) => _$AppDocumentFromJson(json);
  Map<String, dynamic> toJson() => _$AppDocumentToJson(this);

  String get typeLabel {
    switch (type) {
      case 'image': return '图片';
      case 'pdf': return 'PDF';
      case 'ppt': case 'pptx': return 'PPT';
      case 'doc': case 'docx': return 'Word';
      case 'xls': case 'xlsx': return 'Excel';
      case 'txt': return '文本';
      case 'zip': case 'rar': return '压缩包';
      case 'note': return '笔记';
      case 'exam': return '试题';
      default: return '文件';
    }
  }

  String get typeIcon {
    switch (type) {
      case 'image': return '🖼️';
      case 'pdf': return '📄';
      case 'ppt': case 'pptx': return '📊';
      case 'doc': case 'docx': return '📃';
      case 'xls': case 'xlsx': return '📈';
      case 'txt': return '📝';
      case 'zip': case 'rar': return '📦';
      case 'note': return '📝';
      case 'exam': return '📋';
      default: return '📎';
    }
  }
}

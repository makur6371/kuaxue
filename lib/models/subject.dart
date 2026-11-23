import 'package:json_annotation/json_annotation.dart';

part 'subject.g.dart';

@JsonSerializable()
class Subject {
  final String id;
  final String name;
  final String? icon;
  final String? color;
  final int sortOrder;
  final DateTime createdAt;

  const Subject({
    required this.id,
    required this.name,
    this.icon,
    this.color,
    this.sortOrder = 0,
    required this.createdAt,
  });

  Subject copyWith({
    String? id,
    String? name,
    String? icon,
    String? color,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Subject.fromJson(Map<String, dynamic> json) => _$SubjectFromJson(json);
  Map<String, dynamic> toJson() => _$SubjectToJson(this);
}

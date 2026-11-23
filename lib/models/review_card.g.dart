// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_card.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReviewCard _$ReviewCardFromJson(Map<String, dynamic> json) => ReviewCard(
  id: json['id'] as String,
  title: json['title'] as String,
  content: json['content'] as String,
  subjectId: json['subjectId'] as String?,
  source: json['source'] as String? ?? 'manual',
  easeFactor: (json['easeFactor'] as num?)?.toDouble() ?? 2.5,
  interval: (json['interval'] as num?)?.toInt() ?? 0,
  repetitions: (json['repetitions'] as num?)?.toInt() ?? 0,
  nextReview: DateTime.parse(json['nextReview'] as String),
  createdAt: DateTime.parse(json['createdAt'] as String),
  lastReviewedAt: json['lastReviewedAt'] == null
      ? null
      : DateTime.parse(json['lastReviewedAt'] as String),
);

Map<String, dynamic> _$ReviewCardToJson(ReviewCard instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'content': instance.content,
      'subjectId': instance.subjectId,
      'source': instance.source,
      'easeFactor': instance.easeFactor,
      'interval': instance.interval,
      'repetitions': instance.repetitions,
      'nextReview': instance.nextReview.toIso8601String(),
      'createdAt': instance.createdAt.toIso8601String(),
      'lastReviewedAt': instance.lastReviewedAt?.toIso8601String(),
    };

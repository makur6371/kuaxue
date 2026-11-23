import 'package:json_annotation/json_annotation.dart';

part 'review_card.g.dart';

@JsonSerializable()
class ReviewCard {
  final String id;
  final String title;
  final String content;
  final String? subjectId;
  final String source; // 'exam', 'chat', 'manual'
  final double easeFactor;
  final int interval; // 天数
  final int repetitions;
  final DateTime nextReview;
  final DateTime createdAt;
  final DateTime? lastReviewedAt;

  const ReviewCard({
    required this.id,
    required this.title,
    required this.content,
    this.subjectId,
    this.source = 'manual',
    this.easeFactor = 2.5,
    this.interval = 0,
    this.repetitions = 0,
    required this.nextReview,
    required this.createdAt,
    this.lastReviewedAt,
  });

  ReviewCard copyWith({
    String? id,
    String? title,
    String? content,
    String? subjectId,
    String? source,
    double? easeFactor,
    int? interval,
    int? repetitions,
    DateTime? nextReview,
    DateTime? createdAt,
    DateTime? lastReviewedAt,
  }) {
    return ReviewCard(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      subjectId: subjectId ?? this.subjectId,
      source: source ?? this.source,
      easeFactor: easeFactor ?? this.easeFactor,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
      nextReview: nextReview ?? this.nextReview,
      createdAt: createdAt ?? this.createdAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
    );
  }

  factory ReviewCard.fromJson(Map<String, dynamic> json) => _$ReviewCardFromJson(json);
  Map<String, dynamic> toJson() => _$ReviewCardToJson(this);
}

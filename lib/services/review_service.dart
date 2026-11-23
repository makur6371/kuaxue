import 'package:uuid/uuid.dart';
import '../models/review_card.dart';
import 'database_service.dart';

class ReviewService {
  final DatabaseService _db;

  ReviewService(this._db);

  /// SM-2 算法：根据用户评分更新复习卡片
  /// rating: 1=忘了 2=模糊 3=记得 4=很熟
  ReviewCard review(ReviewCard card, int rating) {
    double easeFactor = card.easeFactor;
    int interval = card.interval;
    int repetitions = card.repetitions;

    if (rating < 3) {
      // 忘了或模糊 → 重置
      repetitions = 0;
      interval = 1;
    } else {
      // 记得或很熟 → 递增
      if (repetitions == 0) {
        interval = 1;
      } else if (repetitions == 1) {
        interval = 3;
      } else {
        interval = (interval * easeFactor).round();
      }
      repetitions++;
    }

    // 更新 easeFactor
    easeFactor += 0.1 - (4 - rating) * (0.08 + (4 - rating) * 0.02);
    if (easeFactor < 1.3) easeFactor = 1.3;

    final now = DateTime.now();
    final nextReview = now.add(Duration(days: interval));

    return card.copyWith(
      easeFactor: easeFactor,
      interval: interval,
      repetitions: repetitions,
      nextReview: nextReview,
      lastReviewedAt: now,
    );
  }

  /// 创建复习卡片
  Future<ReviewCard> createCard({
    required String title,
    required String content,
    String? subjectId,
    String source = 'manual',
  }) async {
    final card = ReviewCard(
      id: const Uuid().v4(),
      title: title,
      content: content,
      subjectId: subjectId,
      source: source,
      nextReview: DateTime.now(), // 新卡片立即可复习
      createdAt: DateTime.now(),
    );
    await _db.insertReviewCard(card);
    return card;
  }

  /// 获取今日到期的复习卡片
  Future<List<ReviewCard>> getDueCards({String? subjectId}) async {
    return _db.getDueReviewCards(subjectId: subjectId);
  }

  /// 获取所有复习卡片
  Future<List<ReviewCard>> getAllCards() async {
    return _db.getReviewCards();
  }

  /// 更新卡片（复习后）
  Future<void> updateCard(ReviewCard card) async {
    await _db.updateReviewCard(card);
  }

  /// 删除卡片
  Future<void> deleteCard(String id) async {
    await _db.deleteReviewCard(id);
  }

  /// 获取统计信息
  Future<ReviewStats> getStats({String? subjectId}) async {
    final all = await _db.getReviewCards();
    final filtered = subjectId != null
        ? all.where((c) => c.subjectId == subjectId).toList()
        : all;
    final due = filtered.where((c) => !c.nextReview.isAfter(DateTime.now())).toList();
    final mastered = filtered.where((c) => c.repetitions >= 5 && c.easeFactor >= 2.3).toList();

    return ReviewStats(
      total: filtered.length,
      due: due.length,
      mastered: mastered.length,
    );
  }
}

class ReviewStats {
  final int total;
  final int due;
  final int mastered;
  const ReviewStats({required this.total, required this.due, required this.mastered});
}

class ClassroomLesson {
  final String id;
  final String topic;
  final String? subjectId;
  final List<ClassroomScene> scenes;
  final ClassroomStatus status;
  final DateTime createdAt;

  ClassroomLesson({
    required this.id,
    required this.topic,
    this.subjectId,
    required this.scenes,
    this.status = ClassroomStatus.outline,
    required this.createdAt,
  });

  ClassroomLesson copyWith({
    List<ClassroomScene>? scenes,
    ClassroomStatus? status,
  }) {
    return ClassroomLesson(
      id: id,
      topic: topic,
      subjectId: subjectId,
      scenes: scenes ?? this.scenes,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}

enum ClassroomStatus { outline, teaching, quiz, done }

class ClassroomScene {
  final String title;
  final String content;
  final List<StudentQuestion> studentQuestions;
  final ClassroomQuiz? quiz;

  ClassroomScene({
    required this.title,
    this.content = '',
    this.studentQuestions = const [],
    this.quiz,
  });

  ClassroomScene copyWith({
    String? content,
    List<StudentQuestion>? studentQuestions,
    ClassroomQuiz? quiz,
  }) {
    return ClassroomScene(
      title: title,
      content: content ?? this.content,
      studentQuestions: studentQuestions ?? this.studentQuestions,
      quiz: quiz ?? this.quiz,
    );
  }
}

class StudentQuestion {
  final String name;
  final String question;
  final String answer;

  StudentQuestion({
    required this.name,
    required this.question,
    this.answer = '',
  });
}

class ClassroomQuiz {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  ClassroomQuiz({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });
}

/// 流式输出的课堂内容块类型
sealed class ClassroomChunk {
  const ClassroomChunk();
}

class TeachChunk extends ClassroomChunk {
  final String text;
  const TeachChunk(this.text);
}

class StudentAskChunk extends ClassroomChunk {
  final String name;
  final String question;
  const StudentAskChunk({required this.name, required this.question});
}

class StudentAnswerChunk extends ClassroomChunk {
  final String text;
  const StudentAnswerChunk(this.text);
}

class QuizChunk extends ClassroomChunk {
  final ClassroomQuiz quiz;
  const QuizChunk(this.quiz);
}

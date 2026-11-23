import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/api_config.dart';
import '../models/classroom.dart';
import 'retry_interceptor.dart';

class ClassroomService {
  final Dio _dio = Dio();

  ClassroomService() {
    _dio.interceptors.add(RetryInterceptor(dio: _dio));
  }

  /// 生成课程大纲（3-5 个知识点）
  Future<List<ClassroomScene>> generateOutline({
    required ApiConfig config,
    required String topic,
    String? documentContent,
  }) async {
    final contentHint = documentContent != null
        ? '\n\n以下是参考文档内容（从中提取知识点）：\n${documentContent.length > 3000 ? documentContent.substring(0, 3000) : documentContent}'
        : '';

    final response = await _dio.post(
      '${config.baseUrl}/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'model': config.chatModel,
        'messages': [
          {
            'role': 'system',
            'content': '你是一个课程规划助手。根据用户给出的学习主题，生成 3-5 个知识点的课程大纲。'
                '严格以 JSON 数组格式输出，每个元素包含 title 字段。不要输出任何其他内容。'
                '\n\n示例输出：\n[{"title":"导数的定义"},{"title":"导数的几何意义"},{"title":"基本求导公式"}]',
          },
          {
            'role': 'user',
            'content': '请为「$topic」生成课程大纲。$contentHint',
          },
        ],
        'max_tokens': 1024,
        'temperature': 0.7,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final text = (data['choices'][0]['message']['content'] as String).trim();

    // 提取 JSON（可能被 markdown 代码块包裹）
    String jsonStr = text;
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (jsonMatch != null) {
      jsonStr = jsonMatch.group(0)!;
    }

    final List<dynamic> arr = jsonDecode(jsonStr);
    return arr.map((item) {
      final map = item as Map<String, dynamic>;
      return ClassroomScene(title: map['title'] as String);
    }).toList();
  }

  /// 流式讲解单个知识点，输出 ClassroomChunk 流
  Stream<ClassroomChunk> teachScene({
    required ApiConfig config,
    required ClassroomScene scene,
    required String topic,
    List<Map<String, dynamic>> conversationHistory = const [],
  }) async* {
    final controller = StreamController<ClassroomChunk>();

    final messages = [
      {
        'role': 'system',
        'content': '你是一个生动的课堂讲解系统。你的课堂主题是「$topic」。'
            '现在请讲解知识点：「${scene.title}」\n\n'
            '## 输出要求\n'
            '1. 先用老师身份讲解核心内容（用 Markdown，含公式用 LaTeX）\n'
            '2. 讲解完一段后，模拟 1-2 个学生的提问\n'
            '3. 老师回答学生的问题\n'
            '4. 最后出一道选择题测验\n\n'
            '## 输出格式（严格遵守）\n'
            '用以下标记分隔不同内容块，每个标记独占一行：\n\n'
            '[TEACH]\n讲解内容（Markdown 格式）\n\n'
            '[STUDENT:小明]\n学生的提问内容\n\n'
            '[ANSWER]\n老师对学生的回答\n\n'
            '[STUDENT:小红]\n另一个学生的提问\n\n'
            '[ANSWER]\n老师的回答\n\n'
            '[QUIZ]\n题目：{question}\nA. {option1}\nB. {option2}\nC. {option3}\nD. {option4}\n答案：{A/B/C/D}\n解析：{explanation}\n\n'
            '注意：\n- [TEACH] 块可以有多个，用于分段讲解\n- [STUDENT:名字] 中的名字用中文名\n- [QUIZ] 只在最后出一道题\n- 不要在标记外输出其他标记或前缀',
      },
      ...conversationHistory,
      {
        'role': 'user',
        'content': '请讲解「${scene.title}」',
      },
    ];

    final response = await _dio.post<ResponseBody>(
      '${config.baseUrl}/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer ${config.apiKey}',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
      data: {
        'model': config.chatModel,
        'messages': messages,
        'max_tokens': 4096,
        'temperature': 0.7,
        'stream': true,
      },
    );

    String buffer = '';
    String currentMode = 'TEACH'; // TEACH, STUDENT, ANSWER, QUIZ
    String currentStudentName = '';
    final teachBuffer = StringBuffer();
    final studentBuffer = StringBuffer();
    final answerBuffer = StringBuffer();
    final quizBuffer = StringBuffer();

    void flushBuffer() {
      switch (currentMode) {
        case 'TEACH':
          if (teachBuffer.isNotEmpty) {
            controller.add(TeachChunk(teachBuffer.toString()));
            teachBuffer.clear();
          }
        case 'STUDENT':
          if (studentBuffer.isNotEmpty) {
            controller.add(StudentAskChunk(
              name: currentStudentName,
              question: studentBuffer.toString(),
            ));
            studentBuffer.clear();
          }
        case 'ANSWER':
          if (answerBuffer.isNotEmpty) {
            controller.add(StudentAnswerChunk(answerBuffer.toString()));
            answerBuffer.clear();
          }
        case 'QUIZ':
          if (quizBuffer.isNotEmpty) {
            final quiz = _parseQuiz(quizBuffer.toString());
            if (quiz != null) {
              controller.add(QuizChunk(quiz));
            }
            quizBuffer.clear();
          }
      }
    }

    response.data!.stream
        .map((bytes) => utf8.decode(bytes))
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (!line.startsWith('data: ')) return;
        final data = line.substring(6).trim();
        if (data == '[DONE]') {
          flushBuffer();
          controller.close();
          return;
        }

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) return;
          final delta = choices[0]['delta'] as Map<String, dynamic>? ?? {};
          final content = delta['content'] as String?;
          if (content == null || content.isEmpty) return;

          buffer += content;

          // 逐行解析 buffer 中的标记
          while (buffer.contains('\n')) {
            final newlineIdx = buffer.indexOf('\n');
            final line = buffer.substring(0, newlineIdx);
            buffer = buffer.substring(newlineIdx + 1);

            final trimmed = line.trim();

            // 检测标记
            if (trimmed == '[TEACH]') {
              flushBuffer();
              currentMode = 'TEACH';
              continue;
            }
            if (trimmed.startsWith('[STUDENT:') && trimmed.endsWith(']')) {
              flushBuffer();
              currentMode = 'STUDENT';
              currentStudentName = trimmed.substring(9, trimmed.length - 1);
              continue;
            }
            if (trimmed == '[ANSWER]') {
              flushBuffer();
              currentMode = 'ANSWER';
              continue;
            }
            if (trimmed == '[QUIZ]') {
              flushBuffer();
              currentMode = 'QUIZ';
              continue;
            }

            // 写入对应 buffer
            switch (currentMode) {
              case 'TEACH':
                if (teachBuffer.isNotEmpty) teachBuffer.write('\n');
                teachBuffer.write(line);
              case 'STUDENT':
                if (studentBuffer.isNotEmpty) studentBuffer.write('\n');
                studentBuffer.write(line);
              case 'ANSWER':
                if (answerBuffer.isNotEmpty) answerBuffer.write('\n');
                answerBuffer.write(line);
              case 'QUIZ':
                if (quizBuffer.isNotEmpty) quizBuffer.write('\n');
                quizBuffer.write(line);
            }
          }
        } catch (_) {}
      },
      onError: (e) {
        controller.addError(e);
        controller.close();
      },
      onDone: () {
        // 处理 buffer 中剩余内容
        if (buffer.trim().isNotEmpty) {
          switch (currentMode) {
            case 'TEACH':
              teachBuffer.write(buffer);
            case 'STUDENT':
              studentBuffer.write(buffer);
            case 'ANSWER':
              answerBuffer.write(buffer);
            case 'QUIZ':
              quizBuffer.write(buffer);
          }
        }
        flushBuffer();
        if (!controller.isClosed) controller.close();
      },
    );

    yield* controller.stream;
  }

  /// 解析测验文本为 ClassroomQuiz
  ClassroomQuiz? _parseQuiz(String text) {
    try {
      final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

      String question = '';
      final options = <String>[];
      int correctIndex = -1;
      String explanation = '';

      for (final line in lines) {
        if (line.startsWith('题目：') || line.startsWith('题目:')) {
          question = line.substring(3).trim();
        } else if (RegExp(r'^[A-D][.、．。]\s*').hasMatch(line)) {
          options.add(line.substring(2).trim());
        } else if (line.startsWith('答案：') || line.startsWith('答案:')) {
          final letter = line.substring(3).trim().toUpperCase();
          correctIndex = letter.codeUnitAt(0) - 'A'.codeUnitAt(0);
        } else if (line.startsWith('解析：') || line.startsWith('解析:')) {
          explanation = line.substring(3).trim();
        }
      }

      if (question.isEmpty || options.length < 2 || correctIndex < 0) return null;

      return ClassroomQuiz(
        question: question,
        options: options,
        correctIndex: correctIndex.clamp(0, options.length - 1),
        explanation: explanation,
      );
    } catch (_) {
      return null;
    }
  }

  /// 检查用户答案并生成反馈
  Future<String> checkAnswer({
    required ApiConfig config,
    required ClassroomQuiz quiz,
    required int userAnswer,
  }) async {
    final isCorrect = userAnswer == quiz.correctIndex;
    final userLetter = String.fromCharCode('A'.codeUnitAt(0) + userAnswer);
    final correctLetter = String.fromCharCode('A'.codeUnitAt(0) + quiz.correctIndex);

    if (isCorrect) {
      return '✅ 正确！${quiz.explanation.isNotEmpty ? "\n\n${quiz.explanation}" : ""}';
    }

    // 错误时调用 LLM 生成个性化反馈
    try {
      final response = await _dio.post(
        '${config.baseUrl}/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': config.chatModel,
          'messages': [
            {
              'role': 'system',
              'content': '你是一个耐心的老师。学生答错了选择题，请简短地解释为什么错了，并给出正确答案的思路。控制在 100 字以内。',
            },
            {
              'role': 'user',
              'content': '题目：${quiz.question}\n'
                  '选项：${quiz.options.asMap().entries.map((e) => "${String.fromCharCode(65 + e.key)}. ${e.value}").join("\n")}\n'
                  '学生选择了 $userLetter，正确答案是 $correctLetter\n'
                  '${quiz.explanation.isNotEmpty ? "参考解析：${quiz.explanation}" : ""}',
            },
          ],
          'max_tokens': 256,
          'temperature': 0.7,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final feedback = data['choices'][0]['message']['content'] as String;
      return '❌ 答错了，你选了 $userLetter，正确答案是 $correctLetter\n\n$feedback';
    } catch (_) {
      return '❌ 答错了，你选了 $userLetter，正确答案是 $correctLetter'
          '${quiz.explanation.isNotEmpty ? "\n\n${quiz.explanation}" : ""}';
    }
  }
}

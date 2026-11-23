import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/app_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class ExamRecognitionScreen extends ConsumerStatefulWidget {
  final String? subjectId;
  final String? subjectName;

  const ExamRecognitionScreen({super.key, this.subjectId, this.subjectName});

  @override
  ConsumerState<ExamRecognitionScreen> createState() => _ExamRecognitionScreenState();
}

class _ExamRecognitionScreenState extends ConsumerState<ExamRecognitionScreen> {
  final _apiService = ApiService();
  String? _base64Image;
  String? _imageName;
  bool _isAnalyzing = false;
  String _analysisResult = '';
  String _selectedMode = 'analyze';

  static const _analysisModes = {
    'analyze': {'label': '知识点分析', 'icon': Icons.analytics_outlined, 'prompt': '''请分析这张试题图片，提取以下信息并以 JSON 格式返回：
{
  "subject": "科目名称",
  "topics": ["涉及的知识点1", "知识点2"],
  "difficulty": "难度等级(简单/中等/困难)",
  "questions": [
    {
      "number": "题号",
      "type": "题型(选择/填空/解答等)",
      "content": "题目内容",
      "knowledge_points": ["相关知识点"],
      "answer_hint": "解题思路提示"
    }
  ],
  "summary": "整体分析总结"
}
请确保返回有效的 JSON 格式。'''},
    'compare': {'label': '对比分析', 'icon': Icons.compare_arrows, 'prompt': '''请分析这张试题图片，重点进行对比分析：
1. 识别题目中涉及的知识点
2. 分析各知识点的考查方式
3. 指出常见的易错点
4. 总结该类题目的解题规律

请以清晰的 Markdown 格式输出。'''},
    'extract': {'label': '题目提取', 'icon': Icons.text_snippet_outlined, 'prompt': '''请从这张试题图片中提取所有题目内容，以 JSON 格式返回：
{
  "questions": [
    {
      "number": "题号",
      "type": "题型",
      "content": "完整题目内容",
      "options": ["选项A", "选项B", "选项C", "选项D"],
      "answer": "参考答案(如果图中有)"
    }
  ]
}
如果某些字段无法从图中确定，设为 null。请确保返回有效的 JSON。'''},
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subjectName != null ? '${widget.subjectName} - 试题识别' : '试题识别'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 图片选择区域
          _buildImageSection(),
          const SizedBox(height: 16),

          // 分析模式选择
          if (_base64Image != null) ...[
            _buildModeSelector(),
            const SizedBox(height: 16),
          ],

          // 分析按钮
          if (_base64Image != null && !_isAnalyzing)
            ElevatedButton.icon(
              onPressed: _analyze,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('开始分析'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),

          // 加载状态
          if (_isAnalyzing) _buildLoadingState(),

          // 分析结果
          if (_analysisResult.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildResultSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: _base64Image != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.image, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _imageName ?? '已选择图片',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSec,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() {
                        _base64Image = null;
                        _imageName = null;
                        _analysisResult = '';
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(_base64Image!),
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('重新拍照'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text('从相册选'),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              children: [
                Icon(
                  Icons.document_scanner_outlined,
                  size: 48,
                  color: AppColors.primary.withOpacity(0.6),
                ),
                const SizedBox(height: 12),
                Text(
                  '拍摄或选择试题图片',
                  style: TextStyle(
                    fontSize: 15,
                    color: context.textSec,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('拍照'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('相册'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildModeSelector() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '分析模式',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textSec,
            ),
          ),
          const SizedBox(height: 12),
          ..._analysisModes.entries.map((entry) {
            final mode = entry.value;
            final isSelected = _selectedMode == entry.key;
            return GestureDetector(
              onTap: () => setState(() => _selectedMode = entry.key),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.glassBorder,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      mode['icon'] as IconData,
                      size: 20,
                      color: isSelected ? AppColors.primary : context.textSec,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      mode['label'] as String,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? AppColors.primary : context.text,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      Icon(Icons.check_circle, size: 18, color: AppColors.primary),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return GlassCard(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '正在分析试题...',
            style: TextStyle(
              fontSize: 14,
              color: context.textSec,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI 正在识别和分析图片内容',
            style: TextStyle(
              fontSize: 12,
              color: context.textSec.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSection() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                '分析结果',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _analysisResult));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                  );
                },
                tooltip: '复制结果',
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          SelectableText(
            _analysisResult,
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (image == null) return;

    final bytes = await File(image.path).readAsBytes();
    setState(() {
      _base64Image = base64Encode(bytes);
      _imageName = image.name;
      _analysisResult = '';
    });
  }

  Future<void> _analyze() async {
    if (_base64Image == null) return;

    final config = ref.read(apiConfigProvider);
    if (!config.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置 API Key')),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisResult = '';
    });

    try {
      final prompt = _analysisModes[_selectedMode]!['prompt'] as String;
      final result = await _apiService.analyzeImage(
        config: config,
        base64Image: _base64Image!,
        prompt: prompt,
      );

      if (mounted) {
        setState(() {
          _analysisResult = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _analysisResult = '分析失败: $e';
        });
      }
    }
  }
}

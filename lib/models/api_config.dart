import 'package:json_annotation/json_annotation.dart';

part 'api_config.g.dart';

@JsonSerializable()
class ApiConfig {
  final String provider; // 'siliconflow' 或 'custom'
  final String baseUrl;
  final String apiKey;
  final String chatModel;
  final String visionModel;

  const ApiConfig({
    this.provider = 'siliconflow',
    this.baseUrl = 'https://api.siliconflow.cn/v1',
    this.apiKey = '',
    this.chatModel = 'Qwen/Qwen3.5-4B',
    this.visionModel = 'Qwen/Qwen3-VL-8B-Instruct',
  });

  ApiConfig copyWith({
    String? provider,
    String? baseUrl,
    String? apiKey,
    String? chatModel,
    String? visionModel,
  }) {
    return ApiConfig(
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      chatModel: chatModel ?? this.chatModel,
      visionModel: visionModel ?? this.visionModel,
    );
  }

  bool get isConfigured => apiKey.isNotEmpty;

  factory ApiConfig.fromJson(Map<String, dynamic> json) =>
      _$ApiConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ApiConfigToJson(this);
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApiConfig _$ApiConfigFromJson(Map<String, dynamic> json) => ApiConfig(
  provider: json['provider'] as String? ?? 'siliconflow',
  baseUrl: json['baseUrl'] as String? ?? 'https://api.siliconflow.cn/v1',
  apiKey: json['apiKey'] as String? ?? '',
  chatModel: json['chatModel'] as String? ?? 'Qwen/Qwen3.5-4B',
  visionModel: json['visionModel'] as String? ?? 'Qwen/Qwen3-VL-8B-Instruct',
);

Map<String, dynamic> _$ApiConfigToJson(ApiConfig instance) => <String, dynamic>{
  'provider': instance.provider,
  'baseUrl': instance.baseUrl,
  'apiKey': instance.apiKey,
  'chatModel': instance.chatModel,
  'visionModel': instance.visionModel,
};

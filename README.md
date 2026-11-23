<div align="center">

[![GitHub stars](https://img.shields.io/github/stars/makur6371/kuaxue?style=social)](https://github.com/makur6371/kuaxue)
[![GitHub forks](https://img.shields.io/github/forks/makur6371/kuaxue?style=social)](https://github.com/makur6371/kuaxue)
[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)](https://developer.android.com)

</div>

# Kuaxue (AI Studio)

Flutter 跨平台学习助手 —— 把课堂、文档、知识卡片、复习计划串成一条完整的学习链路。

## 功能模块

| 模块 | 说明 |
| --- | --- |
| **课堂 Classroom** | 课程与课堂管理 |
| **知识卡片 Knowledge Card** | 卡片式知识整理与编辑 |
| **复习卡片 Review Card** | 间隔复习，记忆巩固 |
| **文档 Document** | 文档解析与智能处理（OCR / 嵌入） |
| **考试识别 Exam Recognition** | 试卷识别与结构化 |
| **日程 Schedule** | 学习计划与日程面板 |
| **搜索 Search** | 全局检索 |
| **对话 Chat** | AI 智能问答 |

## 技术栈

- **Flutter / Dart**（Material 3 主题，`app_theme.dart`）
- **状态管理**：`app_provider.dart`
- **本地存储**：`database_service.dart`（SQLite）
- **AI 能力**：`agent_service.dart`、`embedding_service.dart`、`prompt_service.dart`、`memory_service.dart`
- **语音**：`tts_service.dart`、`voice_service.dart`
- **网络**：`api_service.dart` + `retry_interceptor.dart`（失败重试）
- **文档**：`document_processor.dart`、`export_service.dart`

## 目录结构

```
lib/
  models/       # 数据模型（api_config / classroom / document / memory / message…）
  providers/    # 状态管理
  screens/      # 页面
  services/     # 业务服务
  theme/        # 主题
  widgets/      # 组件
android/        # Android 原生配置
```

## 运行

```bash
flutter pub get
flutter run
```

### 打包

```bash
flutter build apk      # Android
flutter build ipa      # iOS
```

## 说明

本项目为个人自用项目，代码仅供学习参考。

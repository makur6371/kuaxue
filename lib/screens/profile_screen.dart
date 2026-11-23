import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import '../main.dart';
import '../models/api_config.dart';
import '../providers/app_provider.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatMessagesProvider);
    final todos = ref.watch(todosProvider);
    final todoCount = todos.where((t) => !t.isDone).length;
    final hasUpdate = ref.watch(updateInfoProvider) != null;
    final userService = ref.read(userServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // 头像
          _ProfileHeader(
            nickname: userService.nickname ?? 'Macura用户',
            username: '@${userService.username ?? ""}',
          ),
          const SizedBox(height: 16),

          // 统计
          _StatsRow(messageCount: messages.length, todoCount: todoCount),
          const SizedBox(height: 24),

          // 设置列表
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.smart_toy_outlined,
                  iconColor: AppColors.primary,
                  title: 'AI 模型设置',
                  subtitle: '配置 API 和模型',
                  trailing: _buildConfigBadge(ref),
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const _AiModelSettingsPage())),
                ),
                const Divider(height: 1, indent: 60),
                _SettingsTile(
                  icon: Icons.palette_outlined,
                  iconColor: AppColors.primary,
                  title: '外观',
                  subtitle: '主题和显示',
                  onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const _AppearancePage())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.system_update_outlined,
                  iconColor: AppColors.primary,
                  title: '检查更新',
                  subtitle: hasUpdate ? '有新版本可用' : '查看是否有新版本',
                  subtitleColor: hasUpdate ? Colors.orange : null,
                  trailing: hasUpdate
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            ref.watch(updateInfoProvider)!.versionName,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        )
                      : null,
                  onTap: () => _checkUpdate(context, ref),
                ),
                const Divider(height: 1, indent: 60),
                _SettingsTile(
                  icon: Icons.info_outline,
                  iconColor: AppColors.primary,
                  title: '关于 Macura',
                  onTap: () => _showAboutDialog(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.upload_outlined,
                  iconColor: AppColors.primary,
                  title: '导出聊天记录',
                  subtitle: '导出为 JSON 文件',
                  onTap: () => _exportChatHistory(context, ref),
                ),
                const Divider(height: 1, indent: 60),
                _SettingsTile(
                  icon: Icons.backup_outlined,
                  iconColor: AppColors.primary,
                  title: '备份全部数据',
                  subtitle: '导出所有数据为 JSON',
                  onTap: () => _exportAll(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.delete_outline,
                  iconColor: Colors.redAccent,
                  title: '清空聊天记录',
                  subtitle: '删除所有对话消息',
                  onTap: () => _confirmClearChat(context, ref),
                ),
                const Divider(height: 1, indent: 60),
                _SettingsTile(
                  icon: Icons.logout,
                  iconColor: Colors.redAccent,
                  title: '退出登录',
                  subtitle: '切换到其他账号',
                  titleColor: Colors.redAccent,
                  onTap: () => _confirmLogout(context, ref),
                ),
              ],
            ),
          ),

          // API 配置指引
          if (!ref.read(apiConfigProvider).isConfigured) ...[
            const SizedBox(height: 24),
            _ApiGuideCard(),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static Widget? _buildConfigBadge(WidgetRef ref) {
    final config = ref.watch(apiConfigProvider);
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: config.isConfigured ? AppColors.primary : Colors.orange,
      ),
    );
  }

  static Future<void> _checkUpdate(BuildContext context, WidgetRef ref) async {
    var update = ref.read(updateInfoProvider);
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在检查更新...'), duration: Duration(seconds: 1)),
      );
      await ref.read(updateInfoProvider.notifier).check();
      update = ref.read(updateInfoProvider);
    }
    if (!context.mounted) return;
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已是最新版本'), duration: Duration(seconds: 1)),
      );
      return;
    }
    final info = update;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('发现新版本 ${info.versionName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.changelog.isNotEmpty) ...[
              const Text('更新内容：', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
              const SizedBox(height: 4),
              Text(info.changelog, style: const TextStyle(fontSize: 13, height: 1.5)),
              const SizedBox(height: 12),
            ],
            Text('是否下载并安装？', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ),
        actions: [
          if (!info.isForce)
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startDownload(context, ref, info);
            },
            child: const Text('下载更新'),
          ),
        ],
      ),
    );
  }

  static void _startDownload(BuildContext context, WidgetRef ref, UpdateInfo info) {
    final cancelToken = CancelToken();
    final updateService = UpdateService();
    double progress = 0;
    bool started = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (!started) {
            started = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              updateService.downloadAndInstall(
                info.downloadUrl,
                (p) {
                  if (ctx.mounted) setDialogState(() => progress = p);
                },
                cancelToken,
              ).catchError((e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('下载失败: ${e is DioException ? "网络错误" : e.toString()}')),
                  );
                }
                return null;
              });
            });
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(progress < 1 ? '正在下载' : '下载完成'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.primary.withOpacity(0.15),
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
                const SizedBox(height: 12),
                Text(
                  progress < 1 ? '${(progress * 100).toStringAsFixed(0)}%' : '正在打开安装...',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              ],
            ),
            actions: [
              if (progress < 1)
                TextButton(
                  onPressed: () {
                    cancelToken.cancel();
                    Navigator.pop(ctx);
                  },
                  child: const Text('取消'),
                ),
            ],
          );
        },
      ),
    );
  }

  static void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(authStateProvider.notifier).logout();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  static void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (ctx, snapshot) {
          final info = snapshot.data;
          final versionText = info != null
              ? '版本: ${info.version} (${info.buildNumber})'
              : '版本: 加载中...';
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.school, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('Macura'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Macura', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(versionText),
                const SizedBox(height: 12),
                const Text('Macura 是 Makur 旗下的 AI 学习 Agent，帮助你高效学习、整理知识、分析试题。', style: TextStyle(height: 1.5)),
                const SizedBox(height: 12),
                const Text('功能特色：', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                const Text('• AI 智能对话（Agent Loop）'),
                const Text('• 试题拍照识别'),
                const Text('• 文档分类管理'),
                const Text('• 语音识别输入'),
                const Text('• 智能日程待办'),
                const Text('• 间隔重复复习（SM-2）'),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _exportChatHistory(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在导出...'), duration: Duration(seconds: 1)),
    );
    try {
      final file = await ref.read(exportServiceProvider).exportChatHistory();
      await ref.read(exportServiceProvider).shareFile(file);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  static Future<void> _exportAll(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在备份...'), duration: Duration(seconds: 1)),
    );
    try {
      final file = await ref.read(exportServiceProvider).exportAll();
      await ref.read(exportServiceProvider).shareFile(file);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  static void _confirmClearChat(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空聊天记录'),
        content: const Text('确定要删除所有对话消息吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(chatMessagesProvider.notifier).clearChat();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('聊天记录已清空'), duration: Duration(seconds: 1)),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

// ── 头像组件 ──

class _ProfileHeader extends StatelessWidget {
  final String nickname;
  final String username;
  const _ProfileHeader({required this.nickname, required this.username});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.school, size: 36, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(nickname, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(username, style: TextStyle(fontSize: 13, color: context.textSec)),

        ],
      ),
    );
  }
}

// ── 统计行 ──

class _StatsRow extends StatelessWidget {
  final int messageCount;
  final int todoCount;
  const _StatsRow({required this.messageCount, required this.todoCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _statCard(context, Icons.chat_bubble_outline, '对话数', '$messageCount')),
        const SizedBox(width: 12),
        Expanded(child: _statCard(context, Icons.calendar_today_outlined, '待办数', '$todoCount')),
      ],
    );
  }

  Widget _statCard(BuildContext context, IconData icon, String label, String value) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: context.textSec)),
        ],
      ),
    );
  }
}

// ── 设置列表项 ──

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.titleColor,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Text(title, style: TextStyle(color: titleColor, fontWeight: FontWeight.w500, fontSize: 15)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(color: subtitleColor ?? context.textSec, fontSize: 12))
          : null,
      trailing: trailing ?? Icon(Icons.chevron_right, size: 20, color: context.textSec.withOpacity(0.5)),
      onTap: onTap,
    );
  }
}

// ── API 配置指引卡片 ──

class _ApiGuideCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.rocket_launch_outlined, size: 20, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('配置 API 即可开始使用', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('推荐使用 SiliconFlow 平台，注册即送免费额度：', style: TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 12),
          _guideStep('1', '访问 siliconflow.cn 注册账号'),
          _guideStep('2', '在 API Keys 页面创建密钥'),
          _guideStep('3', '复制 sk-xxx 粘贴到 AI 模型设置'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://cloud.siliconflow.cn/account/ak?invite=ikB6dKbJ'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('注册 SiliconFlow（邀请链接）'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: BorderSide(color: Colors.blue.withOpacity(0.3)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num, style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 子页面：AI 模型设置
// ══════════════════════════════════════════════════════════════

class _AiModelSettingsPage extends ConsumerStatefulWidget {
  const _AiModelSettingsPage();

  @override
  ConsumerState<_AiModelSettingsPage> createState() => _AiModelSettingsPageState();
}

class _AiModelSettingsPageState extends ConsumerState<_AiModelSettingsPage> {
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _apiKeyCtrl;
  String _provider = 'siliconflow';
  String _chatModel = '';
  String _visionModel = '';
  List<String> _chatModels = [];
  List<String> _visionModels = [];
  bool _loadingModels = false;

  static const _defaultChatModels = [
    'Qwen/Qwen3.5-4B',
    'Qwen/Qwen3-8B',
    'Qwen/Qwen3-14B',
    'deepseek-ai/DeepSeek-V3',
  ];
  static const _defaultVisionModels = [
    'Qwen/Qwen3-VL-8B-Instruct',
    'Pro/Qwen/Qwen2.5-VL-7B-Instruct',
  ];

  @override
  void initState() {
    super.initState();
    final config = ref.read(apiConfigProvider);
    _provider = config.provider;
    _baseUrlCtrl = TextEditingController(text: config.baseUrl);
    _apiKeyCtrl = TextEditingController(text: config.apiKey);
    _chatModel = config.chatModel;
    _visionModel = config.visionModel;
    _chatModels = List.from(_defaultChatModels);
    _visionModels = List.from(_defaultVisionModels);
    if (!_chatModels.contains(_chatModel) && _chatModel.isNotEmpty) {
      _chatModels.insert(0, _chatModel);
    }
    if (!_visionModels.contains(_visionModel) && _visionModel.isNotEmpty) {
      _visionModels.insert(0, _visionModel);
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(apiConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI 模型设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 状态
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: config.isConfigured ? AppColors.primary : Colors.orange,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  config.isConfigured ? 'API 已配置' : 'API 未配置',
                  style: TextStyle(
                    fontSize: 14,
                    color: config.isConfigured ? AppColors.primary : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 提供商
          Text('API 提供商', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: context.textSec)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'siliconflow', label: Text('SiliconFlow')),
              ButtonSegment(value: 'custom', label: Text('自定义')),
            ],
            selected: {_provider},
            onSelectionChanged: (v) {
              setState(() {
                _provider = v.first;
                if (_provider == 'siliconflow') {
                  _baseUrlCtrl.text = 'https://api.siliconflow.cn/v1';
                  _chatModel = 'Qwen/Qwen3.5-4B';
                  _visionModel = 'Qwen/Qwen3-VL-8B-Instruct';
                }
              });
            },
          ),
          const SizedBox(height: 20),

          // Base URL
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.siliconflow.cn/v1',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            enabled: _provider == 'custom',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),

          // API Key
          TextField(
            controller: _apiKeyCtrl,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            obscureText: true,
            style: const TextStyle(fontSize: 14),
          ),

          if (_provider == 'siliconflow') ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loadingModels ? null : _loadModels,
                icon: _loadingModels
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('加载模型列表', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
          const SizedBox(height: 8),

          // 对话模型
          Text('对话模型', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: context.textSec)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _chatModels.contains(_chatModel) ? _chatModel : null,
            items: _chatModels.map((m) => DropdownMenuItem(
              value: m,
              child: Text(m, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setState(() => _chatModel = v ?? ''),
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            isExpanded: true,
          ),
          const SizedBox(height: 12),

          // 视觉模型
          Text('视觉模型', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: context.textSec)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _visionModels.contains(_visionModel) ? _visionModel : null,
            items: _visionModels.map((m) => DropdownMenuItem(
              value: m,
              child: Text(m, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setState(() => _visionModel = v ?? ''),
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            isExpanded: true,
          ),
          const SizedBox(height: 24),

          // 保存
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveConfig,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('保存配置'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadModels() async {
    final apiKey = _apiKeyCtrl.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入 API Key'), duration: Duration(seconds: 1)),
      );
      return;
    }
    setState(() => _loadingModels = true);
    try {
      final resp = await Dio().get(
        '${_baseUrlCtrl.text.trim()}/models',
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      final data = resp.data as Map<String, dynamic>;
      final models = (data['data'] as List).map((m) => m['id'] as String).toList()..sort();
      setState(() {
        _chatModels = models;
        _visionModels = models.where((m) =>
            m.toLowerCase().contains('vl') ||
            m.toLowerCase().contains('vision')).toList();
        if (_visionModels.isEmpty) _visionModels = List.from(_defaultVisionModels);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加载 ${models.length} 个模型'), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载失败'), duration: Duration(seconds: 1)),
        );
      }
    }
    setState(() => _loadingModels = false);
  }

  Future<void> _saveConfig() async {
    final config = ApiConfig(
      provider: _provider,
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      chatModel: _chatModel,
      visionModel: _visionModel,
    );
    await ref.read(apiConfigProvider.notifier).update(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存'), duration: Duration(seconds: 1)),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════
// 子页面：外观设置
// ══════════════════════════════════════════════════════════════

class _AppearancePage extends ConsumerWidget {
  const _AppearancePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('主题模式', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: context.textSec)),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('跟随系统'), icon: Icon(Icons.phone_android, size: 18)),
                ButtonSegment(value: 'light', label: Text('浅色'), icon: Icon(Icons.light_mode, size: 18)),
                ButtonSegment(value: 'dark', label: Text('深色'), icon: Icon(Icons.dark_mode, size: 18)),
              ],
              selected: {themeMode},
              onSelectionChanged: (v) => ref.read(themeModeProvider.notifier).setMode(v.first),
            ),
          ),
        ],
      ),
    );
  }
}

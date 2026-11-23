import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/app_provider.dart';
import 'models/subject.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'services/user_service.dart';
import 'services/update_service.dart';
import 'theme/app_theme.dart';
import 'screens/chat_screen.dart';
import 'screens/document_screen.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/search_screen.dart';
import 'screens/subject_detail_screen.dart';
import 'screens/animated_splash_screen.dart';
import 'screens/classroom_screen.dart';
import 'widgets/glass_card.dart';

// User Service Provider
final userServiceProvider = Provider<UserService>((ref) => UserService());

// Update Service Provider
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());

// Update Info Provider (background check)
final updateInfoProvider = StateNotifierProvider<UpdateNotifier, UpdateInfo?>((ref) {
  return UpdateNotifier(ref.read(updateServiceProvider));
});

class UpdateNotifier extends StateNotifier<UpdateInfo?> {
  final UpdateService _service;
  UpdateNotifier(this._service) : super(null);

  Future<void> check() async {
    final info = await _service.checkUpdate();
    if (info != null) state = info;
  }

  void dismiss() => state = null;
}

// Auth State
enum AuthStatus { loading, authenticated, unauthenticated }

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthStatus>((ref) {
  return AuthNotifier(ref.read(userServiceProvider), ref);
});

class AuthNotifier extends StateNotifier<AuthStatus> {
  final UserService _userService;
  final Ref _ref;
  AuthNotifier(this._userService, this._ref) : super(AuthStatus.loading) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final valid = await _userService.loadSavedAuth();
    state = valid ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    if (valid) {
      _ref.read(updateInfoProvider.notifier).check();
    }
  }

  void setLoggedIn() {
    state = AuthStatus.authenticated;
    _ref.read(updateInfoProvider.notifier).check();
  }

  Future<void> logout() async {
    await _userService.logout();
    state = AuthStatus.unauthenticated;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  await storage.init();

  await NotificationService().init();

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: const KuaxueApp(),
    ),
  );
}

class KuaxueApp extends ConsumerWidget {
  const KuaxueApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final authStatus = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'Macura',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode == 'dark'
          ? ThemeMode.dark
          : themeMode == 'light'
              ? ThemeMode.light
              : ThemeMode.system,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: switch (authStatus) {
          AuthStatus.loading => AnimatedSplashScreen(
              key: const ValueKey('splash'),
              onComplete: () {},
            ),
          AuthStatus.authenticated => const HomePage(key: ValueKey('home')),
          AuthStatus.unauthenticated => LoginScreen(
              key: ValueKey('login'),
              onLoginSuccess: () {
                ref.read(authStateProvider.notifier).setLoggedIn();
              },
            ),
        },
      ),
    );
  }
}

// ── HomePage ──

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _subjectNameCtrl = TextEditingController();

  static const _presetColors = [
    '#88D8B0', '#FF6B6B', '#4ECDC4', '#45B7D1',
    '#96CEB4', '#FFEAA7', '#DDA0DD', '#98D8C8',
    '#F7DC6F', '#BB8FCE', '#85C1E9', '#F1948A',
  ];

  static const _presetIcons = [
    '📐', '📚', '🔬', '🧪', '🌍', '💻', '🎨', '🎵',
    '📊', '📝', '🔤', '🧮', '📖', '🎓', '✏️', '📏',
  ];

  @override
  void dispose() {
    _subjectNameCtrl.dispose();
    super.dispose();
  }

  Color _parseColor(String hex) {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 500;

    if (isWide) {
      // 横屏/平板：左侧固定侧边栏 + 右侧对话
      return Scaffold(
        appBar: AppBar(
          title: const Text('Macura'),
        ),
        body: Row(
          children: [
            SizedBox(
              width: 195,
              child: _buildSidebarContent(context),
            ),
            const VerticalDivider(width: 1),
            const Expanded(child: ChatScreen()),
          ],
        ),
      );
    }

    // 竖屏：Drawer + 对话
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: GestureDetector(
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
          child: const Text('Macura'),
        ),
      ),
      drawer: Drawer(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: _buildSidebarContent(context),
      ),
      body: SafeArea(
        child: ChatScreen(
          onSwipeRight: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
    );
  }

  // ── 侧边栏内容 ──

  Widget _buildSidebarContent(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Logo 区域
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: const DecorationImage(
                      image: AssetImage('assets/logonew.png'),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.2),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Macura',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.text),
                ),
                const SizedBox(height: 2),
                Text(
                  'AI Learning Agent',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSec,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 搜索入口
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: context.textSec),
                    const SizedBox(width: 8),
                    Text('搜索...', style: TextStyle(fontSize: 13, color: context.textSec)),
                  ],
                ),
              ),
            ),
          ),
          // 文档列表标题 + 新增按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Text(
                  '文档',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.textSec,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.add, size: 20, color: AppColors.primary),
                  onPressed: _showAddSubjectSheet,
                  tooltip: '新增科目',
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          // 文档列表（限制最大高度）
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: _buildDocumentList(),
          ),
          const Divider(height: 1),
          // AI 课堂入口
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ClassroomScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.12),
                      AppColors.primaryDark.withOpacity(0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Text('🧑‍🏫', style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI 课堂', style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.text,
                          )),
                          Text('互动讲解 · 随堂测验', style: TextStyle(
                            fontSize: 11,
                            color: context.textSec,
                          )),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: context.textSec),
                  ],
                ),
              ),
            ),
          ),
          // 底部：文档管理 + 设置
          ListTile(
            leading: Icon(Icons.folder_outlined, size: 20, color: context.textSec),
            title: Text('文档管理', style: TextStyle(fontSize: 14, color: context.text)),
            dense: true,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DocumentScreen()),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.settings_outlined, size: 20, color: context.textSec),
            title: Text('设置', style: TextStyle(fontSize: 14, color: context.text)),
            dense: true,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDocumentList() {
    final subjects = ref.watch(subjectsProvider);

    if (subjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined, size: 40, color: AppColors.primary.withOpacity(0.4)),
              const SizedBox(height: 8),
              Text(
                '还没有文档',
                style: TextStyle(fontSize: 13, color: context.textSec),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: _showAddSubjectSheet,
                child: Text(
                  '点击 + 创建',
                  style: TextStyle(fontSize: 12, color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: subjects.length,
      itemBuilder: (context, index) {
        final subject = subjects[index];
        return _buildSubjectTile(subject);
      },
    );
  }

  Widget _buildSubjectTile(Subject subject) {
    final color = _parseColor(subject.color ?? '#88D8B0');
    final icon = subject.icon ?? '📚';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context,
          MaterialPageRoute(builder: (_) => SubjectDetailScreen(subject: subject)),
        );
      },
      onLongPress: () => _showSubjectActions(subject),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: Text(icon, style: const TextStyle(fontSize: 16))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subject.name,
                style: TextStyle(
                  fontSize: 14,
                  color: context.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSubjectActions(Subject subject) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GlassCard(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditSubjectSheet(subject);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('删除', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteSubject(subject);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSubject(Subject subject) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除科目'),
        content: Text('确定删除「${subject.name}」及其所有文档吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(subjectsProvider.notifier).delete(subject.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ── 添加/编辑 Subject sheets ──

  void _showAddSubjectSheet() {
    _subjectNameCtrl.clear();
    String selectedIcon = _presetIcons[0];
    String selectedColor = _presetColors[0];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return GlassCard(
            margin: const EdgeInsets.all(12),
            padding: EdgeInsets.fromLTRB(20, 20, 20,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('添加科目', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _subjectNameCtrl,
                    decoration: const InputDecoration(
                      labelText: '科目名称',
                      hintText: '例如：高等数学、大学英语',
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 20),
                  const Text('选择图标', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _presetIcons.map((icon) {
                      final isSelected = icon == selectedIcon;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedIcon = icon),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withOpacity(0.2) : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.glassBorder,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text('选择颜色', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _presetColors.map((colorHex) {
                      final color = _parseColor(colorHex);
                      final isSelected = colorHex == selectedColor;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = colorHex),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final name = _subjectNameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('请输入科目名称'), duration: Duration(seconds: 1)),
                        );
                        return;
                      }
                      ref.read(subjectsProvider.notifier).add(name, icon: selectedIcon, color: selectedColor);
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: const Text('添加'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditSubjectSheet(Subject subject) {
    final nameCtrl = TextEditingController(text: subject.name);
    String selectedIcon = subject.icon ?? _presetIcons[0];
    String selectedColor = subject.color ?? _presetColors[0];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return GlassCard(
            margin: const EdgeInsets.all(12),
            padding: EdgeInsets.fromLTRB(20, 20, 20,
                MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('编辑科目', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '科目名称',
                      hintText: '例如：高等数学、大学英语',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('选择图标', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _presetIcons.map((icon) {
                      final isSelected = icon == selectedIcon;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedIcon = icon),
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withOpacity(0.2) : AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.glassBorder,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text('选择颜色', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _presetColors.map((colorHex) {
                      final color = _parseColor(colorHex);
                      final isSelected = colorHex == selectedColor;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedColor = colorHex),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('请输入科目名称'), duration: Duration(seconds: 1)),
                        );
                        return;
                      }
                      ref.read(subjectsProvider.notifier).update(
                        subject.copyWith(name: name, icon: selectedIcon, color: selectedColor),
                      );
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

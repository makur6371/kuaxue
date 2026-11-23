import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static const String _baseUrl = 'https://makur.top/kuaxue-api';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// 获取当前版本号
  Future<int> get currentVersionCode async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 1;
  }

  /// 检查是否有新版本
  Future<UpdateInfo?> checkUpdate() async {
    try {
      final code = await currentVersionCode;
      final response = await _dio.get(
        '/api/app/version',
        queryParameters: {'version_code': code},
      );

      final data = response.data;
      if (data['has_update'] == true) {
        return UpdateInfo(
          versionCode: data['version_code'],
          versionName: data['version_name'],
          changelog: data['changelog'] ?? '',
          downloadUrl: '$_baseUrl${data['download_url'] ?? '/api/app/download'}',
          isForce: (data['is_force'] ?? 0) == 1 || data['is_force'] == true,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 下载 APK 并返回进度，完成后打开安装
  Future<void> downloadAndInstall(
    String url,
    void Function(double progress) onProgress,
    CancelToken cancelToken,
  ) async {
    final dir = await getTemporaryDirectory();
    final savePath = '${dir.path}/kuaxue.apk';

    await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress(received / total);
      },
    );

    await OpenFilex.open(savePath);
  }
}

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String changelog;
  final String downloadUrl;
  final bool isForce;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.changelog,
    required this.downloadUrl,
    this.isForce = false,
  });
}

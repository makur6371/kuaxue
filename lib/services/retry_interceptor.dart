import 'package:dio/dio.dart';

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  RetryInterceptor({required this.dio, this.maxRetries = 2});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_shouldRetry(err) && err.requestOptions.extra['retryCount'] == null) {
      err.requestOptions.extra['retryCount'] = 0;
    }

    final retryCount = err.requestOptions.extra['retryCount'] as int? ?? 0;
    if (retryCount >= maxRetries) {
      handler.next(err);
      return;
    }

    if (!_shouldRetry(err)) {
      handler.next(err);
      return;
    }

    err.requestOptions.extra['retryCount'] = retryCount + 1;
    final delay = Duration(seconds: retryCount + 1);
    await Future.delayed(delay);

    try {
      final response = await dio.fetch(err.requestOptions);
      handler.resolve(response);
    } catch (e) {
      handler.next(e is DioException ? e : err);
    }
  }

  bool _shouldRetry(DioException err) {
    // 超时可重试
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout) {
      return true;
    }
    // 5xx 服务端错误可重试
    if (err.response?.statusCode != null && err.response!.statusCode! >= 500) {
      return true;
    }
    // 连接错误可重试
    if (err.type == DioExceptionType.connectionError) {
      return true;
    }
    return false;
  }
}

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../auth/token_storage.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/safe_log_interceptor.dart';

class ApiClient {
  late final Dio dio;

  ApiClient({
    required TokenStorage tokenStorage,
    VoidCallback? onUnauthorized,
  }) {
    final baseUrl =
        dotenv.env['API_BASE_URL'] ?? 'https://api.oakle.app/api/v1/';
    final configuredUri = Uri.parse(baseUrl);
    final apiPrefix = configuredUri.path.endsWith('/')
        ? configuredUri.path
        : '${configuredUri.path}/';

    dio = Dio(
      BaseOptions(
        baseUrl: '${configuredUri.origin}/',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 45),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.addAll([
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (!options.path.startsWith('http://') &&
              !options.path.startsWith('https://')) {
            final route = options.path.replaceFirst(RegExp(r'^/+'), '');
            options.path = '${configuredUri.origin}$apiPrefix$route';
          }
          handler.next(options);
        },
      ),
      AuthInterceptor(
        tokenStorage: tokenStorage,
        onUnauthorized: onUnauthorized,
      ),
      SafeLogInterceptor(),
    ]);
  }
}

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
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000/api/v1/';

    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 45),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.addAll([
      AuthInterceptor(
        tokenStorage: tokenStorage,
        onUnauthorized: onUnauthorized,
      ),
      SafeLogInterceptor(),
    ]);
  }
}
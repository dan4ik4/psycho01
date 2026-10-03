import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'token_storage.dart';
import 'auth_interceptor.dart';
import 'safe_log_interceptor.dart';

class ApiClient {
  late final Dio dio;

  ApiClient({
    required TokenStorage tokenStorage,
  }) {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000/api/v1/';

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
      AuthInterceptor(tokenStorage: tokenStorage),
      SafeLogInterceptor(),
    ]);
  }
}
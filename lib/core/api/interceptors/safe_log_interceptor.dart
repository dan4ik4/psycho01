import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class SafeLogInterceptor extends Interceptor {
  static const List<String> _sensitiveKeys = [
    'password',
    'token',
    'access_token',
    'refresh_token',
    'otp',
    'code',
    'authorization',
    'secret',
    'text',    // Добавлено: скрытие текста сообщения
    'message', // Добавлено: скрытие текста сообщения
    'content', // Добавлено: скрытие текста сообщения
  ];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      final safeHeaders = _sanitizeMap(options.headers);
      final safeData = _sanitizeData(options.data);
      debugPrint('--> [REQ] ${options.method} ${options.uri}');
      debugPrint('Headers: $safeHeaders');
      if (safeData != null) debugPrint('Body: $safeData');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('<-- [RESP ${response.statusCode}] ${response.requestOptions.uri}');
      final safeData = _sanitizeData(response.data);
      if (safeData != null) debugPrint('Payload: $safeData');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('<-- [ERROR ${err.response?.statusCode}] ${err.requestOptions.uri}');
      debugPrint('Message: ${err.message}');
    }
    handler.next(err);
  }

  dynamic _sanitizeData(dynamic data) {
    if (data is Map<String, dynamic>) {
      return _sanitizeMap(data);
    }
    return data;
  }

  Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map) {
    final result = Map<String, dynamic>.from(map);
    for (final entry in result.entries) {
      final key = entry.key.toLowerCase();
      if (_sensitiveKeys.any((s) => key.contains(s))) {
        result[entry.key] = '***MASKED***';
      } else if (entry.value is Map<String, dynamic>) {
        result[entry.key] = _sanitizeMap(entry.value as Map<String, dynamic>);
      }
    }
    return result;
  }
}
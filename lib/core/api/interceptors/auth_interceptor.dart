import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../auth/token_storage.dart';

class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  final VoidCallback? _onUnauthorized;

  AuthInterceptor({
    required TokenStorage tokenStorage,
    VoidCallback? onUnauthorized,
  })  : _tokenStorage = tokenStorage,
        _onUnauthorized = onUnauthorized;

  @override
  void onRequest(
      RequestOptions options,
      RequestInterceptorHandler handler,
      ) async {
    final token = await _tokenStorage.getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(
      DioException err,
      ErrorInterceptorHandler handler,
      ) async {
    if (err.response?.statusCode == 401) {
      await _tokenStorage.clearToken();
      _onUnauthorized?.call();
    }
    handler.next(err);
  }
}
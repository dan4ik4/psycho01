import 'package:dio/dio.dart';

enum ApiFailureKind { http, timeout, network, cancelled, unknown }

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
    this.retryAfter,
  });

  final ApiFailureKind kind;
  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;
  final Duration? retryAfter;

  bool get isUnauthorized => statusCode == 401;
  bool get isConflict => statusCode == 409;
  bool get isRateLimited => statusCode == 429;

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          kind: ApiFailureKind.timeout,
          message: 'Превышено время ожидания ответа',
        );
      case DioExceptionType.cancel:
        return const ApiException(
          kind: ApiFailureKind.cancelled,
          message: 'Запрос отменен',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return const ApiException(
          kind: ApiFailureKind.network,
          message: 'Нет защищенного соединения с сервером',
        );
      case DioExceptionType.badResponse:
        return _fromResponse(error.response);
      case DioExceptionType.unknown:
        return ApiException(
          kind: ApiFailureKind.unknown,
          message: error.message ?? 'Неизвестная ошибка',
        );
    }
  }

  static ApiException _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode;
    final fields = <String, List<String>>{};
    String? message;
    Duration? retryAfter;
    final data = response?.data;

    // Парсинг заголовока Retry-After при 429
    if (status == 429 && response?.headers != null) {
      final rawHeader = response!.headers.value('retry-after');
      if (rawHeader != null) {
        final seconds = int.tryParse(rawHeader);
        if (seconds != null) {
          retryAfter = Duration(seconds: seconds);
        }
      }
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final detail = map['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List) {
        for (final raw in detail) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final loc = item['loc'];
          final path = loc is List
              ? loc.where((e) => e != 'body').map((e) => '$e').join('.')
              : 'request';
          final text = item['msg']?.toString() ?? 'Invalid value';
          fields.putIfAbsent(path.isEmpty ? 'request' : path, () => []).add(text);
        }
        message = fields.values.expand((e) => e).join('; ');
      } else if (detail is Map) {
        final detailMap = Map<String, dynamic>.from(detail);
        message = detailMap['reason']?.toString() ?? detailMap['code']?.toString();
      }
      message ??= map['error']?.toString();
    } else if (data is String && data.trim().isNotEmpty) {
      message = data;
    }

    final fallback = switch (status) {
      400 => 'Некорректный запрос',
      401 => 'Сессия истекла. Войдите снова.',
      403 => 'Недостаточно прав',
      404 => 'Объект не найден',
      409 => 'Слот уже забронирован другим пользователем. Обновите список.',
      422 => 'Проверьте введённые данные',
      429 => 'Слишком много запросов. Повторите позже',
      500 => 'Внутренняя ошибка сервера',
      502 => 'Сервис временно недоступен',
      _ => 'Ошибка запроса',
    };

    return ApiException(
      kind: ApiFailureKind.http,
      statusCode: status,
      message: (message == null || message.isEmpty) ? fallback : message,
      fieldErrors: fields,
      retryAfter: retryAfter,
    );
  }

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

Future<T> apiGuard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DioException catch (error) {
    throw ApiException.fromDio(error);
  }
}
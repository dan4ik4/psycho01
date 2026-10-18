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

  String get userMessage => switch (statusCode) {
    400 => 'Не удалось выполнить запрос. Проверьте введённые данные.',
    401 => 'Сессия завершилась. Войдите в приложение снова.',
    403 => 'У этой учётной записи пока нет доступа. Проверьте роль аккаунта.',
    404 => 'Не удалось найти нужные данные. Обновите экран.',
    409 => 'Данные изменились. Обновите экран и попробуйте ещё раз.',
    422 => 'Проверьте введённые данные и выбранное время.',
    429 => 'Слишком много запросов. Подождите немного и попробуйте снова.',
    500 || 502 || 503 => 'Сервис временно недоступен. Попробуйте позже.',
    _ when kind == ApiFailureKind.network =>
      'Нет соединения с сервером. Проверьте интернет.',
    _ when kind == ApiFailureKind.timeout =>
      'Сервер долго не отвечает. Попробуйте ещё раз.',
    _ => 'Не удалось выполнить действие. Попробуйте ещё раз.',
  };

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
          fields
              .putIfAbsent(path.isEmpty ? 'request' : path, () => [])
              .add(text);
        }
        message = fields.values.expand((e) => e).join('; ');
      } else if (detail is Map) {
        final detailMap = Map<String, dynamic>.from(detail);
        message =
            detailMap['reason']?.toString() ?? detailMap['code']?.toString();
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

    // Never display raw server details (or Dio diagnostics) directly to users.
    if (status == 400 ||
        status == 401 ||
        status == 403 ||
        status == 404 ||
        status == 409 ||
        status == 422 ||
        status == 429 ||
        (status != null && status >= 500)) {
      message = fallback;
    }

    return ApiException(
      kind: ApiFailureKind.http,
      statusCode: status,
      message: (message == null || message.isEmpty) ? fallback : message,
      fieldErrors: fields,
      retryAfter: retryAfter,
    );
  }

  @override
  String toString() => userMessage;
}

String friendlyApiError(
  Object error, {
  String fallback = 'Не удалось выполнить действие. Попробуйте ещё раз.',
}) {
  if (error is ApiException) return error.userMessage;
  if (error is DioException) return ApiException.fromDio(error).userMessage;
  return fallback;
}

Future<T> apiGuard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DioException catch (error) {
    throw ApiException.fromDio(error);
  }
}

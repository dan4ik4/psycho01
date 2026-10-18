import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/auth/token_storage.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  AuthRepository({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  Future<void> preRegister(String email, String password) async {
    try {
      await _apiClient.dio.post(
        '/auth/preregister',
        data: {'email': email, 'password': password},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> verifySignUpOtp(String email, String code) async {
    try {
      // Исправлен эндпоинт и удалено сохранение токена (возвращается 204 No Content)
      await _apiClient.dio.post(
        '/auth/confirm',
        data: {'email': email, 'otp_code': code},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> completeProfile({
    required String firstName,
    required String lastName,
    required DateTime birthDate,
  }) async {
    try {
      await _apiClient.dio.patch(
        '/users/me',
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'birth_date': birthDate.toIso8601String().split('T').first,
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<String> login(String email, String password) async {
    try {
      // Исправлен эндпоинт и формат данных (FastAPI OAuth2PasswordRequestForm)
      final response = await _apiClient.dio.post(
        '/auth/jwt/login',
        data: {'username': email, 'password': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final token = response.data?['access_token'];
      if (token != null) {
        await _tokenStorage.saveToken(token);
      }
      final user = await _apiClient.dio.get('/users/me');
      return user.data?['is_psychologist'] == true ? 'specialist' : 'client';
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _apiClient.dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> updatePassword(String token, String password) async {
    try {
      await _apiClient.dio.post(
        '/auth/reset-password',
        data: {'token': token, 'password': password},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

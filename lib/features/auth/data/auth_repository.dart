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
  })  : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  Future<void> preRegister(String email, String password) async {
    try {
      await _apiClient.dio.post('/auth/preregister', data: {
        'email': email,
        'password': password,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> verifySignUpOtp(String email, String code) async {
    try {
      // Исправлен эндпоинт и удалено сохранение токена (возвращается 204 No Content)
      await _apiClient.dio.post('/auth/confirm', data: {
        'email': email,
        'code': code,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> completeProfile({
    required String fullName,
    required String gender,
    required int age,
    required String role,
  }) async {
    try {
      await _apiClient.dio.post('/auth/complete-profile', data: {
        'full_name': fullName,
        'gender': gender,
        'age': age,
        'role': role,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<String> login(String email, String password) async {
    try {
      // Исправлен эндпоинт и формат данных (FastAPI OAuth2PasswordRequestForm)
      final response = await _apiClient.dio.post(
        '/auth/jwt/login',
        data: FormData.fromMap({
          'username': email,
          'password': password,
        }),
      );

      final token = response.data?['access_token'];
      if (token != null) {
        await _tokenStorage.saveToken(token);
      }

      return response.data?['role'] ?? 'client';
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _apiClient.dio.post('/auth/forgot-password', data: {
        'email': email,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> verifyResetOtp(String email, String code) async {
    try {
      final response = await _apiClient.dio.post('/auth/verify-reset-otp', data: {
        'email': email,
        'code': code,
      });
      final token = response.data?['access_token'];
      if (token != null) {
        await _tokenStorage.saveToken(token);
      }
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> updatePassword(String password) async {
    try {
      await _apiClient.dio.post('/auth/reset-password', data: {
        'password': password,
      });
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
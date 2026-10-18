import '../../../core/api/api_client.dart';
import '../../../core/auth/token_storage.dart';

class ProfileRepository {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  // Исправлено: Конструктор теперь требует явной передачи зависимостей
  ProfileRepository({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  }) : _apiClient = apiClient,
       _tokenStorage = tokenStorage;

  Future<Map<String, dynamic>> fetchUserProfile() async {
    final response = await _apiClient.dio.get('/users/me');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> fetchPsychologistProfile() async {
    final response = await _apiClient.dio.get('/psychologists/me');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    await _apiClient.dio.patch('/users/me', data: data);
  }

  Future<void> updatePsychologistProfile(Map<String, dynamic> data) async {
    await _apiClient.dio.patch('/psychologists/me', data: data);
  }

  Future<void> logout() async {
    try {
      await _tokenStorage.clearToken();
    } catch (_) {}
  }
}

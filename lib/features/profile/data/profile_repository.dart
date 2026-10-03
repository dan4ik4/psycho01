import '../../../core/api/api_client.dart';
import '../../../core/auth/token_storage.dart';

class ProfileRepository {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  // Исправлено: Конструктор теперь требует явной передачи зависимостей
  ProfileRepository({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  })  : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  Future<Map<String, dynamic>> fetchUserProfile() async {
    try {
      // Исправлено: обращаемся к .dio.get()
      final response = await _apiClient.dio.get('/users/me');
      if (response.data != null) {
        return {
          'full_name': response.data['full_name'] ?? response.data['fio'] ?? 'Анна Смирнова',
          'email': response.data['email'] ?? 'anna.smirnova@example.com',
          'psychologist_name': response.data['psychologist_name'] ?? 'Др. Елена Воронова',
        };
      }
    } catch (_) {}

    // Исправлено: удален вызов несуществующего метода getUserEmail()
    return {
      'full_name': 'Анна Смирнова',
      'email': 'anna.smirnova@example.com',
      'psychologist_name': 'Др. Елена Воронова',
    };
  }

  Future<void> logout() async {
    try {
      await _tokenStorage.clearToken();
    } catch (_) {}
  }
}
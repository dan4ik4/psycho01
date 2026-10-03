import '../../../core/api/api_client.dart';
import 'package:dio/dio.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final DateTime timestamp;

  ChatMessage({required this.id, required this.text, required this.isMe, required this.timestamp});
}

class ChatRepository {
  final ApiClient _apiClient;

  ChatRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<ChatMessage>> fetchHistory(String sessionId) async {
    try {
      final response = await _apiClient.dio.get('/chat/$sessionId/messages');
      // Временная заглушка парсинга для UI
      return [];
    } on DioException catch (_) {
      // Имитация данных при ошибке сервера
      return [
        ChatMessage(id: '1', text: 'Здравствуйте, как прошла неделя?', isMe: false, timestamp: DateTime.now().subtract(const Duration(minutes: 5))),
        ChatMessage(id: '2', text: 'Немного тревожно, но справляюсь.', isMe: true, timestamp: DateTime.now()),
      ];
    }
  }

  Future<void> sendMessage(String sessionId, String text) async {
    try {
      await _apiClient.dio.post('/chat/$sessionId/messages', data: {'text': text});
    } catch (_) {}
  }
}
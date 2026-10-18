import 'package:uuid/uuid.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isMe;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.isMe,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'].toString(),
    text: json['content']?.toString() ?? '',
    isMe: json['role'] == 'user',
    timestamp:
        DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

class ChatConversation {
  final String id;
  final String name;
  final String mode;
  final DateTime createdAt;
  final List<ChatMessage> messages;

  const ChatConversation({
    required this.id,
    required this.name,
    required this.mode,
    required this.createdAt,
    this.messages = const [],
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'Чат',
        mode: json['mode']?.toString() ?? 'self_help',
        createdAt:
            DateTime.tryParse(
              json['created_at']?.toString() ?? '',
            )?.toLocal() ??
            DateTime.now(),
        messages: (json['messages'] as List? ?? const [])
            .map(
              (item) =>
                  ChatMessage.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(),
      );
}

class ChatRepository {
  final ApiClient _apiClient;
  final Uuid _uuid = const Uuid();

  ChatRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  Future<List<ChatConversation>> fetchConversations() => apiGuard(() async {
    final response = await _apiClient.dio.get('/ai/conversations');
    return (response.data as List)
        .map(
          (item) =>
              ChatConversation.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  });

  Future<ChatConversation> createConversation(
    String name, {
    String mode = 'self_help',
  }) => apiGuard(() async {
    final response = await _apiClient.dio.post(
      '/ai/conversations',
      data: {'mode': mode, if (name.trim().isNotEmpty) 'name': name.trim()},
    );
    return ChatConversation.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  });

  Future<ChatConversation> fetchConversation(String conversationId) =>
      apiGuard(() async {
        final response = await _apiClient.dio.get(
          '/ai/conversations/$conversationId',
        );
        return ChatConversation.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      });

  Future<void> renameConversation(String conversationId, String name) =>
      apiGuard(() async {
        await _apiClient.dio.patch(
          '/ai/conversations/$conversationId',
          data: {'name': name.trim()},
        );
      });

  Future<List<ChatMessage>> sendMessage(
    String conversationId,
    String text, {
    String? requestId,
  }) => apiGuard(() async {
    final response = await _apiClient.dio.post(
      '/ai/conversations/$conversationId/messages',
      data: {'request_id': requestId ?? _uuid.v4(), 'content': text.trim()},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return [
      ChatMessage.fromJson(
        Map<String, dynamic>.from(data['user_message'] as Map),
      ),
      ChatMessage.fromJson(
        Map<String, dynamic>.from(data['assistant_message'] as Map),
      ),
    ];
  });
}

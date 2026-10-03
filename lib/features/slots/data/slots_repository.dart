import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

enum SlotStatus { free, booked, reserved, cancelled }

class SlotModel {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final SlotStatus status;

  SlotModel({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  bool get isBooked => status == SlotStatus.booked || status == SlotStatus.reserved;

  factory SlotModel.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status']?.toString().toLowerCase() ?? 'free';
    final status = switch (statusStr) {
      'booked' => SlotStatus.booked,
      'reserved' => SlotStatus.reserved,
      'cancelled' => SlotStatus.cancelled,
      _ => SlotStatus.free,
    };

    return SlotModel(
      id: json['id']?.toString() ?? '',
      startTime: DateTime.parse(json['start_at']).toUtc().toLocal(),
      endTime: DateTime.parse(json['end_at'] ?? json['start_at']).toUtc().toLocal(),
      status: status,
    );
  }
}

class SlotsRepository {
  final ApiClient _apiClient;

  SlotsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Получение доступных слотов психолога
  Future<List<SlotModel>> fetchAvailableSlots(String psychologistId) async {
    return apiGuard(() async {
      final response = await _apiClient.dio.get('/psychologists/$psychologistId/slots');
      final List data = response.data ?? [];
      return data.map((e) => SlotModel.fromJson(Map<String, dynamic>.from(e))).toList();
    });
  }

  /// Бронирование слота
  /// В случае конфликта (409) выбрасывает ApiException с isConflict == true
  Future<void> bookSlot(String slotId) async {
    return apiGuard(() async {
      await _apiClient.dio.post('/slots/$slotId/book');
    });
  }
}
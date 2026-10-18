import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import 'package:uuid/uuid.dart';

enum SlotStatus { free, booked, reserved, cancelled }

class SlotModel {
  final String id;
  final String psychologistId;
  final DateTime startTime;
  final DateTime endTime;
  final SlotStatus status;

  SlotModel({
    required this.id,
    required this.psychologistId,
    required this.startTime,
    required this.endTime,
    required this.status,
  });

  bool get isBooked =>
      status == SlotStatus.booked || status == SlotStatus.reserved;

  factory SlotModel.fromJson(Map<String, dynamic> json) {
    return SlotModel(
      id: json['id']?.toString() ?? '',
      psychologistId: json['psychologist_id']?.toString() ?? '',
      startTime: DateTime.parse(json['start_at'].toString()).toLocal(),
      endTime: DateTime.parse(json['end_at'].toString()).toLocal(),
      status: SlotStatus.free,
    );
  }
}

class SlotsRepository {
  final ApiClient _apiClient;

  SlotsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Получение доступных слотов психолога
  Future<List<SlotModel>> fetchAvailableSlots([String? psychologistId]) async {
    return apiGuard(() async {
      final response = await _apiClient.dio.get('/slots/available');
      final List data = response.data ?? [];
      return data
          .map((e) => SlotModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  /// Бронирование слота
  /// В случае конфликта (409) выбрасывает ApiException с isConflict == true
  Future<void> bookSlot(String slotId, {String? requestId}) async {
    return apiGuard(() async {
      await _apiClient.dio.post(
        '/slots/$slotId/book',
        data: {'request_id': requestId ?? const Uuid().v4()},
      );
    });
  }

  Future<void> cancelBooking(String slotId) async {
    return apiGuard(() async {
      await _apiClient.dio.post('/slots/$slotId/cancel', data: const {});
    });
  }
}

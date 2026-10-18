import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';

class ClientCarePlanCard extends StatefulWidget {
  final ApiClient apiClient;

  const ClientCarePlanCard({super.key, required this.apiClient});

  @override
  State<ClientCarePlanCard> createState() => _ClientCarePlanCardState();
}

class _ClientCarePlanCardState extends State<ClientCarePlanCard> {
  static const _purple = Color(0xFF7862D6);
  static const _ink = Color(0xFF323045);
  static const _muted = Color(0xFF706D8C);

  bool _loading = true;
  bool _hasActiveAssignment = false;
  bool _planMissing = false;
  String? _recommendations;
  String? _eventType;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasActiveAssignment = false;
    });
    try {
      final assignmentResponse = await widget.apiClient.dio.get(
        '/patient-assignments/my',
      );
      if (assignmentResponse.data is! Map) {
        if (mounted) {
          setState(() {
            _hasActiveAssignment = false;
            _loading = false;
          });
        }
        return;
      }

      final assignment = Map<String, dynamic>.from(
        assignmentResponse.data as Map,
      );
      final latest = Map<String, dynamic>.from(
        assignment['latest_event'] as Map? ?? const {},
      );
      if (latest['event_type']?.toString().toLowerCase() != 'accepted') {
        if (mounted) {
          setState(() {
            _hasActiveAssignment = false;
            _loading = false;
          });
        }
        return;
      }

      final assignmentId = assignment['id']?.toString();
      if (assignmentId == null || assignmentId.isEmpty) {
        throw const FormatException('Не найден номер работы с психологом');
      }

      if (mounted) setState(() => _hasActiveAssignment = true);
      final response = await widget.apiClient.dio.get(
        '/ai/care-plans/$assignmentId/patient',
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;
      setState(() {
        _recommendations = data['patient_recommendations']?.toString();
        _eventType = data['event_type']?.toString().toLowerCase();
        _planMissing = false;
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 404) {
        setState(() {
          _hasActiveAssignment = true;
          _planMissing = true;
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = error.response?.statusCode == 403
            ? 'Не удалось открыть рекомендации. Попросите психолога проверить, что план активирован, и сообщите в поддержку приложения о проблеме с доступом.'
            : friendlyApiError(error);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_hasActiveAssignment) return const SizedBox.shrink();

    final message =
        _error ??
        (_planMissing
            ? 'Психолог ещё не добавил рекомендации. Когда план будет активирован, он появится здесь.'
            : (_recommendations?.trim().isNotEmpty == true
                  ? _recommendations!.trim()
                  : 'Психолог пока не добавил рекомендации для вас.'));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FD),
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE8E3FA),
                  child: Icon(Icons.favorite_rounded, color: _purple),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Рекомендации психолога',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: _loading ? null : _loadPlan,
                  icon: const Icon(Icons.refresh_rounded, color: _purple),
                ),
              ],
            ),
            ...[
              if (_eventType != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    switch (_eventType) {
                      'activated' => 'План активен',
                      'paused' => 'План на паузе',
                      'completed' => 'План завершён',
                      _ => 'Ваш план поддержки',
                    },
                    style: const TextStyle(
                      color: _purple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Text(
                message,
                style: TextStyle(
                  color: _error == null ? _muted : const Color(0xFFB3261E),
                  height: 1.45,
                ),
              ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _loadPlan,
                    child: const Text('Повторить'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

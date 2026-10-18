import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/widgets/oakle_notice.dart';
import 'dart:convert';

const Color kDeepPurple = Color(0xFFB0A6E8);
const Color kAccentPurple = Color(0xFF7862D6);
const Color kWarmWhite = Color(0xFFF6F8FD);
const Color kTextPrimary = Color(0xFF323045);
const Color kTextSecondary = Color(0xFF706D8C);
const Color kWeekendRed = Color(0xFFFF8A80);

class PsychologistDashboard extends StatefulWidget {
  final ApiClient apiClient;
  final int initialTab;
  const PsychologistDashboard({
    super.key,
    required this.apiClient,
    this.initialTab = 0,
  });

  @override
  _PsychologistDashboardState createState() => _PsychologistDashboardState();
}

class _PsychologistDashboardState extends State<PsychologistDashboard> {
  double sessionPrice = 0.0;
  int sessionDurationMinutes = 60;
  String? _priceAccessMessage;
  bool _priceLoaded = false;

  DateTime visibleMonth = DateTime.now();
  DateTime? _selectedDate;
  int _calendarSlideDirection = 0;
  final DateTime now = DateTime.now();

  int _selectedTab = 0; // 0 - Расписание, 1 - Клиенты

  Map<String, List<String>> _availableSlots = {};
  final Map<String, String> _slotIdsByDateAndTime = {};
  Map<String, List<Map<String, dynamic>>> _bookedVisits = {};

  Map<int, List<String>> _weeklyTemplate = {
    1: [],
    2: [],
    3: [],
    4: [],
    5: [],
    6: [],
    7: [],
  };

  // State Machine variables
  List<Map<String, dynamic>> _incomingRequests = [];
  List<Map<String, dynamic>> _activeClients = [];

  final List<String> _monthNames = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  final List<String> _fullWeekDaysGenitive = [
    'понедельника',
    'вторника',
    'среды',
    'четверга',
    'пятницы',
    'субботы',
    'воскресенья',
  ];

  final List<String> _weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final templateStr = prefs.getString('doc_template');
    final nextTemplate = <int, List<String>>{
      1: [],
      2: [],
      3: [],
      4: [],
      5: [],
      6: [],
      7: [],
    };
    if (templateStr != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(templateStr);
        nextTemplate.addAll(
          decoded.map(
            (key, value) => MapEntry(int.parse(key), List<String>.from(value)),
          ),
        );
      } catch (_) {}
    }

    final nextSlots = <String, List<String>>{};
    final nextSlotIds = <String, String>{};
    final nextBookedVisits = <String, List<Map<String, dynamic>>>{};
    final nextIncoming = <Map<String, dynamic>>[];
    final nextActive = <Map<String, dynamic>>[];
    final failedLists = <String>[];
    double nextPrice = sessionPrice;
    try {
      Future<List<dynamic>> fetchList(String path) async {
        try {
          final response = await widget.apiClient.dio.get(path);
          return response.data is List ? response.data as List<dynamic> : [];
        } catch (error) {
          debugPrint('Could not load $path: $error');
          failedLists.add(path);
          return [];
        }
      }

      final responses = await Future.wait([
        fetchList('/slots/my'),
        fetchList('/slots/booked'),
        fetchList('/patient-assignments/incoming'),
        fetchList('/patient-assignments/active'),
      ]);
      final bookedSlotIds = responses[1]
          .whereType<Map>()
          .map((slot) => slot['id']?.toString())
          .whereType<String>()
          .toSet();
      for (final raw in responses[0]) {
        final slot = Map<String, dynamic>.from(raw as Map);
        // `/slots/my` contains all slots and doesn't distinguish availability.
        // Exclude IDs returned by `/slots/booked` so booked appointments are
        // never presented as open times in the psychologist's calendar.
        if (bookedSlotIds.contains(slot['id']?.toString())) continue;
        final start = DateTime.parse(slot['start_at'].toString()).toLocal();
        final end = DateTime.parse(slot['end_at'].toString()).toLocal();
        final date = _formatToYMD(start);
        final label =
            '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
        nextSlots.putIfAbsent(date, () => []).add(label);
        nextSlotIds['$date|$label'] = slot['id'].toString();
      }
      for (final raw in responses[1]) {
        final slot = Map<String, dynamic>.from(raw as Map);
        final start = DateTime.parse(slot['start_at'].toString()).toLocal();
        final date = _formatToYMD(start);
        final end = DateTime.parse(slot['end_at'].toString()).toLocal();
        final label =
            '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} - ${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
        nextBookedVisits.putIfAbsent(date, () => []).add({
          'id': slot['id'],
          'time': label,
          'patientName': 'Запись',
        });
      }
      for (final raw in responses[2]) {
        nextIncoming.add(
          _assignmentUiModel(Map<String, dynamic>.from(raw as Map)),
        );
      }
      for (final raw in responses[3]) {
        nextActive.add(
          _assignmentUiModel(Map<String, dynamic>.from(raw as Map)),
        );
      }
      try {
        final billing = await widget.apiClient.dio.get(
          '/billing/psychologist/me',
        );
        if (billing.data is Map && billing.data['hourly_net_minor'] is num) {
          nextPrice =
              (billing.data['hourly_net_minor'] as num).toDouble() / 100;
          _priceLoaded = true;
          _priceAccessMessage = null;
        }
      } catch (error) {
        _priceAccessMessage = friendlyApiError(error);
      }
    } catch (error) {
      if (mounted) {
        showOakleNotice(
          context,
          friendlyApiError(
            error,
            fallback:
                'Не удалось загрузить расписание. Проверьте, что аккаунту выдана роль психолога.',
          ),
          isError: true,
        );
      }
    }

    if (!mounted) return;
    setState(() {
      sessionPrice = nextPrice;
      sessionDurationMinutes = prefs.getInt('doc_session_duration') ?? 60;
      _weeklyTemplate = nextTemplate;
      _availableSlots = nextSlots;
      _slotIdsByDateAndTime
        ..clear()
        ..addAll(nextSlotIds);
      _bookedVisits = nextBookedVisits;
      _incomingRequests.clear();
      _activeClients.clear();
      _incomingRequests.addAll(nextIncoming);
      _activeClients.addAll(nextActive);
    });
    if (failedLists.isNotEmpty && mounted) {
      final scheduleFailed = failedLists.any((path) => path == '/slots/my');
      showOakleNotice(
        context,
        scheduleFailed
            ? 'Сервер не отдал ваше расписание. Проверьте, что администратор назначил аккаунту роль психолога.'
            : 'Часть данных не загрузилась. Обновите экран чуть позже.',
        isError: true,
      );
    }
  }

  Map<String, dynamic> _assignmentUiModel(Map<String, dynamic> data) {
    final event = Map<String, dynamic>.from(
      data['latest_event'] as Map? ?? const {},
    );
    final patient = Map<String, dynamic>.from(
      data['patient'] as Map? ?? const {},
    );
    final firstName =
        data['patient_first_name'] ?? patient['first_name'] ?? patient['name'];
    final lastName = data['patient_last_name'] ?? patient['last_name'];
    final fullName = [firstName, lastName]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .join(' ');
    return {
      ...data,
      'status': event['event_type']?.toString().toLowerCase() ?? '',
      'requestComment': event['comment'] ?? '',
      'clientName': fullName.isEmpty ? 'Клиент' : fullName,
    };
  }

  Future<void> _updateAssignmentStatus(
    Map<String, dynamic> assignment,
    String newStatus, {
    String? commentField,
    String? commentValue,
  }) async {
    final id = assignment['id']?.toString();
    if (id == null) return;
    try {
      if (newStatus == 'accepted') {
        await widget.apiClient.dio.post('/patient-assignments/$id/accept');
      } else if (newStatus == 'rejected') {
        await widget.apiClient.dio.post(
          '/patient-assignments/$id/reject',
          data: {'comment': commentValue ?? 'Заявка отклонена'},
        );
      } else if (newStatus == 'finished') {
        await widget.apiClient.dio.post(
          '/patient-assignments/$id/finish',
          data: {'comment': commentValue ?? 'Работа завершена'},
        );
      }
      await _loadData();
    } catch (error) {
      if (mounted) {
        showOakleNotice(context, friendlyApiError(error), isError: true);
      }
    }
  }

  Future<bool> _savePrice(double price) async {
    try {
      await widget.apiClient.dio.patch(
        '/billing/psychologist/me',
        data: {'hourly_net_minor': (price * 100).round()},
      );
      if (!mounted) return false;
      setState(() {
        sessionPrice = price;
        _priceLoaded = true;
        _priceAccessMessage = null;
      });
      showOakleNotice(context, 'Стоимость сохранена');
      return true;
    } catch (error) {
      if (mounted) {
        showOakleNotice(
          context,
          friendlyApiError(
            error,
            fallback:
                'Не удалось сохранить цену. Проверьте доступ психолога к разделу оплаты.',
          ),
          isError: true,
        );
      }
      return false;
    }
  }

  Future<void> _saveSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'doc_template',
      jsonEncode(
        _weeklyTemplate.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }

  Future<void> _createApiSlot(String date, String interval) async {
    final parts = interval.split(' - ');
    if (parts.length != 2) return;
    final startParts = parts[0].split(':').map(int.parse).toList();
    final endParts = parts[1].split(':').map(int.parse).toList();
    final day = DateTime.parse(date);
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      startParts[0],
      startParts[1],
    );
    var end = DateTime(day.year, day.month, day.day, endParts[0], endParts[1]);
    if (!end.isAfter(start)) {
      end = DateTime(
        day.year,
        day.month,
        day.day + 1,
        endParts[0],
        endParts[1],
      );
    }
    if (end.difference(start).inMinutes < 15) {
      throw const FormatException('Сеанс должен длиться не менее 15 минут');
    }
    final response = await widget.apiClient.dio.post(
      '/slots/create',
      data: {
        'start_at': start.toUtc().toIso8601String(),
        'end_at': end.toUtc().toIso8601String(),
      },
    );
    if (response.data is Map && response.data['id'] != null) {
      _slotIdsByDateAndTime['$date|$interval'] = response.data['id'].toString();
    }
  }

  Future<void> _removeApiSlot(String date, String interval) async {
    final id = _slotIdsByDateAndTime['$date|$interval'];
    if (id == null) return;
    await widget.apiClient.dio.post('/slots/$id/remove', data: const {});
    _slotIdsByDateAndTime.remove('$date|$interval');
  }

  String _formatToYMD(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  void _changeMonth({required int delta}) {
    setState(() {
      _calendarSlideDirection = delta > 0 ? 1 : -1;
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    });
  }

  List<DateTime> _buildGridDates(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final int startOffset = (first.weekday - 1);
    final DateTime gridStart = DateTime(
      month.year,
      month.month,
      1,
    ).subtract(Duration(days: startOffset));
    // Construct each civil date instead of adding 24-hour durations. Across
    // the autumn DST change, adding Duration(days: 1) can repeat a local day.
    final all = List<DateTime>.generate(
      42,
      (i) => DateTime(gridStart.year, gridStart.month, gridStart.day + i),
    );
    final weeks = <List<DateTime>>[];
    for (int i = 0; i < 42; i += 7) {
      weeks.add(all.sublist(i, i + 7));
    }
    weeks.removeWhere((week) => week.every((d) => d.month != month.month));
    return weeks.expand((w) => w).toList();
  }

  String _calculateInterval(String startTime, int durationMinutes) {
    try {
      final parts = startTime.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final startDt = DateTime(2020, 1, 1, hour, minute);
      final endDt = startDt.add(Duration(minutes: durationMinutes));
      final endHour = endDt.hour.toString().padLeft(2, '0');
      final endMinute = endDt.minute.toString().padLeft(2, '0');
      return "$startTime - $endHour:$endMinute";
    } catch (e) {
      return startTime;
    }
  }

  void _applyTemplateToMonth() {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final lastDay = DateTime(visibleMonth.year, visibleMonth.month + 1, 0);

    setState(() {
      for (int i = 0; i < lastDay.day; i++) {
        final d = DateTime(firstDay.year, firstDay.month, firstDay.day + i);
        final dateStr = _formatToYMD(d);

        final templateForDay = _weeklyTemplate[d.weekday] ?? [];
        final bookedTimes = (_bookedVisits[dateStr] ?? [])
            .map((b) => b['time'] as String)
            .toList();

        final newSlots = {...templateForDay, ...bookedTimes}.toList();
        newSlots.sort((a, b) => a.compareTo(b));

        if (newSlots.isNotEmpty) {
          _availableSlots[dateStr] = newSlots;
        } else {
          _availableSlots.remove(dateStr);
        }
      }
    });
    _saveSchedule();
    () async {
      try {
        final now = DateTime.now();
        final bookedKeys = <String>{};
        for (final entry in _bookedVisits.entries) {
          for (final booking in entry.value) {
            bookedKeys.add('${entry.key}|${booking['time']}');
          }
        }
        for (final entry in _availableSlots.entries) {
          for (final interval in entry.value) {
            final key = '${entry.key}|$interval';
            final parts = interval.split(' - ');
            if (parts.length != 2 ||
                bookedKeys.contains(key) ||
                _slotIdsByDateAndTime.containsKey(key)) {
              continue;
            }
            final startParts = parts.first.split(':').map(int.parse).toList();
            final day = DateTime.parse(entry.key);
            final start = DateTime(
              day.year,
              day.month,
              day.day,
              startParts[0],
              startParts[1],
            );
            if (!start.isAfter(now)) continue;
            await _createApiSlot(entry.key, interval);
          }
        }
        if (mounted) showOakleNotice(context, 'Расписание опубликовано');
        await _loadData();
      } catch (error) {
        if (mounted) {
          showOakleNotice(
            context,
            friendlyApiError(
              error,
              fallback:
                  'Не удалось полностью опубликовать расписание. Проверьте, что выбранное время ещё не прошло и аккаунту выдана роль психолога.',
            ),
            isError: true,
          );
        }
      }
    }();
  }

  Future<void> _pickTime(
    BuildContext context,
    Function(String) onTimePicked,
  ) async {
    final now = TimeOfDay.now();
    int selectedHour = now.hour;
    int selectedMinute = now.minute;

    final FixedExtentScrollController hourController =
        FixedExtentScrollController(initialItem: selectedHour);
    final FixedExtentScrollController minuteController =
        FixedExtentScrollController(initialItem: selectedMinute);

    await showModalBottomSheet(
      context: context,
      backgroundColor: kWarmWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Выберите время",
                    style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    height: 160,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 75,
                          child: ListWheelScrollView.useDelegate(
                            controller: hourController,
                            itemExtent: 50,
                            perspective: 0.002,
                            diameterRatio: 1.5,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: (index) {
                              setModalState(() => selectedHour = index);
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 24,
                              builder: (context, index) {
                                final isSelected = index == selectedHour;
                                return Center(
                                  child: Text(
                                    index.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: isSelected ? 32 : 24,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? kAccentPurple
                                          : kTextSecondary.withOpacity(0.4),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            ":",
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: kAccentPurple.withOpacity(0.8),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 75,
                          child: ListWheelScrollView.useDelegate(
                            controller: minuteController,
                            itemExtent: 50,
                            perspective: 0.002,
                            diameterRatio: 1.5,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: (index) {
                              setModalState(() => selectedMinute = index);
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 60,
                              builder: (context, index) {
                                final isSelected = index == selectedMinute;
                                return Center(
                                  child: Text(
                                    index.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: isSelected ? 32 : 24,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? kAccentPurple
                                          : kTextSecondary.withOpacity(0.4),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Отмена",
                            style: TextStyle(
                              color: kTextSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAccentPurple,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            final formattedTime =
                                "${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}";
                            onTimePicked(formattedTime);
                            Navigator.pop(context);
                          },
                          child: const Text(
                            "Готово",
                            style: TextStyle(
                              color: kWarmWhite,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showPriceEditor() {
    TextEditingController controller = TextEditingController(
      text: sessionPrice.toInt().toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kWarmWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Установить стоимость",
          style: TextStyle(color: kTextPrimary, fontSize: 18),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          decoration: const InputDecoration(suffixText: "₽"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Отмена",
              style: TextStyle(color: kTextSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccentPurple),
            onPressed: () async {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value <= 0) {
                showOakleNotice(
                  context,
                  'Введите цену больше нуля',
                  isError: true,
                );
                return;
              }
              final saved = await _savePrice(value);
              if (saved && mounted && ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Сохранить", style: TextStyle(color: kWarmWhite)),
          ),
        ],
      ),
    );
  }

  void _showRejectOrFinishDialog(Map<String, dynamic> req, bool isReject) {
    TextEditingController commentCtrl = TextEditingController();

    // Быстрые ответы
    final List<String> finishReplies = [
      "Терапия успешно завершена",
      "Цели терапии достигнуты",
      "Клиент решил приостановить работу",
      "Проблема решена, прогресс стабилен",
      "Перенаправлен к другому специалисту",
    ];

    final List<String> rejectReplies = [
      "К сожалению, нет свободных мест",
      "Не работаю с данным запросом",
      "Запрос вне моей компетенции",
    ];

    final List<String> currentReplies = isReject
        ? rejectReplies
        : finishReplies;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        // Динамический отступ для клавиатуры
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          // Делаем окно прокручиваемым на случай маленьких экранов
          child: Container(
            decoration: const BoxDecoration(
              color: kDeepPurple,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: kWarmWhite.withOpacity(0.9),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min, // Окно занимает только нужное место
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isReject ? "Отклонение заявки" : "Завершение работы",
                    style: const TextStyle(
                      color: kTextPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isReject
                        ? "Укажите причину отказа"
                        : "Оставьте обязательный комментарий о завершении терапии",
                    style: const TextStyle(color: kTextSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 15),

                  // Блок с быстрыми ответами (используем Wrap для переноса строк)
                  Wrap(
                    spacing: 8.0, // Горизонтальный отступ между плашками
                    runSpacing: 10.0, // Вертикальный отступ между строками
                    children: currentReplies
                        .map(
                          (reply) => GestureDetector(
                            onTap: () {
                              commentCtrl.text = reply;
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isReject
                                    ? kWeekendRed.withOpacity(0.1)
                                    : kAccentPurple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isReject
                                      ? kWeekendRed.withOpacity(0.3)
                                      : kAccentPurple.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                reply,
                                style: TextStyle(
                                  color: isReject ? kWeekendRed : kAccentPurple,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: commentCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: kTextPrimary),
                    decoration: InputDecoration(
                      hintText: "Напишите здесь или выберите вариант выше...",
                      filled: true,
                      fillColor: kDeepPurple.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isReject ? kWeekendRed : kAccentPurple,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () {
                        if (commentCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isReject
                                    ? "Укажите причину отказа"
                                    : "Пожалуйста, оставьте комментарий для завершения",
                              ),
                            ),
                          );
                          return;
                        }
                        _updateAssignmentStatus(
                          req,
                          isReject ? 'rejected' : 'finished',
                          commentField: isReject
                              ? 'rejectComment'
                              : 'finishComment',
                          commentValue: commentCtrl.text.trim(),
                        );
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        isReject ? "Отклонить заявку" : "Завершить работу",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showTreatmentPlanDialog(Map<String, dynamic> client) async {
    final aiInstructions = TextEditingController();
    final patientRecommendations = TextEditingController();
    final assignmentId = client['id']?.toString();
    if (assignmentId == null) {
      aiInstructions.dispose();
      patientRecommendations.dispose();
      return;
    }
    var hasPlan = false;
    try {
      final response = await widget.apiClient.dio.get(
        '/ai/care-plans/$assignmentId/psychologist',
      );
      final payload = Map<String, dynamic>.from(response.data as Map);
      final latestVersion = Map<String, dynamic>.from(
        payload['latest_version'] as Map,
      );
      aiInstructions.text =
          latestVersion['instructions_for_ai']?.toString() ?? '';
      patientRecommendations.text =
          latestVersion['patient_recommendations']?.toString() ?? '';
      hasPlan = true;
    } catch (error) {
      if (error is! DioException || error.response?.statusCode != 404) {
        aiInstructions.dispose();
        patientRecommendations.dispose();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                friendlyApiError(
                  error,
                  fallback:
                      'Не удалось загрузить план. Обновите список клиентов и попробуйте ещё раз.',
                ),
              ),
            ),
          );
        }
        return;
      }
    }
    if (!mounted) {
      aiInstructions.dispose();
      patientRecommendations.dispose();
      return;
    }
    var isSaving = false;
    var didClose = false;
    String? saveError;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            decoration: const BoxDecoration(
              color: kWarmWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'План лечения',
                      style: TextStyle(
                        color: kTextPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Пациент: ${client['clientName'] ?? 'ID ${client['patient_id'] ?? ''}'}',
                      style: const TextStyle(color: kTextSecondary),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Инструкции для ИИ',
                      style: TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: aiInstructions,
                      maxLines: 4,
                      maxLength: 10000,
                      decoration: const InputDecoration(
                        hintText: 'Что ИИ должен учитывать в беседе?',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Рекомендации пациенту',
                      style: TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: patientRecommendations,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Рекомендации, которые увидит пациент',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (saveError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE9E8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          saveError!,
                          style: const TextStyle(color: Color(0xFFB3261E)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAccentPurple,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: () async {
                          if (isSaving) return;
                          isSaving = true;
                          setModalState(() {
                            isSaving = true;
                            saveError = null;
                          });
                          final instructions = aiInstructions.text.trim();
                          final recommendations = patientRecommendations.text
                              .trim();
                          try {
                            late Map<String, dynamic> version;
                            if (hasPlan) {
                              final response = await widget.apiClient.dio.post(
                                '/ai/care-plans/$assignmentId/versions',
                                data: {
                                  'instructions_for_ai': instructions,
                                  'patient_recommendations':
                                      recommendations.isEmpty
                                      ? null
                                      : recommendations,
                                },
                              );
                              version = Map<String, dynamic>.from(
                                response.data as Map,
                              );
                            } else {
                              final response = await widget.apiClient.dio.post(
                                '/ai/care-plans',
                                data: {
                                  'assignment_id': assignmentId,
                                  'instructions_for_ai': instructions,
                                  'patient_recommendations':
                                      recommendations.isEmpty
                                      ? null
                                      : recommendations,
                                },
                              );
                              final planResponse = Map<String, dynamic>.from(
                                response.data as Map,
                              );
                              version = Map<String, dynamic>.from(
                                planResponse['latest_version'] as Map,
                              );
                              hasPlan = true;
                            }
                            final versionId = version['id']?.toString();
                            if (versionId == null || versionId.isEmpty) {
                              throw StateError(
                                'Сервер сохранил план, но не вернул его версию для активации.',
                              );
                            }
                            await widget.apiClient.dio.post(
                              '/ai/care-plans/$assignmentId/activate',
                              data: {'version_id': versionId},
                            );
                            client['treatmentPlan'] = instructions;
                            client['patientRecommendations'] = recommendations;
                            if (!mounted || !ctx.mounted) return;
                            didClose = true;
                            Navigator.pop(ctx);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                showOakleNotice(
                                  context,
                                  'План сохранён и активирован',
                                );
                              }
                            });
                          } catch (error) {
                            if (mounted && ctx.mounted) {
                              setModalState(
                                () => saveError =
                                    'Не удалось сохранить и активировать план. ${friendlyApiError(error)}',
                              );
                            }
                          } finally {
                            if (mounted && ctx.mounted && !didClose) {
                              setModalState(() => isSaving = false);
                            } else {
                              isSaving = false;
                            }
                          }
                        },
                        child: isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Сохранить и активировать',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      aiInstructions.dispose();
      patientRecommendations.dispose();
    });
  }

  void _showWeeklyTemplateEditor() {
    int selectedWeekday = 1;
    TextEditingController durationController = TextEditingController(
      text: sessionDurationMinutes.toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final daySlots = _weeklyTemplate[selectedWeekday] ?? [];
          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: kDeepPurple,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Шаблон",
                      style: TextStyle(
                        color: kWarmWhite,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: kWarmWhite),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Длительность (мин):",
                      style: TextStyle(
                        color: kWarmWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      width: 90,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: kWarmWhite.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: kWarmWhite,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null && parsed >= 15) {
                            setModalState(
                              () => sessionDurationMinutes = parsed,
                            );
                            setState(() => sessionDurationMinutes = parsed);
                            SharedPreferences.getInstance().then(
                              (prefs) =>
                                  prefs.setInt('doc_session_duration', parsed),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (index) {
                    final dayNum = index + 1;
                    final isSel = selectedWeekday == dayNum;
                    return GestureDetector(
                      onTap: () =>
                          setModalState(() => selectedWeekday = dayNum),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? kAccentPurple
                              : kWarmWhite.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          _weekDays[index],
                          style: TextStyle(
                            color: isSel
                                ? kWarmWhite
                                : kWarmWhite.withOpacity(0.9),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                Text(
                  "Время для ${_fullWeekDaysGenitive[selectedWeekday - 1]}",
                  style: const TextStyle(
                    color: kWarmWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kWarmWhite.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SingleChildScrollView(
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 2.8,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                        itemCount: daySlots.length + 1,
                        itemBuilder: (context, index) {
                          if (index == daySlots.length) {
                            return InkWell(
                              onTap: () {
                                _pickTime(context, (time) {
                                  final interval = _calculateInterval(
                                    time,
                                    sessionDurationMinutes,
                                  );
                                  setModalState(() {
                                    if (!(_weeklyTemplate[selectedWeekday]
                                            ?.contains(interval) ??
                                        false)) {
                                      _weeklyTemplate[selectedWeekday]?.add(
                                        interval,
                                      );
                                      _weeklyTemplate[selectedWeekday]?.sort(
                                        (a, b) => a.compareTo(b),
                                      );
                                    }
                                  });
                                  _saveSchedule();
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: kWarmWhite,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      color: kTextPrimary,
                                      size: 18,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      "Добавить",
                                      style: TextStyle(
                                        color: kTextPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          final t = daySlots[index];
                          return Container(
                            decoration: BoxDecoration(
                              color: kAccentPurple,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    t,
                                    style: const TextStyle(
                                      color: kWarmWhite,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(
                                    Icons.close,
                                    color: kWarmWhite,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    setModalState(
                                      () => _weeklyTemplate[selectedWeekday]
                                          ?.remove(t),
                                    );
                                    _saveSchedule();
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kWarmWhite,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: () {
                      _applyTemplateToMonth();
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      "ПРИМЕНИТЬ К ЭТОМУ МЕСЯЦУ",
                      style: TextStyle(
                        color: kTextPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendarGrid({
    required Key key,
    required List<DateTime> gridDates,
    required double calendarHeight,
  }) {
    final int totalCells = gridDates.length;
    final int rows = (totalCells / 7).ceil();
    final double cellHeight = calendarHeight / rows;

    return Container(
      key: key,
      child: SizedBox(
        height: calendarHeight,
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio:
                (MediaQuery.of(context).size.width / 7) / cellHeight,
          ),
          itemCount: totalCells,
          itemBuilder: (context, idx) {
            final d = gridDates[idx];
            final dateStr = _formatToYMD(d);
            final isOtherMonth = d.month != visibleMonth.month;
            final isToday =
                d.year == now.year && d.month == now.month && d.day == now.day;
            final isWeekend =
                d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

            final bool hasSlots = (_availableSlots[dateStr] ?? []).isNotEmpty;
            final bool hasBookings = (_bookedVisits[dateStr] ?? []).isNotEmpty;

            bool isSelected =
                _selectedDate != null &&
                _selectedDate!.day == d.day &&
                _selectedDate!.month == d.month &&
                _selectedDate!.year == d.year;

            Color bg = Colors.transparent;
            if (hasBookings) {
              bg = kAccentPurple;
            } else if (hasSlots) {
              bg = const Color(0xFFE2DCF8);
            } else if (isToday) {
              bg = kWarmWhite.withOpacity(0.8);
            }

            Color textColor;
            if (hasBookings) {
              textColor = kWarmWhite;
            } else if (isOtherMonth) {
              textColor = kTextSecondary.withOpacity(0.3);
            } else if (isWeekend) {
              textColor = kWeekendRed;
            } else {
              textColor = kTextPrimary;
            }

            return GestureDetector(
              onTap: () {
                if (isOtherMonth) {
                  setState(() => visibleMonth = DateTime(d.year, d.month));
                  Future.delayed(
                    const Duration(milliseconds: 150),
                    () => setState(() => _selectedDate = d),
                  );
                } else {
                  setState(() => _selectedDate = d);
                }
              },
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(
                          color: kTextPrimary.withOpacity(0.5),
                          width: 2,
                        )
                      : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      d.day.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor,
                        fontWeight: isToday || isSelected || hasBookings
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (hasBookings)
                      const Positioned(
                        top: 2,
                        right: 2,
                        child: Icon(
                          Icons.star,
                          color: Colors.amberAccent,
                          size: 10,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: kWarmWhite.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTab == 0 ? kAccentPurple : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  "Расписание",
                  style: TextStyle(
                    color: kWarmWhite,
                    fontWeight: _selectedTab == 0
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = 1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedTab == 1 ? kAccentPurple : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Клиенты",
                      style: TextStyle(
                        color: kWarmWhite,
                        fontWeight: _selectedTab == 1
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (_incomingRequests.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: kWeekendRed,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${_incomingRequests.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gridDates = _buildGridDates(visibleMonth);
    const double calendarHeight = 280;

    String? selectedDateStr = _selectedDate != null
        ? _formatToYMD(_selectedDate!)
        : null;
    List<Map<String, dynamic>> currentBookings = selectedDateStr != null
        ? (_bookedVisits[selectedDateStr] ?? [])
        : [];
    List<String> currentSlots = selectedDateStr != null
        ? (_availableSlots[selectedDateStr] ?? [])
        : [];

    return Scaffold(
      backgroundColor: kDeepPurple,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Мой кабинет",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: kWarmWhite,
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildTabSwitcher(),

                    const SizedBox(height: 25),

                    // ---- ВКЛАДКА 1: РАСПИСАНИЕ И НАСТРОЙКИ ----
                    if (_selectedTab == 0) ...[
                      GestureDetector(
                        onTap: _showPriceEditor,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 25,
                          ),
                          decoration: BoxDecoration(
                            color: kWarmWhite.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.payments_outlined,
                                      color: kAccentPurple,
                                      size: 28,
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Стоимость сеанса",
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: kTextPrimary,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Row(
                                children: [
                                  Text(
                                    _priceLoaded
                                        ? "${sessionPrice.toInt()} ₽"
                                        : 'Не загружена',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: kAccentPurple,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.edit,
                                    color: kTextSecondary,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!_priceLoaded && _priceAccessMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Цена пока не загружена. Проверьте у администратора роль психолога и доступ к оплате.',
                          style: TextStyle(color: kWeekendRed, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 20),

                      GestureDetector(
                        onTap: _showWeeklyTemplateEditor,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: kAccentPurple,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: kWarmWhite.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.copy_all,
                                  color: kWarmWhite,
                                ),
                              ),
                              const SizedBox(width: 15),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Шаблон расписания",
                                      style: TextStyle(
                                        color: kWarmWhite,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      "Настройте неделю по умолчанию",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios,
                                color: kWarmWhite,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      Container(
                        decoration: BoxDecoration(
                          color: kWarmWhite,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.chevron_left,
                                    color: kTextPrimary,
                                  ),
                                  onPressed: () {
                                    _changeMonth(delta: -1);
                                  },
                                ),
                                Expanded(
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 1100,
                                      ),
                                      transitionBuilder:
                                          (
                                            Widget child,
                                            Animation<double> anim,
                                          ) {
                                            final offset =
                                                Tween<Offset>(
                                                  begin: Offset(
                                                    0.22 *
                                                        _calendarSlideDirection,
                                                    0,
                                                  ),
                                                  end: Offset.zero,
                                                ).animate(
                                                  CurvedAnimation(
                                                    parent: anim,
                                                    curve: Curves.easeOutCubic,
                                                  ),
                                                );
                                            return ClipRect(
                                              child: SlideTransition(
                                                position: offset,
                                                child: FadeTransition(
                                                  opacity: anim,
                                                  child: child,
                                                ),
                                              ),
                                            );
                                          },
                                      child: Text(
                                        '${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}',
                                        key: ValueKey(
                                          '${visibleMonth.month}_${visibleMonth.year}',
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: kTextPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.chevron_right,
                                    color: kTextPrimary,
                                  ),
                                  onPressed: () {
                                    _changeMonth(delta: 1);
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: _weekDays.map((d) {
                                final isWeekend = d == 'Сб' || d == 'Вс';
                                return Expanded(
                                  child: Center(
                                    child: Text(
                                      d,
                                      style: TextStyle(
                                        color: isWeekend
                                            ? kWeekendRed
                                            : kTextSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onHorizontalDragEnd: (details) {
                                if (details.primaryVelocity == null) return;
                                if (details.primaryVelocity! < -200) {
                                  _changeMonth(delta: 1);
                                } else if (details.primaryVelocity! > 200) {
                                  _changeMonth(delta: -1);
                                }
                              },
                              child: SizedBox(
                                height: calendarHeight,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 1100),
                                  transitionBuilder:
                                      (Widget child, Animation<double> anim) {
                                        final offset =
                                            Tween<Offset>(
                                              begin: Offset(
                                                0.18 * _calendarSlideDirection,
                                                0,
                                              ),
                                              end: Offset.zero,
                                            ).animate(
                                              CurvedAnimation(
                                                parent: anim,
                                                curve: Curves.easeOutCubic,
                                              ),
                                            );
                                        return ClipRect(
                                          child: SlideTransition(
                                            position: offset,
                                            child: FadeTransition(
                                              opacity: anim,
                                              child: child,
                                            ),
                                          ),
                                        );
                                      },
                                  child: _buildCalendarGrid(
                                    key: ValueKey<String>(
                                      'grid_${visibleMonth.year}_${visibleMonth.month}_${gridDates.length}',
                                    ),
                                    gridDates: gridDates,
                                    calendarHeight: calendarHeight,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 25),

                      if (_selectedDate != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Редактирование: ${_selectedDate!.day.toString().padLeft(2, '0')}.${_selectedDate!.month.toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                color: kWarmWhite,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (currentBookings.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  "Записей: ${currentBookings.length}",
                                  style: const TextStyle(
                                    color: kWarmWhite,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 15),

                        if (currentBookings.isNotEmpty) ...[
                          Column(
                            children: currentBookings
                                .map(
                                  (b) => Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: kWarmWhite.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: kAccentPurple,
                                        width: 2,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.network(
                                            b['image'],
                                            width: 45,
                                            height: 45,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(width: 15),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                b['client'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: kTextPrimary,
                                                ),
                                              ),
                                              Text(
                                                b['topic'],
                                                style: const TextStyle(
                                                  color: kTextSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: kAccentPurple,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            b['time'],
                                            style: const TextStyle(
                                              color: kWarmWhite,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 15),
                        ],

                        const Text(
                          "Свободное время",
                          style: TextStyle(color: kWarmWhite, fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: kWarmWhite.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 2.8,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                            itemCount: currentSlots.length + 1,
                            itemBuilder: (context, index) {
                              if (index == currentSlots.length) {
                                return InkWell(
                                  onTap: () {
                                    _pickTime(context, (time) async {
                                      final interval = _calculateInterval(
                                        time,
                                        sessionDurationMinutes,
                                      );
                                      try {
                                        final date = _formatToYMD(
                                          _selectedDate ?? DateTime.now(),
                                        );
                                        await _createApiSlot(date, interval);
                                      } catch (error) {
                                        if (mounted)
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Не удалось создать время. ${friendlyApiError(error)}',
                                              ),
                                            ),
                                          );
                                        return;
                                      }
                                      setState(() {
                                        _availableSlots.putIfAbsent(
                                          selectedDateStr!,
                                          () => [],
                                        );
                                        if (!(_availableSlots[selectedDateStr]!
                                            .contains(interval))) {
                                          _availableSlots[selectedDateStr]!.add(
                                            interval,
                                          );
                                          _availableSlots[selectedDateStr]!
                                              .sort((a, b) => a.compareTo(b));
                                        }
                                      });
                                      _saveSchedule();
                                    });
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: kAccentPurple,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add,
                                          color: kWarmWhite,
                                          size: 18,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          "Добавить",
                                          style: TextStyle(
                                            color: kWarmWhite,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              final t = currentSlots[index];
                              final bool isBooked = currentBookings.any(
                                (b) => b['time'] == t,
                              );

                              return Container(
                                decoration: BoxDecoration(
                                  color: isBooked
                                      ? Colors.redAccent.withOpacity(0.6)
                                      : kWarmWhite,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t,
                                        style: TextStyle(
                                          color: isBooked
                                              ? kWarmWhite
                                              : kTextPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    if (!isBooked)
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        icon: const Icon(
                                          Icons.close,
                                          color: kTextSecondary,
                                          size: 16,
                                        ),
                                        onPressed: () async {
                                          try {
                                            await _removeApiSlot(
                                              selectedDateStr!,
                                              t,
                                            );
                                            setState(() {
                                              _availableSlots[selectedDateStr]
                                                  ?.remove(t);
                                            });
                                            _saveSchedule();
                                          } catch (error) {
                                            if (mounted)
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Не удалось удалить время. ${friendlyApiError(error)}',
                                                  ),
                                                ),
                                              );
                                          }
                                        },
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ]
                    // ---- ВКЛАДКА 2: КЛИЕНТЫ И ЗАЯВКИ ----
                    else ...[
                      if (_incomingRequests.isNotEmpty) ...[
                        const Text(
                          "Новые заявки",
                          style: TextStyle(
                            color: kWarmWhite,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Column(
                          children: _incomingRequests
                              .map(
                                (req) => Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kWarmWhite.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: kAccentPurple
                                                .withOpacity(0.2),
                                            child: const Icon(
                                              Icons.person,
                                              color: kAccentPurple,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              req['clientName'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: kTextPrimary,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        "«${req['requestComment']}»",
                                        style: const TextStyle(
                                          color: kTextSecondary,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      const SizedBox(height: 15),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  _showRejectOrFinishDialog(
                                                    req,
                                                    true,
                                                  ),
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(
                                                  color: kWeekendRed,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              child: const Text(
                                                "Отклонить",
                                                style: TextStyle(
                                                  color: kWeekendRed,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () =>
                                                  _updateAssignmentStatus(
                                                    req,
                                                    'accepted',
                                                  ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                elevation: 0,
                                              ),
                                              child: const Text(
                                                "Принять",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 20),
                      ],

                      const Text(
                        "Мои клиенты",
                        style: TextStyle(
                          color: kWarmWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),

                      if (_activeClients.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40.0),
                            child: Text(
                              "У вас пока нет активных клиентов.",
                              style: TextStyle(
                                color: kWarmWhite.withOpacity(0.7),
                                fontSize: 16,
                              ),
                            ),
                          ),
                        )
                      else
                        Column(
                          children: _activeClients
                              .map(
                                (client) => Container(
                                  margin: const EdgeInsets.only(bottom: 15),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: kWarmWhite.withOpacity(0.95),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: kAccentPurple
                                                .withOpacity(0.2),
                                            child: const Icon(
                                              Icons.person,
                                              color: kAccentPurple,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  client['clientName'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: kTextPrimary,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.check_circle,
                                                      color: Colors.green,
                                                      size: 14,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      "В терапии",
                                                      style: TextStyle(
                                                        color: kTextSecondary
                                                            .withOpacity(0.8),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 15),
                                      Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: kAccentPurple,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                elevation: 0,
                                              ),
                                              icon: const Icon(
                                                Icons.edit_document,
                                                size: 16,
                                                color: kWarmWhite,
                                              ),
                                              label: const Text(
                                                "План лечения",
                                                style: TextStyle(
                                                  color: kWarmWhite,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _showTreatmentPlanDialog(
                                                    client,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            flex: 2,
                                            child: TextButton(
                                              style: TextButton.styleFrom(
                                                backgroundColor: kWeekendRed
                                                    .withOpacity(0.1),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 10,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  _showRejectOrFinishDialog(
                                                    client,
                                                    false,
                                                  ),
                                              child: const Text(
                                                "Завершить",
                                                style: TextStyle(
                                                  color: kWeekendRed,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                    ],

                    const SizedBox(height: 50),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

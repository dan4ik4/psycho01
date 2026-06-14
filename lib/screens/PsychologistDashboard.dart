import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Цветовая палитра SoulBuddy
const Color kDeepPurple = Color(0xFFB0A6E8);
const Color kAccentPurple = Color(0xFF7862D6);
const Color kWarmWhite = Color(0xFFFFF9F2);
const Color kTextPrimary = Color(0xFF323045);
const Color kTextSecondary = Color(0xFF706D8C);
const Color kWeekendRed = Color(0xFFFF8A80);

class PsychologistDashboard extends StatefulWidget {
  @override
  _PsychologistDashboardState createState() => _PsychologistDashboardState();
}

class _PsychologistDashboardState extends State<PsychologistDashboard> {
  double sessionPrice = 85.0;
  int sessionDurationMinutes = 60; // Длительность одного сеанса по умолчанию

  DateTime visibleMonth = DateTime.now();
  DateTime? _selectedDate;
  int _calendarSlideDirection = 0;
  final DateTime now = DateTime.now();

  // Данные расписания и записей (хранят промежутки времени "HH:mm - HH:mm")
  Map<String, List<String>> _availableSlots = {}; // Дата -> Доступные времена
  Map<String, List<Map<String, dynamic>>> _bookedVisits = {}; // Дата -> Записи клиентов

  // Трафарет недели (1 - Пн, 7 - Вс)
  Map<int, List<String>> _weeklyTemplate = {
    1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 7: []
  };

  final List<String> _monthNames = [
    'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
    'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'
  ];

  final List<String> _fullWeekDaysGenitive = [
    'понедельника', 'вторника', 'среды', 'четверга', 'пятницы', 'субботы', 'воскресенья'
  ];

  final List<String> _weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      sessionPrice = prefs.getDouble('doc_price') ?? 85.0;
      sessionDurationMinutes = prefs.getInt('doc_session_duration') ?? 60;

      // Загрузка трафарета
      final templateStr = prefs.getString('doc_template');
      if (templateStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(templateStr);
        _weeklyTemplate = decoded.map((key, value) => MapEntry(int.parse(key), List<String>.from(value)));
      }

      // Загрузка доступных слотов
      final slotsStr = prefs.getString('doc_slots');
      if (slotsStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(slotsStr);
        _availableSlots = decoded.map((key, value) => MapEntry(key, List<String>.from(value)));
      }

      _bookedVisits = {};
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('doc_price', sessionPrice);
    await prefs.setInt('doc_session_duration', sessionDurationMinutes);
  }

  Future<void> _saveSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('doc_template', jsonEncode(_weeklyTemplate.map((key, value) => MapEntry(key.toString(), value))));
    await prefs.setString('doc_slots', jsonEncode(_availableSlots));
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
    final DateTime gridStart = DateTime(month.year, month.month, 1).subtract(Duration(days: startOffset));
    final all = List<DateTime>.generate(42, (i) => gridStart.add(Duration(days: i)));
    final weeks = <List<DateTime>>[];
    for (int i = 0; i < 42; i += 7) { weeks.add(all.sublist(i, i + 7)); }
    weeks.removeWhere((week) => week.every((d) => d.month != month.month));
    return weeks.expand((w) => w).toList();
  }

  // Автоматический расчет интервала времени на основе начала и длительности
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

  // Применение трафарета к выбранному месяцу (ПОЛНАЯ ПЕРЕЗАПИСЬ)
  void _applyTemplateToMonth() {
    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final lastDay = DateTime(visibleMonth.year, visibleMonth.month + 1, 0);

    setState(() {
      for (int i = 0; i < lastDay.day; i++) {
        final d = firstDay.add(Duration(days: i));
        final dateStr = _formatToYMD(d);

        final templateForDay = _weeklyTemplate[d.weekday] ?? [];

        // Получаем время, на которое уже есть записи (чтобы не удалить их из сетки)
        final bookedTimes = (_bookedVisits[dateStr] ?? []).map((b) => b['time'] as String).toList();

        // Формируем новые слоты: только шаблон + забронированные клиентами
        final newSlots = {...templateForDay, ...bookedTimes}.toList();
        newSlots.sort((a, b) => a.compareTo(b));

        if (newSlots.isNotEmpty) {
          _availableSlots[dateStr] = newSlots;
        } else {
          _availableSlots.remove(dateStr); // Очищаем день, если шаблон пуст
        }
      }
    });
    _saveSchedule();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Расписание на месяц успешно обновлено", style: TextStyle(color: kWarmWhite)), backgroundColor: kAccentPurple));
  }

  // Диалог выбора времени начала
  // Крупный и аккуратный барабан выбора времени в стиле Samsung
  Future<void> _pickTime(BuildContext context, Function(String) onTimePicked) async {
    final now = TimeOfDay.now();
    int selectedHour = now.hour;
    int selectedMinute = now.minute;

    // Контроллеры для установки начального положения барабанов
    final FixedExtentScrollController hourController = FixedExtentScrollController(initialItem: selectedHour);
    final FixedExtentScrollController minuteController = FixedExtentScrollController(initialItem: selectedMinute);

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
                  // Заголовок окна
                  const Text(
                    "Выберите время",
                    style: TextStyle(
                      color: kTextPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Основной блок с барабанами времени
                  SizedBox(
                    height: 160, // Ограничиваем высоту, чтобы было видно ровно 3 ряда чисел
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Барабан ЧАСОВ
                        SizedBox(
                          width: 75,
                          child: ListWheelScrollView.useDelegate(
                            controller: hourController,
                            itemExtent: 50, // Высота каждого элемента
                            perspective: 0.002, // Минимальное 3D-искривление для плоского вида
                            diameterRatio: 1.5,
                            physics: const FixedExtentScrollPhysics(), // Плавная фиксация на элементе
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
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                                      color: isSelected ? kAccentPurple : kTextSecondary.withOpacity(0.4),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        // Разделительное двоеточие
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

                        // Барабан МИНУТ
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
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w400,
                                      color: isSelected ? kAccentPurple : kTextSecondary.withOpacity(0.4),
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

                  // Кнопки управления (Нижний ряд)
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
                            style: TextStyle(color: kTextSecondary, fontSize: 16, fontWeight: FontWeight.w600),
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
                            final formattedTime = "${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}";
                            onTimePicked(formattedTime);
                            Navigator.pop(context);
                          },
                          child: const Text(
                            "Готово",
                            style: TextStyle(color: kWarmWhite, fontSize: 16, fontWeight: FontWeight.bold),
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
    TextEditingController controller = TextEditingController(text: sessionPrice.toInt().toString());
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kWarmWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Установить стоимость сеанса", style: TextStyle(color: kTextPrimary, fontSize: 18)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: kTextPrimary, fontSize: 22, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(suffixText: "BYN"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена", style: TextStyle(color: kTextSecondary))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kAccentPurple),
              onPressed: () {
                setState(() => sessionPrice = double.tryParse(controller.text) ?? sessionPrice);
                _saveSettings();
                Navigator.pop(ctx);
              },
              child: const Text("Сохранить", style: TextStyle(color: kWarmWhite)),
            )
          ],
        )
    );
  }

  // Окно управления трафаретом недели
  void _showWeeklyTemplateEditor() {
    int selectedWeekday = 1;
    TextEditingController durationController = TextEditingController(text: sessionDurationMinutes.toString());

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
                        const Text("Шаблон расписания", style: TextStyle(color: kWarmWhite, fontSize: 22, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close, color: kWarmWhite), onPressed: () => Navigator.pop(ctx))
                      ],
                    ),
                    const Text("Настройте стандартную неделю, чтобы быстро применять её к месяцам.", style: TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 15),

                    // Блок ручного вписывания продолжительности сессии
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Длительность сеанса (мин):", style: TextStyle(color: kWarmWhite, fontSize: 16, fontWeight: FontWeight.w500)),
                        Container(
                          width: 90,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: kWarmWhite.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: durationController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: kWarmWhite, fontSize: 16, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                            onChanged: (value) {
                              final parsed = int.tryParse(value);
                              if (parsed != null && parsed > 0) {
                                setModalState(() {
                                  sessionDurationMinutes = parsed;
                                });
                                setState(() {
                                  sessionDurationMinutes = parsed;
                                });
                                _saveSettings();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    // Переключатель дней недели
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(7, (index) {
                        final dayNum = index + 1;
                        final isSel = selectedWeekday == dayNum;
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedWeekday = dayNum),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                                color: isSel ? kAccentPurple : kWarmWhite.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(15)
                            ),
                            child: Text(_weekDays[index], style: TextStyle(color: isSel ? kWarmWhite : kWarmWhite.withOpacity(0.9), fontWeight: FontWeight.bold)),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 20),

                    Text("Время для ${_fullWeekDaysGenitive[selectedWeekday-1]}", style: const TextStyle(color: kWarmWhite, fontSize: 16, fontWeight: FontWeight.bold)),                    const SizedBox(height: 10),

                    // Таблица временных промежутков шаблона
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                        child: SingleChildScrollView(
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 2.8,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: daySlots.length + 1,
                            itemBuilder: (context, index) {
                              if (index == daySlots.length) {
                                // Кнопка добавления промежутка
                                return InkWell(
                                  onTap: () {
                                    _pickTime(context, (time) {
                                      final interval = _calculateInterval(time, sessionDurationMinutes);
                                      setModalState(() {
                                        if (!(_weeklyTemplate[selectedWeekday]?.contains(interval) ?? false)) {
                                          _weeklyTemplate[selectedWeekday]?.add(interval);
                                          _weeklyTemplate[selectedWeekday]?.sort((a, b) => a.compareTo(b));
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
                                        Icon(Icons.add, color: kTextPrimary, size: 18),
                                        SizedBox(width: 4),
                                        Text("Добавить", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
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
                                        style: const TextStyle(color: kWarmWhite, fontWeight: FontWeight.bold, fontSize: 13),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.close, color: kWarmWhite, size: 16),
                                      onPressed: () {
                                        setModalState(() {
                                          _weeklyTemplate[selectedWeekday]?.remove(t);
                                        });
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
                      width: double.infinity, height: 55,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: kWarmWhite, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                        onPressed: () {
                          _applyTemplateToMonth();
                          Navigator.pop(ctx);
                        },
                        child: const Text("ПРИМЕНИТЬ К ЭТОМУ МЕСЯЦУ", style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                ),
              );
            }
        )
    );
  }

  Widget _buildCalendarGrid({required Key key, required List<DateTime> gridDates, required double calendarHeight}) {
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
              childAspectRatio: (MediaQuery.of(context).size.width / 7) / cellHeight
          ),
          itemCount: totalCells,
          itemBuilder: (context, idx) {
            final d = gridDates[idx];
            final dateStr = _formatToYMD(d);
            final isOtherMonth = d.month != visibleMonth.month;
            final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
            final isWeekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

            final bool hasSlots = (_availableSlots[dateStr] ?? []).isNotEmpty;
            final bool hasBookings = (_bookedVisits[dateStr] ?? []).isNotEmpty;

            bool isSelected = _selectedDate != null && _selectedDate!.day == d.day && _selectedDate!.month == d.month && _selectedDate!.year == d.year;

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
                  Future.delayed(const Duration(milliseconds: 150), () => setState(() => _selectedDate = d));
                } else {
                  setState(() => _selectedDate = d);
                }
              },
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected ? Border.all(color: kTextPrimary.withOpacity(0.5), width: 2) : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                        d.day.toString().padLeft(2, '0'),
                        style: TextStyle(fontSize: 14, color: textColor, fontWeight: isToday || isSelected || hasBookings ? FontWeight.bold : FontWeight.normal)
                    ),
                    if (hasBookings)
                      const Positioned(
                        top: 2, right: 2,
                        child: Icon(Icons.star, color: Colors.amberAccent, size: 10),
                      )
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gridDates = _buildGridDates(visibleMonth);
    const double calendarHeight = 280;

    String? selectedDateStr = _selectedDate != null ? _formatToYMD(_selectedDate!) : null;
    List<Map<String, dynamic>> currentBookings = selectedDateStr != null ? (_bookedVisits[selectedDateStr] ?? []) : [];
    List<String> currentSlots = selectedDateStr != null ? (_availableSlots[selectedDateStr] ?? []) : [];

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
                    const Text("Мой кабинет", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kWarmWhite)),
                    const SizedBox(height: 20),

                    // Кнопка настройки стоимости
                    GestureDetector(
                      onTap: _showPriceEditor,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
                        decoration: BoxDecoration(
                            color: kWarmWhite.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.payments_outlined, color: kAccentPurple, size: 28),
                                SizedBox(width: 12),
                                Text("Стоимость сеанса", style: TextStyle(color: kTextPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Row(
                              children: [
                                Text("${sessionPrice.toInt()} BYN", style: const TextStyle(fontWeight: FontWeight.bold, color: kAccentPurple, fontSize: 18)),
                                const SizedBox(width: 8),
                                const Icon(Icons.edit, color: kTextSecondary, size: 20),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Кнопка Трафарета стандартной недели
                    GestureDetector(
                      onTap: _showWeeklyTemplateEditor,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: kAccentPurple,
                            borderRadius: BorderRadius.circular(20)
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.2), shape: BoxShape.circle),
                              child: const Icon(Icons.copy_all, color: kWarmWhite),
                            ),
                            const SizedBox(width: 15),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Шаблон расписания", style: TextStyle(color: kWarmWhite, fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text("Настройте неделю по умолчанию", style: TextStyle(color: Colors.white70, fontSize: 12)),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios, color: kWarmWhite, size: 16)
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Календарь
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
                              IconButton(icon: const Icon(Icons.chevron_left, color: kTextPrimary), onPressed: () { _changeMonth(delta: -1); }),
                              Expanded(
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 1100),
                                    transitionBuilder: (Widget child, Animation<double> anim) {
                                      final offset = Tween<Offset>(begin: Offset(0.22 * _calendarSlideDirection, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                                      return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: child)));
                                    },
                                    child: Text('${_monthNames[visibleMonth.month - 1]} ${visibleMonth.year}', key: ValueKey('${visibleMonth.month}_${visibleMonth.year}'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kTextPrimary)),
                                  ),
                                ),
                              ),
                              IconButton(icon: const Icon(Icons.chevron_right, color: kTextPrimary), onPressed: () { _changeMonth(delta: 1); }),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: _weekDays.map((d) {
                              final isWeekend = d == 'Сб' || d == 'Вс';
                              return Expanded(child: Center(child: Text(d, style: TextStyle(color: isWeekend ? kWeekendRed : kTextSecondary, fontWeight: FontWeight.w600))));
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onHorizontalDragEnd: (details) {
                              if (details.primaryVelocity == null) return;
                              if (details.primaryVelocity! < -200) { _changeMonth(delta: 1); }
                              else if (details.primaryVelocity! > 200) { _changeMonth(delta: -1); }
                            },
                            child: SizedBox(
                              height: calendarHeight,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 1100),
                                transitionBuilder: (Widget child, Animation<double> anim) {
                                  final offset = Tween<Offset>(begin: Offset(0.18 * _calendarSlideDirection, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
                                  return ClipRect(child: SlideTransition(position: offset, child: FadeTransition(opacity: anim, child: child)));
                                },
                                child: _buildCalendarGrid(key: ValueKey<String>('grid_${visibleMonth.year}_${visibleMonth.month}_${gridDates.length}'), gridDates: gridDates, calendarHeight: calendarHeight),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Информация о выбранном дне
                    if (_selectedDate != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Редактирование: ${_selectedDate!.day.toString().padLeft(2,'0')}.${_selectedDate!.month.toString().padLeft(2,'0')}", style: const TextStyle(color: kWarmWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                          if (currentBookings.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                              child: Text("Записей: ${currentBookings.length}", style: const TextStyle(color: kWarmWhite, fontWeight: FontWeight.bold, fontSize: 12)),
                            )
                        ],
                      ),
                      const SizedBox(height: 15),

                      // Карточки записанных клиентов
                      if (currentBookings.isNotEmpty) ...[
                        Column(
                          children: currentBookings.map((b) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.9), borderRadius: BorderRadius.circular(20), border: Border.all(color: kAccentPurple, width: 2)),
                            child: Row(
                              children: [
                                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(b['image'], width: 45, height: 45, fit: BoxFit.cover)),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(b['client'], style: const TextStyle(fontWeight: FontWeight.bold, color: kTextPrimary)),
                                      Text(b['topic'], style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: kAccentPurple, borderRadius: BorderRadius.circular(12)),
                                  child: Text(b['time'], style: const TextStyle(color: kWarmWhite, fontWeight: FontWeight.bold, fontSize: 12)),
                                )
                              ],
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 15),
                      ],

                      // Таблица свободных временных промежутков на выбранный день
                      const Text("Свободное время", style: TextStyle(color: kWarmWhite, fontSize: 16)),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: kWarmWhite.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 2.8,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: currentSlots.length + 1,
                          itemBuilder: (context, index) {
                            if (index == currentSlots.length) {
                              // Кнопка добавления промежутка
                              return InkWell(
                                onTap: () {
                                  _pickTime(context, (time) {
                                    final interval = _calculateInterval(time, sessionDurationMinutes);
                                    setState(() {
                                      _availableSlots.putIfAbsent(selectedDateStr!, () => []);
                                      if (!(_availableSlots[selectedDateStr!]!.contains(interval))) {
                                        _availableSlots[selectedDateStr!]!.add(interval);
                                        _availableSlots[selectedDateStr!]!.sort((a, b) => a.compareTo(b));
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add, color: kWarmWhite, size: 18),
                                      SizedBox(width: 4),
                                      Text("Добавить", style: TextStyle(color: kWarmWhite, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              );
                            }

                            final t = currentSlots[index];
                            final bool isBooked = currentBookings.any((b) => b['time'] == t);

                            return Container(
                              decoration: BoxDecoration(
                                color: isBooked ? Colors.redAccent.withOpacity(0.6) : kWarmWhite,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      t,
                                      style: TextStyle(
                                        color: isBooked ? kWarmWhite : kTextPrimary,
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
                                      icon: const Icon(Icons.close, color: kTextSecondary, size: 16),
                                      onPressed: () {
                                        setState(() {
                                          _availableSlots[selectedDateStr!]?.remove(t);
                                        });
                                        _saveSchedule();
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
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
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'note_editor.dart';
import '../../utils/score_manager.dart';

class CalendarView extends StatefulWidget {
  final bool isDarkMode;
  final void Function(int points)? onAddStars;

  const CalendarView({
    super.key,
    required this.isDarkMode,
    this.onAddStars,
  });

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView>
    with SingleTickerProviderStateMixin {
  late DateTime _currentMonth;
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;

  final Map<String, List<Map<String, dynamic>>> _notesMap = {};
  final Set<String> _rewardedDays = {}; // чтобы не начислять повторно

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime.now();
    _animController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _slideAnimation =
        Tween<Offset>(begin: Offset.zero, end: const Offset(1.0, 0.0)).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
        );
    _loadNotes();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('note_'));
    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as List<dynamic>;
          _notesMap[key.substring(5)] =
              decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}
      }
    }
    setState(() {});
  }

  Future<void> _saveNotesForDate(String key, List<Map<String, dynamic>> notes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('note_$key', jsonEncode(notes));
  }

  void _changeMonth(int delta) {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
    });
  }

  Future<void> _openNotesForDay(DateTime day) async {
    final key = _dateKey(day);
    final notes = _notesMap[key] ?? [];

    final result = await showModalBottomSheet<List<Map<String, dynamic>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NoteEditor(
        day: day,
        initialNotes: notes,
        isDarkMode: widget.isDarkMode,
      ),
    );

    if (result != null) {
      await _saveNotesForDate(key, result);
      setState(() {
        _notesMap[key] = result;
      });

      // Начисляем очки только если:
      // - есть хотя бы одна заметка
      // - есть хотя бы одна, где createdAt совпадает по дате с самим днём
      // - и день ещё не награждён
      if (!_rewardedDays.contains(key)) {
        final sameDayNotes = result.where((n) {
          try {
            final createdAt = DateTime.parse(n['createdAt']);
            return createdAt.year == day.year &&
                createdAt.month == day.month &&
                createdAt.day == day.day;
          } catch (_) {
            return false;
          }
        }).toList();

        if (sameDayNotes.isNotEmpty) {
          await ScoreManager.addPoints(1);
          _rewardedDays.add(key);
          widget.onAddStars?.call(1);
        }
      }
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<DateTime> _generateDaysForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);

    final startOffset = firstDay.weekday % 7; // Monday-first
    final days = <DateTime>[];

    // дни из предыдущего месяца
    for (int i = 0; i < startOffset; i++) {
      days.add(firstDay.subtract(Duration(days: startOffset - i)));
    }

    // дни текущего месяца
    for (int i = 0; i < lastDay.day; i++) {
      days.add(DateTime(month.year, month.month, i + 1));
    }

    // дни следующего месяца до конца недели
    while (days.length % 7 != 0) {
      final nextDay = days.last.add(const Duration(days: 1));
      days.add(nextDay);
    }

    return days;
  }

  Color _dayColor(DateTime day) {
    final key = _dateKey(day);
    final notes = _notesMap[key];
    if (notes == null || notes.isEmpty) return Colors.transparent;

    final sameDayNotes = notes.where((n) {
      try {
        final created = DateTime.parse(n['createdAt']);
        return created.year == day.year &&
            created.month == day.month &&
            created.day == day.day;
      } catch (_) {
        return false;
      }
    }).toList();

    if (sameDayNotes.isNotEmpty) {
      return const Color(0xFFB79CFF); // заметка сделана в тот же день
    } else {
      return Colors.grey.withOpacity(0.3); // заметка из другого дня
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final days = _generateDaysForMonth(_currentMonth);
    final now = DateTime.now();
    final textColor = isDark ? Colors.white : Colors.black87;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! < 0) {
          _changeMonth(1);
        } else if (details.primaryVelocity! > 0) {
          _changeMonth(-1);
        }
      },
      child: Column(
        children: [
          // Заголовок месяца и стрелки
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_left),
                color: textColor,
                onPressed: () => _changeMonth(-1),
              ),
              Text(
                '${_monthName(_currentMonth.month)} ${_currentMonth.year}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_right),
                color: textColor,
                onPressed: () => _changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Дни недели
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
                .map((d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: (d == 'Сб' || d == 'Вс')
                        ? Colors.purple
                        : textColor,
                  ),
                ),
              ),
            ))
                .toList(),
          ),
          const SizedBox(height: 8),

          // Сетка дней
          Expanded(
            child: SlideTransition(
              position: _slideAnimation,
              child: GridView.builder(
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 4,
                ),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final isCurrentMonth = day.month == _currentMonth.month;
                  final isToday = day.year == now.year &&
                      day.month == now.month &&
                      day.day == now.day;

                  return GestureDetector(
                    onTap: () {
                      if (!isCurrentMonth) {
                        setState(() {
                          _currentMonth =
                              DateTime(day.year, day.month, 1);
                        });
                      } else {
                        _openNotesForDay(day);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        color: _dayColor(day),
                        borderRadius: BorderRadius.circular(12),
                        border: isToday
                            ? Border.all(
                            color: const Color(0xFF5E3B8C), width: 2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: isCurrentMonth
                              ? textColor
                              : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int m) {
    const names = [
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
      'Декабрь'
    ];
    return names[m - 1];
  }
}

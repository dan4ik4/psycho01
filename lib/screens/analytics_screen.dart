// lib/screens/analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AnalyticsScreen extends StatefulWidget {
  final Map<String, Map<String, dynamic>> notesData;
  const AnalyticsScreen({required this.notesData, super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String selectedPeriod = 'week';
  final Color purple = const Color(0xFF5E3B8C);

  // Календарный алгоритм определения начала периода
  DateTime _getPeriodStart() {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);

    if (selectedPeriod == 'week') {
      // Ищем текущий понедельник
      return today.subtract(Duration(days: today.weekday - 1));
    } else if (selectedPeriod == 'month') {
      // 1-е число текущего месяца
      return DateTime(today.year, today.month, 1);
    } else {
      // 1-е января
      return DateTime(today.year, 1, 1);
    }
  }

  Map<String, int> _calculateMoodStats() {
    Map<String, int> stats = {'excellent': 0, 'good': 0, 'neutral': 0, 'bad': 0, 'terrible': 0};
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime threshold;

    if (selectedPeriod == 'week') {
      // Начало текущей недели (Понедельник)
      threshold = today.subtract(Duration(days: today.weekday - 1));
    } else if (selectedPeriod == 'month') {
      // 1-е число текущего месяца
      threshold = DateTime(today.year, today.month, 1);
    } else {
      // 1-е января
      threshold = DateTime(today.year, 1, 1);
    }

    widget.notesData.forEach((dateKey, value) {
      try {
        DateTime date = DateTime.parse(dateKey);
        if (!date.isBefore(threshold)) {
          String? mood = value['dayMood'];
          if (mood == null && value['items'] != null && (value['items'] as List).isNotEmpty) {
            mood = (value['items'] as List).first['mood'];
          }
          if (mood != null && stats.containsKey(mood)) {
            stats[mood] = stats[mood]! + 1;
          }
        }
      } catch (_) {}
    });
    return stats;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateMoodStats();
    final total = stats.values.fold(0, (sum, item) => sum + item);
    final start = _getPeriodStart();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FF),
      appBar: AppBar(
        title: const Text("Аналитика настроения", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true, backgroundColor: Colors.transparent, elevation: 0, foregroundColor: purple,
      ),
      body: Column(
        children: [
          Text(
            "Период: ${DateFormat('dd.MM.yy').format(start)} — ${DateFormat('dd.MM.yy').format(DateTime.now())}",
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          const SizedBox(height: 15),
          _buildSelector(),
          const SizedBox(height: 25),
          if (total == 0)
            const Expanded(child: Center(child: Text("За этот период данных пока нет")))
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // Увеличенный контейнер диаграммы
                    Container(
                      height: 350, // Увеличили высоту с 250 до 350
                      padding: const EdgeInsets.fromLTRB(10, 30, 10, 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                              color: purple.withOpacity(0.08),
                              blurRadius: 15,
                              offset: const Offset(0, 5)
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildBar("Ужасно", "😫", stats['terrible']!, total, Colors.redAccent),
                          _buildBar("Плохо", "😔", stats['bad']!, total, Colors.orange),
                          _buildBar("Норм", "😐", stats['neutral']!, total, Colors.amber),
                          _buildBar("Хор", "🙂", stats['good']!, total, Colors.lightGreen),
                          _buildBar("Отл", "😊", stats['excellent']!, total, Colors.green),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                        "Всего записей: $total",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: purple.withOpacity(0.8)
                        )
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
      child: Row(
        children: [
          Expanded(child: _btn("Неделя", 'week')),
          Expanded(child: _btn("Месяц", 'month')),
          Expanded(child: _btn("Год", 'year')),
        ],
      ),
    );
  }

  Widget _btn(String txt, String code) {
    bool isSel = selectedPeriod == code;
    return GestureDetector(
      onTap: () => setState(() => selectedPeriod = code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: isSel ? purple : Colors.transparent, borderRadius: BorderRadius.circular(25)),
        child: Center(child: Text(txt, style: TextStyle(color: isSel ? Colors.white : Colors.grey, fontWeight: isSel ? FontWeight.bold : FontWeight.normal))),
      ),
    );
  }

  Widget _statCard(String label, String emoji, int count, int total, Color color) {
    double percent = total == 0 ? 0 : count / total;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: color.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))]),
      child: Column(
        children: [
          Row(children: [
            Text("$emoji $label", style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text("$count дн.", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 8),
            Text("${(percent * 100).toStringAsFixed(0)}%", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: percent, minHeight: 8, color: color, backgroundColor: Colors.grey[100]),
          ),
        ],
      ),
    );
  }
  Widget _buildBar(String label, String emoji, int count, int total, Color color) {
    double percent = total == 0 ? 0 : count / total;

    // Вычисляем динамическую высоту (макс 220 пикселей)
    double barHeight = (percent * 220).clamp(8.0, 220.0);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Процент над столбиком
        Text(
          "${(percent * 100).toStringAsFixed(0)}%",
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color
          ),
        ),
        const SizedBox(height: 6),
        // Столбик (сделали шире — 45)
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          width: 45,
          height: barHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              )
            ],
          ),
          // Внутри столбика можно вывести количество дней, если оно там поместится
          child: count > 0 && barHeight > 30
              ? Center(
              child: Text(
                  "$count",
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
              )
          )
              : null,
        ),
        const SizedBox(height: 12),
        // Только эмодзи (размер увеличили до 32)
        Text(emoji, style: const TextStyle(fontSize: 32)),
      ],
    );
  }
}
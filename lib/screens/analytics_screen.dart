import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class AnalyticsScreen extends StatefulWidget {
  final Map<String, Map<String, dynamic>> notesData;
  const AnalyticsScreen({required this.notesData, super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String selectedType = 'week';
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  final Color deepPurple = const Color(0xFF2D1B4E);
  final Color accentPurple = const Color(0xFF9575CD);
  final Color warmWhite = const Color(0xFFFFF9F2);

  @override
  void initState() {
    super.initState();
    _applyQuickPeriod('week');
  }

  void _applyQuickPeriod(String type) {
    DateTime now = DateTime.now();
    DateTime start;
    if (type == 'week') {
      start = now.subtract(Duration(days: now.weekday - 1));
    } else if (type == 'month') {
      start = DateTime(now.year, now.month, 1);
    } else {
      start = DateTime(now.year, 1, 1);
    }

    setState(() {
      selectedType = type;
      _startController.text = DateFormat('dd.MM.yy').format(start);
      _endController.text = DateFormat('dd.MM.yy').format(now);
    });
  }

  DateTime? _safeParse(String input) {
    if (input.length != 8) return null;
    try {
      return DateFormat('dd.MM.yy').parseStrict(input);
    } catch (_) {
      return null;
    }
  }

  Map<String, int> _calculateStats() {
    Map<String, int> stats = {'excellent': 0, 'good': 0, 'neutral': 0, 'bad': 0, 'terrible': 0};
    final start = _safeParse(_startController.text);
    final end = _safeParse(_endController.text);

    if (start == null || end == null) return stats;

    final endLimit = DateTime(end.year, end.month, end.day, 23, 59, 59);
    widget.notesData.forEach((key, val) {
      try {
        DateTime d = DateTime.parse(key);
        if (!d.isBefore(start) && !d.isAfter(endLimit)) {
          String? mood = val['dayMood'] ?? (val['items']?.isNotEmpty == true ? val['items'][0]['mood'] : null);
          if (mood != null && stats.containsKey(mood)) stats[mood] = stats[mood]! + 1;
        }
      } catch (_) {}
    });
    return stats;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _calculateStats();
    final total = stats.values.fold(0, (a, b) => a + b);
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: deepPurple,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [deepPurple, warmWhite], stops: const [0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 15),
              _buildPeriodSelector(),

              // Анимированное появление полей ввода
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                child: selectedType == 'custom'
                    ? _buildManualInputBlock()
                    : const SizedBox(height: 10),
              ),

              if (total == 0)
                Expanded(child: Center(child: Text(
                  _safeParse(_startController.text) == null ? "Введите дату полностью (дд.мм.гг)" : "Данных не найдено",
                  style: TextStyle(color: warmWhite.withOpacity(0.4)),
                )))
              else
                Expanded(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // ГРАФИК (50% ВЫСОТЫ ЭКРАНА)
                      Container(
                        height: h * 0.5,
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(35),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _bar("😫", stats['terrible']!, total, Colors.redAccent),
                            _bar("😔", stats['bad']!, total, Colors.orangeAccent),
                            _bar("😐", stats['neutral']!, total, Colors.amberAccent),
                            _bar("🙂", stats['good']!, total, Colors.lightGreenAccent),
                            _bar("😊", stats['excellent']!, total, Colors.greenAccent),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _buildTotalBadge(total),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white), onPressed: () => Navigator.pop(context)),
          const Expanded(child: Center(child: Text("Аналитика настроения", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)))),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 50,
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
      child: Row(
        children: ['week', 'month', 'year', 'custom'].map((t) {
          String label = t == 'week' ? "Неделя" : t == 'month' ? "Месяц" : t == 'year' ? "Год" : "Свой";
          bool isSel = selectedType == t;
          return Expanded(
            child: GestureDetector(
              onTap: () => t == 'custom' ? setState(() => selectedType = 'custom') : _applyQuickPeriod(t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSel ? accentPurple : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(label, style: TextStyle(color: isSel ? Colors.white : Colors.white54, fontSize: 13, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildManualInputBlock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 15, 25, 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentPurple.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            _dateEntry(_startController, "ОТ"),
            Container(margin: const EdgeInsets.symmetric(horizontal: 15), width: 1, height: 30, color: Colors.white10),
            _dateEntry(_endController, "ДО"),
          ],
        ),
      ),
    );
  }

  Widget _dateEntry(TextEditingController ctrl, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: accentPurple, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [DateMaskFormatter()],
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(hintText: "00.00.00", hintStyle: TextStyle(color: Colors.white12), border: InputBorder.none, isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _bar(String emoji, int count, int total, Color color) {
    double percent = count / total;
    double h = (percent * 250).clamp(15.0, 250.0); // Высота столбика
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text("${(percent * 100).toInt()}%", style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutBack,
            width: 38, height: h,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withOpacity(0.4)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 10, spreadRadius: 1)],
            ),
            child: count > 0 && h > 40 ? Center(child: Text("$count", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))) : null,
          ),
          const SizedBox(height: 12),
          Text(emoji, style: const TextStyle(fontSize: 32)),
        ],
      ),
    );
  }

  Widget _buildTotalBadge(int total) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04), // Почти прозрачная
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Всего записей:", style: TextStyle(color: deepPurple.withOpacity(0.4), fontSize: 15, fontWeight: FontWeight.w500)),
          Text("$total", style: TextStyle(color: deepPurple, fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class DateMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll('.', '');
    if (text.length > 6) return oldValue;

    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i == 1 || i == 3) && i != text.length - 1) buffer.write('.');
    }

    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.toString().length),
    );
  }
}
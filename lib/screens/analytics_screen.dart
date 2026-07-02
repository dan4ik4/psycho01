import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

class AnalyticsScreen extends StatefulWidget {
  final Map<String, Map<String, dynamic>> notesData;
  const AnalyticsScreen({required this.notesData, super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> with TickerProviderStateMixin {
  String selectedType = 'week';
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color accentPurple = const Color(0xFF7862D6);
  final Color warmWhite = const Color(0xFFF6F8FD); // Ghost / Soft Lavender White
  final Color textPrimary = const Color(0xFF323045);
  final Color textSecondary = const Color(0xFF706D8C);

  late AnimationController _emojiController;
  late Animation<double> _gentleAnimation;

  @override
  void initState() {
    super.initState();
    _applyQuickPeriod('week');

    _emojiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _gentleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 20,
      ),
    ]).animate(_emojiController);
  }

  @override
  void dispose() {
    _emojiController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  final Map<String, dynamic> moodData = {
    'terrible': {'path': 'assets/lottie/terrible.json', 'color': Colors.redAccent},
    'bad': {'path': 'assets/lottie/bad.json', 'color': Colors.orange},
    'neutral': {'path': 'assets/lottie/neutral.json', 'color': Colors.amber},
    'good': {'path': 'assets/lottie/good.json', 'color': Colors.lightGreen},
    'excellent': {'path': 'assets/lottie/excellent.json', 'color': Colors.green},
  };

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
    final maxCount = stats.values.reduce((a, b) => a > b ? a : b);
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: deepPurple,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: warmWhite),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Аналитика настроения",
          style: TextStyle(color: warmWhite, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 10),
              _buildPeriodSelector(),

              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                child: selectedType == 'custom'
                    ? _buildManualInputBlock()
                    : const SizedBox(height: 10),
              ),

              if (total == 0)
                SizedBox(
                  height: h * 0.5,
                  child: Center(
                    child: Text(
                      _safeParse(_startController.text) == null
                          ? "Введите дату полностью"
                          : "Данных не найдено",
                      style: TextStyle(color: warmWhite.withOpacity(0.8)),
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      height: h * 0.52,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.fromLTRB(10, 30, 10, 15),
                      decoration: BoxDecoration(
                        color: warmWhite.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _bar('terrible', stats['terrible']!, maxCount, total),
                          _bar('bad', stats['bad']!, maxCount, total),
                          _bar('neutral', stats['neutral']!, maxCount, total),
                          _bar('good', stats['good']!, maxCount, total),
                          _bar('excellent', stats['excellent']!, maxCount, total),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildTotalBadge(total),
                    const SizedBox(height: 40),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 50,
      decoration: BoxDecoration(
        color: warmWhite.withOpacity(0.8),
        borderRadius: BorderRadius.circular(15),
      ),
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
                child: Text(
                  label,
                  style: TextStyle(
                      color: isSel ? warmWhite : textPrimary,
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildManualInputBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: warmWhite.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            _dateEntry(_startController, "ОТ"),
            Container(width: 1, height: 30, color: textSecondary.withOpacity(0.2), margin: const EdgeInsets.symmetric(horizontal: 15)),
            _dateEntry(_endController, "ДО"),
          ],
        ),
      ),
    );
  }

  Widget _dateEntry(TextEditingController ctrl, String label) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          DateTime? picked = await showDatePicker(
            context: context,
            initialDate: _safeParse(ctrl.text) ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2101),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: accentPurple,
                    onPrimary: warmWhite,
                    onSurface: textPrimary,
                  ),
                ),
                child: child!,
              );
            },
          );
          if (picked != null) {
            setState(() {
              ctrl.text = DateFormat('dd.MM.yy').format(picked);
            });
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: accentPurple, fontSize: 10, fontWeight: FontWeight.bold)),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              inputFormatters: [SmartDateFormatter()],
              style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                  hintText: "ДД.ММ.ГГ",
                  hintStyle: TextStyle(color: textSecondary.withOpacity(0.4)),
                  border: InputBorder.none,
                  isDense: true
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(String moodKey, int count, int maxCount, int total) {
    double ratio = maxCount > 0 ? count / maxCount : 0;
    double maxPossibleHeight = 240;
    double barHeight = (ratio * maxPossibleHeight).clamp(15.0, maxPossibleHeight);
    double percent = total > 0 ? count / total : 0;

    final color = moodData[moodKey]['color'];
    final path = moodData[moodKey]['path'];

    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text("${(percent * 100).toInt()}%",
              style: TextStyle(color: textPrimary, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 1000),
            curve: Curves.fastOutSlowIn,
            width: 50,
            height: barHeight,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 3))
              ],
            ),
            child: count > 0 && barHeight > 35
                ? Center(child: Text("$count", style: TextStyle(color: warmWhite, fontSize: 13, fontWeight: FontWeight.w900)))
                : null,
          ),
          const SizedBox(height: 15),
          AnimatedBuilder(
            animation: _emojiController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, -5 * _gentleAnimation.value),
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: Lottie.asset(
                    path,
                    repeat: true,
                    animate: true,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTotalBadge(int total) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 25),
      decoration: BoxDecoration(
        color: warmWhite.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("Всего записей:", style: TextStyle(color: textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
          Text("$total", style: TextStyle(color: textPrimary, fontSize: 24, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class SmartDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length < oldValue.text.length) return newValue;
    final text = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < text.length && i < 6; i++) {
      buffer.write(text[i]);
      if ((i == 1 || i == 3) && i != text.length - 1) buffer.write('.');
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.toString().length),
    );
  }
}
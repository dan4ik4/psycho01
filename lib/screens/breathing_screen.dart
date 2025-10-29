import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui';


class BreathingScreen extends StatefulWidget {
  final bool isDarkMode;

  const BreathingScreen({super.key, required this.isDarkMode});

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen>
    with SingleTickerProviderStateMixin {
  static const int totalCycles = 4;
  static const int inhale = 4;
  static const int hold = 7;
  static const int exhale = 8;
  static const int totalDuration = inhale + hold + exhale;

  int currentCycle = 0;
  bool isRunning = false;
  double progress = 0.0;
  double elapsed = 0.0;
  late AnimationController _controller;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(seconds: totalDuration))
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_timer.isActive) _timer.cancel();
    super.dispose();
  }

  void _startBreathing() {
    if (isRunning) return;
    setState(() {
      isRunning = true;
      currentCycle = 0;
      elapsed = 0;
      progress = 0;
    });
    _startCycle();
  }

  void _startCycle() {
    if (currentCycle >= totalCycles) {
      setState(() {
        isRunning = false;
      });
      return;
    }

    _controller.reset();
    _controller.forward();

    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        elapsed += 0.1;
        progress = elapsed / totalDuration;

        if (elapsed >= totalDuration) {
          timer.cancel();
          currentCycle++;
          elapsed = 0;
          progress = 0;
          Future.delayed(const Duration(seconds: 1), _startCycle);
        }
      });
    });
  }

  void _stopBreathing() {
    if (!isRunning) return;
    setState(() {
      isRunning = false;
      progress = 0;
      currentCycle = 0;
    });
    _controller.stop();
    _timer.cancel();
  }

  String _getPhase() {
    if (!isRunning) return "Готов?";
    final phaseTime = elapsed % totalDuration;

    if (phaseTime < inhale) return "Вдох";
    if (phaseTime < inhale + hold) return "Задержка дыхания";
    return "Выдох";
  }

  double _getYPosition(double t) {
    double x = t * 3;
    if (x < 1) return lerpDouble(0.8, 0.2, x)!; // вдох
    if (x < 2) return 0.2; // задержка
    return lerpDouble(0.2, 0.8, x - 2)!; // выдох
  }

  Color _getBackgroundColor() {
    final Color light = widget.isDarkMode ? const Color(0xFF2E2E2E) : Colors.white;
    final Color bright = widget.isDarkMode ? const Color(0xFF4A4A4A) : const Color(0xFFF2E9FF);
    final Color dark = widget.isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFE6DFFF);

    final phaseTime = elapsed % totalDuration;
    if (!isRunning) return light;

    if (phaseTime < inhale) {
      // вдох — осветление
      double t = phaseTime / inhale;
      return Color.lerp(light, bright, t)!;
    } else if (phaseTime < inhale + hold) {
      // задержка — ровный светлый
      return bright;
    } else {
      // выдох — затемнение
      double t = (phaseTime - inhale - hold) / exhale;
      return Color.lerp(bright, dark, t)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color purple = const Color(0xFF6C4AB6);
    final Color textColor = widget.isDarkMode ? Colors.white : Colors.black87;

    double circleProgress = (progress % 1.0).clamp(0.0, 1.0);
    double y = _getYPosition(circleProgress);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      color: _getBackgroundColor(),
      child: SafeArea(
        child: Stack(
          children: [
            // Ломаная линия дыхания
            Align(
              alignment: Alignment.center,
              child: CustomPaint(
                size: Size(MediaQuery.of(context).size.width,
                    MediaQuery.of(context).size.height * 0.6),
                painter: BreathingLinePainter(purple),
              ),
            ),

            // Шар
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment(0, y * 2 - 1),
              curve: Curves.linear,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: purple,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: purple.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 2,
                    )
                  ],
                ),
              ),
            ),

            // Текст и фаза
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    "Дыхательная практика",
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Цикл: $currentCycle / $totalCycles",
                    style: TextStyle(color: textColor.withOpacity(0.7)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getPhase(),
                    style: TextStyle(fontSize: 20, color: purple),
                  ),
                ],
              ),
            ),

            // Круговой таймер (один цикл)
            Positioned(
              bottom: 180,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: circleProgress,
                        color: purple,
                        backgroundColor: widget.isDarkMode
                            ? Colors.white12
                            : Colors.black12,
                        strokeWidth: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Кнопки
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: isRunning ? null : _startBreathing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: purple,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text("Старт",
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: isRunning ? _stopBreathing : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text("Стоп",
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BreathingLinePainter extends CustomPainter {
  final Color color;

  BreathingLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = Path();
    final double w = size.width;
    final double h = size.height;

    path.moveTo(0, h * 0.8);
    path.lineTo(w * 0.25, h * 0.2); // вдох
    path.lineTo(w * 0.55, h * 0.2); // задержка
    path.lineTo(w, h * 0.8); // выдох

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

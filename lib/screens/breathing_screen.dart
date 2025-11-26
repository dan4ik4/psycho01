// lib/screens/breathing_screen.dart
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

class BreathingScreen extends StatefulWidget {
  const BreathingScreen({Key? key}) : super(key: key);

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen> with TickerProviderStateMixin {
  // ------------------ CONFIG (можно менять) ------------------
  final Color purple = const Color(0xFF5E3B8C);

  final int inhale = 4; // seconds
  final int hold = 7;
  final int exhale = 8;
  final int cycles = 3;

  final double circleWidthFactor = 0.72; // доля ширины экрана для базового диаметра круга
  final double circleMaxScale = 1.22; // насколько расширяется видимая окружность
  final double ballBaseSize = 24.0; // px
  final double timerSize = 64.0; // px
  final int confettiMs = 1400; // длительность конфетти (ms)
  // ----------------------------------------------------------

  late final int cycleLen;
  late final int totalSeconds;

  late final AnimationController _mainCtrl;
  late final AnimationController _confettiCtrl;

  bool running = false;
  bool finished = false;

  int completedCycles = 0;

  @override
  void initState() {
    super.initState();
    cycleLen = inhale + hold + exhale;
    totalSeconds = cycleLen * cycles;

    _mainCtrl =
    AnimationController(vsync: this, duration: Duration(seconds: totalSeconds))
      ..addListener(_mainTick)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() {
            running = false;
            finished = true;
            completedCycles = cycles;
          });
          _confettiCtrl.forward(from: 0.0);
        }
      });

    _confettiCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: confettiMs),
    )..addListener(() {
      setState(() {});
    });

  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  void _mainTick() {
    final secondsNow = (_mainCtrl.value * totalSeconds);
    final newCompleted = (secondsNow ~/ cycleLen);
    if (newCompleted != completedCycles) {
      setState(() {
        completedCycles = newCompleted.clamp(0, cycles);
      });
    }
    // Если animation закончился, finished уже выставится в статус-листенере.
  }

  void _start() {
    setState(() {
      running = true;
      finished = false;
      completedCycles = 0;
    });
    _confettiCtrl.reset();
    _mainCtrl.forward(from: 0.0);
  }

  void _stop() {
    _mainCtrl.stop();
    _confettiCtrl.stop();
    setState(() {
      running = false;
      finished = false;
      completedCycles = 0;
    });
  }

  // --- фаза и локальный прогресс в фазе ---
  int _phaseForSeconds(double s) {
    final secInCycle = (s % cycleLen);
    if (secInCycle < inhale) return 0;
    if (secInCycle < inhale + hold) return 1;
    return 2;
  }

  double _phaseLocalT(double s, int phase) {
    final secInCycle = (s % cycleLen);
    int start = 0;
    if (phase == 1) start = inhale;
    if (phase == 2) start = inhale + hold;
    final len = (phase == 0) ? inhale : (phase == 1) ? hold : exhale;
    final t = ((secInCycle - start) / len).clamp(0.0, 1.0);
    return t;
  }

  // масштаб видимой окружности (1..circleMaxScale)
  double _circleScaleFor(double secondsNow) {
    final phase = _phaseForSeconds(secondsNow);
    final local = _phaseLocalT(secondsNow, phase);
    if (phase == 0) {
      return lerpDouble(1.0, circleMaxScale, Curves.easeOut.transform(local))!;
    } else if (phase == 1) {
      return circleMaxScale;
    } else {
      return lerpDouble(circleMaxScale, 1.0, Curves.easeIn.transform(local))!;
    }
  }

  // масштаб шарика  (1..1.32)
  double _ballScaleFor(double secondsNow) {
    final phase = _phaseForSeconds(secondsNow);
    final local = _phaseLocalT(secondsNow, phase);
    if (phase == 0) {
      return lerpDouble(1.0, 1.32, Curves.easeOut.transform(local))!;
    } else if (phase == 1) {
      return 1.32;
    } else {
      return lerpDouble(1.32, 1.0, Curves.easeIn.transform(local))!;
    }
  }

  String? _phraseFor(double secondsNow) {
    final phase = _phaseForSeconds(secondsNow);
    if (phase == 0) return "Вдох";
    if (phase == 2) return "Выдох";
    return null;
  }

  // положение шарика по окружности: progress 0..1 -> angle
  Offset _ballPosOnCircle(double progress, double radius, Offset center) {
    // движемся против часовой (если хотите по часовой — уберите знак)
    // один полный оборот = progress * 2π (но нам нужно пройти cycles оборотов)
    final angle = (progress * 2 * pi * cycles) - pi / 2;
    final x = center.dx + cos(angle) * radius;
    final y = center.dy + sin(angle) * radius;
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;

    // базовый диаметр окружности (до масштабирования)
    final baseDiameter = screenW * circleWidthFactor;

    // максимальный возможный диаметр (учитываем расширение при вдохе)
    final maxDiameter = baseDiameter * circleMaxScale;

    // небольшой запас, чтобы ничего не обрезалось
    final paddingAround = 24.0;

    // итоговый контейнер, чтобы вместить максимум окружности
    final containerSize = maxDiameter + paddingAround * 2;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
          children: [
                  SafeArea(
                    child: Stack(
                       children: [
            // ---------------- BACK BUTTON ----------------
            Positioned(
              top: 12,
              left: 8,
              child: IconButton(
                icon: const Icon(
                    Icons.arrow_back, color: Colors.black87, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),

            // ---------------- TIMER + COUNTER ----------------
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  SizedBox(
                    width: timerSize,
                    height: timerSize,
                    child: AnimatedBuilder(
                      animation: _mainCtrl,
                      builder: (context, _) {
                        final p = _mainCtrl.value.clamp(0.0, 1.0);
                        return CustomPaint(
                          painter: _TimerPainterCCW(progress: p, color: purple),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: _mainCtrl,
                    builder: (context, _) {
                      final cyclesDone =
                      (_mainCtrl.value * totalSeconds ~/ cycleLen)
                          .clamp(0, cycles);
                      return Text(
                        '$cyclesDone/$cycles',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ---------------- CENTER CIRCLE + BALL ----------------
            Center(
              child: SizedBox(
                width: containerSize,
                height: containerSize,
                child: AnimatedBuilder(
                  animation: _mainCtrl,
                  builder: (context, _) {
                    final progress = _mainCtrl.value.clamp(0.0, 1.0);
                    final secondsNow = progress * totalSeconds;

                    // масштаб окружности (1..1.22)
                    final circleScale = _circleScaleFor(secondsNow);

                    // текущий фраза
                    final phrase = _phraseFor(secondsNow);

                    // центр
                    final center = Offset(containerSize / 2, containerSize / 2);

                    // диаметр и радиус текущей окружности
                    final drawDiameter = baseDiameter * circleScale;
                    final radius = drawDiameter / 2;

                    // позиция шарика по окружности
                    final ballScale = _ballScaleFor(secondsNow);
                    final ballPos = _ballPosOnCircle(progress, radius, center);

                    // анимация слов
                    final phraseOpacity =
                    (phrase != null && running && !finished) ? 1.0 : 0.0;

                    return Stack(
                      children: [
                        // ---------------- VISIBLE CIRCLE ----------------
                        Positioned(
                          left: center.dx - radius,
                          top: center.dy - radius,
                          width: drawDiameter,
                          height: drawDiameter,
                          child: CustomPaint(
                            painter: _CircleBasePainter(
                              color: Colors.grey.shade100,
                            ),
                          ),
                        ),

                        Positioned(
                          left: center.dx - radius,
                          top: center.dy - radius,
                          width: drawDiameter,
                          height: drawDiameter,
                          child: CustomPaint(
                            painter: _CircleStrokePainter(
                              color: purple.withOpacity(0.22),
                            ),
                          ),
                        ),

                        // ---------------- MOVING BALL ----------------
                        Positioned(
                          left: ballPos.dx - (ballBaseSize * ballScale) / 2,
                          top: ballPos.dy - (ballBaseSize * ballScale) / 2,
                          child: Transform.scale(
                            scale: ballScale,
                            child: Container(
                              width: ballBaseSize,
                              height: ballBaseSize,
                              decoration: BoxDecoration(
                                color: purple,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),

                        // ---------------- PHRASES (Вдох / Выдох) ----------------
                        Positioned.fill(
                          child: Center(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 900), // было 550
                              curve: Curves.easeOutQuad,
                              opacity: phraseOpacity,
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.easeOutQuad,
                                scale: phraseOpacity > 0 ? 1.0 : 0.94, // мягкое уменьшение
                                child: Text(
                                  phrase ?? '',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: purple,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ---------------- FINISH TEXT ----------------
                        if (finished)
                          Positioned.fill(
                            child: Center(
                              child: FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: _confettiCtrl,
                                  curve: const Interval(0.0, 0.4),
                                ),
                                child: Text(
                                  'Конец',
                                  style: TextStyle(
                                    fontSize: 42,
                                    fontWeight: FontWeight.bold,
                                    color: purple,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // ---------------- START / STOP BUTTON ----------------
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: ElevatedButton(
                  onPressed: () {
                    if (!running) {
                      setState(() {
                        running = true;
                        finished = false;
                      });
                      _start();
                    } else {
                      _stop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: purple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    running ? 'Стоп' : 'Старт',
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
            // ---------------- CONFETTI ----------------
            if (_confettiCtrl.value > 0.0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter:
                    _ConfettiPainter(progress: _confettiCtrl.value),
                  ),
                ),
              ),
          ],
    ),);
  }
}

/// Painter for circular timer (counter-clockwise)
class _TimerPainterCCW extends CustomPainter {
  final double progress;
  final Color color;

  _TimerPainterCCW({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);

    final bg = Paint()
      ..color = color.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Background circle
    canvas.drawCircle(center, r - 3, bg);

    // CCW arc (negative sweep)
    final sweep = -progress * 2 * pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r - 3),
      -pi / 2,
      sweep,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _TimerPainterCCW old) =>
      old.progress != progress || old.color != color;
}

class _CircleBasePainter extends CustomPainter {
  final Color color;
  _CircleBasePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    final paint = Paint()..color = color;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _CircleBasePainter old) => false;
}

class _CircleStrokePainter extends CustomPainter {
  final Color color;
  _CircleStrokePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _CircleStrokePainter old) => false;
}

/// Улучшенное конфетти, которое падает вниз и исчезает.
class _ConfettiPainter extends CustomPainter {
  final double progress; // 0..1
  _ConfettiPainter({required this.progress});

  final List<Color> colors = [
    Colors.redAccent,
    Colors.greenAccent,
    Colors.lightBlueAccent,
    Colors.orangeAccent,
    Colors.purpleAccent,
    Colors.yellowAccent,
    Colors.cyanAccent,
    Colors.pinkAccent,
    Colors.tealAccent,
    Colors.amberAccent,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(777);
    final int count = 160;
    final double t = progress.clamp(0.0, 1.0);

    final launchPhase = (t < 0.65)
        ? (t / 0.65)
        : 1.0;                        // 0..1 — только взлёт
    final fallPhase = (t > 0.65)
        ? ((t - 0.65) / 0.35).clamp(0.0, 1.0)
        : 0.0;                          // 0..1 — падение вниз

    for (int i = 0; i < count; i++) {
      final fromLeft = rnd.nextBool();

      final startX = fromLeft ? -20.0 : size.width + 20.0;
      final startY = size.height * (0.4 + rnd.nextDouble() * 0.15);

      final speed = 300 + rnd.nextDouble() * 340;
      final angle = (fromLeft ? pi / 3 : 2 * pi / 3) +
          (rnd.nextDouble() - 0.5) * 0.55;

      // ---------------- ВЗЛЁТ ----------------
      double dx = startX + cos(angle) * speed * launchPhase * 0.85;
      double dy = startY - sin(angle) * speed * launchPhase + 250 * launchPhase * launchPhase;

      // ---------------- ПАДЕНИЕ ----------------
      if (fallPhase > 0) {
        dy += fallPhase * fallPhase * 600;  // ускоренное падение
      }

      // исчезновение
      final opacity = (1 - fallPhase).clamp(0.0, 1.0);

      final particlePaint = Paint()
        ..color = colors[rnd.nextInt(colors.length)].withOpacity(opacity);

      final sizeW = 6 + rnd.nextDouble() * 9;
      final sizeH = sizeW * (0.5 + rnd.nextDouble() * 0.5);

      // вращение
      final rot = rnd.nextDouble() * pi * 2 * (launchPhase + fallPhase * 0.8);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rot);

      switch (rnd.nextInt(3)) {
        case 0:
          canvas.drawRect(
              Rect.fromCenter(center: Offset(0, 0), width: sizeW, height: sizeH),
              particlePaint);
          break;
        case 1:
          canvas.drawCircle(Offset(0, 0), sizeW * 0.45, particlePaint);
          break;
        case 2:
          final path = Path()
            ..moveTo(0, -sizeH / 2)
            ..lineTo(sizeW / 2, sizeH / 2)
            ..lineTo(-sizeW / 2, sizeH / 2)
            ..close();
          canvas.drawPath(path, particlePaint);
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

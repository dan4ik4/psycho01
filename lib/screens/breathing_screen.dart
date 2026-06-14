import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';

class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key});

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen> with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late ConfettiController _confettiController;

  // Твоя неизменная палитра
  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color accentPurple = const Color(0xFF7862D6);
  final Color warmWhite = const Color(0xFFFFF9F2);
  final Color textPrimary = const Color(0xFF323045);
  final Color textSecondary = const Color(0xFF706D8C);
  final Color weekendRed = const Color(0xFFFF8A80);

  String _instructionText = "Готовы?";
  bool _isPlaying = false;
  bool _isFinished = false;

  int _currentCycle = 1;
  final int _totalCycles = 3;

  final int inhaleDuration = 4000;
  final int holdDuration = 7000;
  final int exhaleDuration = 8000;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 4));
    _animationController = AnimationController(vsync: this);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 2.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.addStatusListener((status) {
      if (!_isPlaying) return;
      if (status == AnimationStatus.completed) {
        setState(() => _instructionText = "Задержите дыхание");
        Future.delayed(Duration(milliseconds: holdDuration), () {
          if (!mounted || !_isPlaying) return;
          setState(() => _instructionText = "Медленный выдох");
          _animationController.duration = Duration(milliseconds: exhaleDuration);
          _animationController.reverse();
        });
      } else if (status == AnimationStatus.dismissed) {
        if (_currentCycle >= _totalCycles) {
          _finishPractice();
        } else {
          setState(() {
            _currentCycle++;
            _instructionText = "Глубокий вдох";
          });
          _animationController.duration = Duration(milliseconds: inhaleDuration);
          _animationController.forward();
        }
      }
    });
  }

  void _finishPractice() {
    setState(() {
      _isPlaying = false;
      _isFinished = true;
      _instructionText = "Прекрасная работа!";
    });
    _confettiController.play();
  }

  void _toggleBreathing() {
    setState(() {
      if (_isFinished) {
        _isFinished = false;
        _currentCycle = 1;
        _confettiController.stop();
      }
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _instructionText = "Глубокий вдох";
        _animationController.duration = Duration(milliseconds: inhaleDuration);
        _animationController.forward();
      } else {
        _instructionText = "Пауза";
        _animationController.stop();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ОТЗЕРКАЛЕНО: Фон теперь фиолетовый
      backgroundColor: deepPurple,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          // ОТЗЕРКАЛЕНО: Иконка назад теперь белая
          icon: Icon(Icons.arrow_back, color: warmWhite),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 20.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  // ОТЗЕРКАЛЕНО: Плашка счетчика светлая полупрозрачная
                  color: warmWhite.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  "$_currentCycle / $_totalCycles",
                  style: TextStyle(
                      color: warmWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 16
                  ),
                ),
              ),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // КОНФЕТТИ (НЕ ТРОГАЕМ)
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple,
                Colors.yellow,
                Colors.cyan,
                Color(0xFFFF00FF),
                Colors.pinkAccent,
              ],
              minimumSize: const Size(15, 10),
              maximumSize: const Size(30, 15),
              numberOfParticles: 50,
              emissionFrequency: 0.2,
              gravity: 0.1,
              maxBlastForce: 40,
              minBlastForce: 20,
            ),

            Column(
              children: [
                const SizedBox(height: 60),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 500),
                  child: Text(
                    _instructionText,
                    key: ValueKey(_instructionText),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      // ОТЗЕРКАЛЕНО: Текст инструкции теперь белый
                      color: warmWhite,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                const Spacer(flex: 2),

                // ОТЗЕРКАЛЕНО: Круг теперь белый
                Center(
                  child: AnimatedBuilder(
                    animation: _scaleAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // Внешние кольца теперь светлые
                            color: warmWhite.withOpacity(0.1),
                            border: Border.all(color: warmWhite.withOpacity(0.2), width: 2),
                          ),
                          child: Center(
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                // Ядро теперь белое
                                color: warmWhite,
                              ),
                              child: Icon(
                                  _isFinished ? Icons.star : Icons.air,
                                  // Иконка внутри стала фиолетовой для контраста
                                  color: deepPurple,
                                  size: 45
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const Spacer(flex: 3),

                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: GestureDetector(
                    onTap: _toggleBreathing,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18),
                      decoration: BoxDecoration(
                        // ОТЗЕРКАЛЕНО: Основная кнопка теперь белая, кнопка стоп остается красной
                          color: _isFinished
                              ? warmWhite
                              : (_isPlaying ? weekendRed : warmWhite),
                          borderRadius: BorderRadius.circular(35),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 8)
                            )
                          ]
                      ),
                      child: Text(
                        _isFinished ? "Заново" : (_isPlaying ? "Стоп" : "Начать"),
                        style: TextStyle(
                          // ОТЗЕРКАЛЕНО: Текст на белой кнопке — фиолетовый
                            color: _isPlaying ? warmWhite : accentPurple,
                            fontSize: 18,
                            fontWeight: FontWeight.bold
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
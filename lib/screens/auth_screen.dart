import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_navigation_screen.dart';

enum AuthStep { login, registerEmail, registerOTP, registerProfile, forgotPasswordEmail, forgotPasswordOTP, resetPassword }

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  // Контроллеры
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final otpController = TextEditingController();
  final fioController = TextEditingController();
  final ageController = TextEditingController();

  bool isLogin = true;
  String? selectedGender;
  String selectedRole = 'client';
  AuthStep currentStep = AuthStep.login;

  final _formKey = GlobalKey<FormState>();

  // Цветовая палитра
  final Color deepPurple = const Color(0xFF2D1B4E);
  final Color accentPurple = const Color(0xFF9575CD);
  final Color warmWhite = const Color(0xFFFFF9F2);

  // --- ЛОГИКА SUPABASE (ПРОВЕРЕНО) ---

  Future<void> _startSignUp() async {
    try {
      await supabase.auth.signUp(email: emailController.text.trim(), password: passwordController.text);
      setState(() => currentStep = AuthStep.registerOTP);
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _verifySignUpOTP() async {
    try {
      await supabase.auth.verifyOTP(email: emailController.text.trim(), token: otpController.text.trim(), type: OtpType.signup);
      setState(() => currentStep = AuthStep.registerProfile);
    } catch (e) { _showError("Неверный код подтверждения"); }
  }

  Future<void> _completeProfile() async {
    try {
      if (selectedGender == null) throw "Выберите пол";
      await supabase.auth.updateUser(UserAttributes(data: {
        'full_name': fioController.text.trim(),
        'gender': selectedGender,
        'age': int.parse(ageController.text.trim()),
        'role': selectedRole,
      }));
      _navigateToHome(selectedRole);
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _sendPasswordReset() async {
    try {
      await supabase.auth.resetPasswordForEmail(emailController.text.trim());
      setState(() => currentStep = AuthStep.forgotPasswordOTP);
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _verifyResetOTP() async {
    try {
      await supabase.auth.verifyOTP(email: emailController.text.trim(), token: otpController.text.trim(), type: OtpType.recovery);
      setState(() => currentStep = AuthStep.resetPassword);
    } catch (e) { _showError("Неверный код"); }
  }

  Future<void> _updatePassword() async {
    if (passwordController.text != confirmPasswordController.text) { _showError("Пароли не совпадают"); return; }
    try {
      await supabase.auth.updateUser(UserAttributes(password: passwordController.text));
      _navigateToHome();
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _login() async {
    try {
      await supabase.auth.signInWithPassword(email: emailController.text.trim(), password: passwordController.text);
      _navigateToHome();
    } catch (e) { _showError("Ошибка входа: проверьте Email и пароль"); }
  }

  void _navigateToHome([String? role]) {
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainNavigationScreen(forcedRole: role)));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- ВСПЛЫВАЮЩИЕ ОКНА С ГРАДИЕНТОМ ---

  void _showAuthDialog(AuthStep initialStep) {
    setState(() => currentStep = initialStep);
    bool obscurePassword = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (context, anim1, anim2) => Container(),
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  // ГРАДИЕНТ ДЛЯ ВСЕХ ОКОН
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [warmWhite, const Color(0xFFF1EAFF)],
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_getStepTitle(), style: TextStyle(color: deepPurple, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          key: ValueKey(currentStep),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (currentStep == AuthStep.login) ...[
                              _buildTextField(emailController, 'Email', Icons.mail_outline),
                              _buildPasswordField(passwordController, "Пароль", obscurePassword, (v) => setDialogState(() => obscurePassword = v)),
                              // ВЕРНУЛ ФУНКЦИЮ СБРОСА ПАРОЛЯ
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => setDialogState(() => currentStep = AuthStep.forgotPasswordEmail),
                                  child: Text('Забыли пароль?', style: TextStyle(color: accentPurple, fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ],
                            if (currentStep == AuthStep.registerEmail || currentStep == AuthStep.forgotPasswordEmail) ...[
                              _buildTextField(emailController, 'Email', Icons.email_outlined),
                              if (currentStep == AuthStep.registerEmail) _buildPasswordField(passwordController, "Пароль", obscurePassword, (v) => setDialogState(() => obscurePassword = v)),
                            ],
                            if (currentStep == AuthStep.registerOTP || currentStep == AuthStep.forgotPasswordOTP) ...[
                              Text("Введите код подтверждения", style: TextStyle(color: deepPurple.withOpacity(0.6))),
                              const SizedBox(height: 10),
                              _buildTextField(otpController, 'Код', Icons.vpn_key_outlined, isNum: true),
                            ],
                            if (currentStep == AuthStep.registerProfile) ...[
                              _buildSectionTitle("Ваша роль:"),
                              Row(children: [
                                _customRadioButton("Клиент", selectedRole == 'client', () => setDialogState(() => selectedRole = 'client')),
                                const SizedBox(width: 10),
                                _customRadioButton("Профи", selectedRole == 'specialist', () => setDialogState(() => selectedRole = 'specialist')),
                              ]),
                              const SizedBox(height: 10),
                              _buildTextField(fioController, 'ФИО', Icons.person_outline),
                              _genderSelector(setDialogState),
                              _buildTextField(ageController, 'Возраст', Icons.cake_outlined, isNum: true),
                            ],
                            if (currentStep == AuthStep.resetPassword) ...[
                              _buildPasswordField(passwordController, "Новый пароль", obscurePassword, (v) => setDialogState(() => obscurePassword = v)),
                              _buildPasswordField(confirmPasswordController, "Повторите пароль", obscurePassword, (v) => setDialogState(() => obscurePassword = v)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentPurple,
                        minimumSize: const Size(double.infinity, 60),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 4,
                      ),
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        if (currentStep == AuthStep.login) await _login();
                        else if (currentStep == AuthStep.registerEmail) await _startSignUp();
                        else if (currentStep == AuthStep.registerOTP) await _verifySignUpOTP();
                        else if (currentStep == AuthStep.registerProfile) await _completeProfile();
                        else if (currentStep == AuthStep.forgotPasswordEmail) await _sendPasswordReset();
                        else if (currentStep == AuthStep.forgotPasswordOTP) await _verifyResetOTP();
                        else if (currentStep == AuthStep.resetPassword) await _updatePassword();
                        setDialogState(() {});
                      },
                      child: Text(_getButtonText(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Отмена', style: TextStyle(color: deepPurple.withOpacity(0.4))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [deepPurple, warmWhite],
            stops: const [0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ЛОТОС И ЦИКЛИЧНЫЕ ОРБИТЫ
                    SizedBox(
                      height: 320,
                      width: 320,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _InfiniteDustOrbit(color: accentPurple.withOpacity(0.7)),
                          Container(
                            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                              BoxShadow(color: accentPurple.withOpacity(0.2), blurRadius: 100, spreadRadius: 30)
                            ]),
                            child: Image.asset('assets/images/lotus.png', height: 200),
                          ),
                        ],
                      ),
                    ),
                    Text("SoulBuddy", style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: warmWhite, letterSpacing: -2)),
                    Text("Найди свой покой", style: TextStyle(color: warmWhite.withOpacity(0.6), fontSize: 16)),
                    const SizedBox(height: 70),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 50),
                      child: Column(
                        children: [
                          _buildMainButton("Войти", true, () { setState(() => isLogin = true); _showAuthDialog(AuthStep.login); }),
                          const SizedBox(height: 20),
                          _buildMainButton("Регистрация", false, () { setState(() => isLogin = false); _showAuthDialog(AuthStep.registerEmail); }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // ТЕСТОВЫЕ КНОПКИ
              Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _debugEntryBtn("Тест: Клиент", () => _navigateToHome('client')),
                    const SizedBox(width: 40),
                    _debugEntryBtn("Тест: Профи", () => _navigateToHome('specialist')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- ХЕЛПЕРЫ И ВИДЖЕТЫ ---

  Widget _buildMainButton(String text, bool isPrimary, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, height: 70,
        decoration: BoxDecoration(
          color: isPrimary ? accentPurple : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(28),
          border: isPrimary ? null : Border.all(color: warmWhite.withOpacity(0.3)),
          boxShadow: isPrimary ? [BoxShadow(color: accentPurple.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))] : [],
        ),
        child: Center(child: Text(text, style: TextStyle(color: warmWhite, fontSize: 18, fontWeight: FontWeight.bold))),
      ),
    );
  }

  Widget _debugEntryBtn(String label, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Text(label, style: TextStyle(color: deepPurple.withOpacity(0.4), fontSize: 13, decoration: TextDecoration.underline)));
  }

  String _getStepTitle() {
    switch (currentStep) {
      case AuthStep.login: return "Вход";
      case AuthStep.registerEmail: return "Создать аккаунт";
      case AuthStep.registerOTP: return "Подтверждение";
      case AuthStep.registerProfile: return "Ваш профиль";
      case AuthStep.forgotPasswordEmail: return "Сброс пароля";
      case AuthStep.forgotPasswordOTP: return "Код из почты";
      case AuthStep.resetPassword: return "Новый пароль";
    }
  }

  String _getButtonText() {
    if (currentStep == AuthStep.registerOTP || currentStep == AuthStep.forgotPasswordOTP) return "Подтвердить";
    if (currentStep == AuthStep.registerEmail || currentStep == AuthStep.forgotPasswordEmail) return "Далее";
    if (currentStep == AuthStep.resetPassword) return "Сохранить";
    return isLogin ? "Войти" : "Продолжить";
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNum = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: deepPurple),
        decoration: InputDecoration(
          labelText: label, prefixIcon: Icon(icon, color: accentPurple),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        ),
        validator: (v) => v!.isEmpty ? 'Заполните' : null,
      ),
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String label, bool obscure, Function(bool) toggle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller, obscureText: obscure,
        style: TextStyle(color: deepPurple),
        decoration: InputDecoration(
          labelText: label, prefixIcon: Icon(Icons.lock_person_outlined, color: accentPurple),
          suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: accentPurple), onPressed: () => toggle(!obscure)),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        ),
        validator: (v) => v!.length < 6 ? 'Минимум 6 знаков' : null,
      ),
    );
  }

  Widget _genderSelector(StateSetter setStateDialog) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      _genderRadio(setStateDialog, 'Мужчина'),
      const SizedBox(width: 20),
      _genderRadio(setStateDialog, 'Женщина'),
    ]);
  }

  Widget _genderRadio(StateSetter setStateDialog, String gender) {
    bool isSel = selectedGender == gender;
    return GestureDetector(
      onTap: () => setStateDialog(() => selectedGender = gender),
      child: Row(children: [
        Icon(isSel ? Icons.check_circle : Icons.circle_outlined, color: accentPurple, size: 22),
        const SizedBox(width: 6), Text(gender, style: TextStyle(color: deepPurple)),
      ]),
    );
  }

  Widget _customRadioButton(String title, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? accentPurple : Colors.white,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Center(child: Text(title, style: TextStyle(color: isSelected ? Colors.white : deepPurple, fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: deepPurple.withOpacity(0.5))),
  );
}

// --- АНИМАЦИЯ ПЫЛИ ---
class _InfiniteDustOrbit extends StatefulWidget {
  final Color color;
  const _InfiniteDustOrbit({required this.color});
  @override
  _InfiniteDustOrbitState createState() => _InfiniteDustOrbitState();
}

class _InfiniteDustOrbitState extends State<_InfiniteDustOrbit> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_OrbitParticle> particles = List.generate(40, (_) => _OrbitParticle());

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: particles.map((p) {
            final double progress = (_controller.value + p.startProgress) % 1.0;
            final double angle = progress * 2 * math.pi;
            final double x = p.radiusX * math.cos(angle);
            final double y = p.radiusY * math.sin(angle);

            return Transform.translate(
              offset: Offset(x, y),
              child: Opacity(
                opacity: (math.sin(progress * math.pi)).abs() * 0.7,
                child: Container(
                  width: p.size, height: p.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: widget.color,
                    boxShadow: [BoxShadow(color: widget.color, blurRadius: 4)],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _OrbitParticle {
  final double radiusX = 100 + math.Random().nextDouble() * 60;
  final double radiusY = 90 + math.Random().nextDouble() * 50;
  final double startProgress = math.Random().nextDouble();
  final double size = 1.0 + math.Random().nextDouble() * 4.0;
}
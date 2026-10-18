import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

import '../core/api/api_exception.dart';
import '../core/widgets/oakle_notice.dart';
import '../main.dart';
import 'main_navigation_screen.dart';

class BirthDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < limited.length; i++) {
      if (i == 2 || i == 4) buffer.write('.');
      buffer.write(limited[i]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

enum AuthStep {
  login,
  registerEmail,
  registerOTP,
  registerProfile,
  forgotPasswordEmail,
  checkEmail,
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  // Контроллеры
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final otpController = TextEditingController();
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final birthDateController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;
  DateTime? birthDate;
  AuthStep currentStep = AuthStep.login;

  final _formKey = GlobalKey<FormState>();

  // Цветовая палитра
  final Color deepPurple = const Color(0xFFB0A6E8);
  final Color accentPurple = const Color(0xFF7862D6);
  final Color warmWhite = const Color(0xFFF6F8FD);
  final Color textPrimary = const Color(0xFF323045);
  final Color textSecondary = const Color(0xFF706D8C);

  @override
  void initState() {
    super.initState();
    _hideSystemUI();
  }

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  void _clearInputs() {
    emailController.clear();
    passwordController.clear();
    confirmPasswordController.clear();
    otpController.clear();
    firstNameController.clear();
    lastNameController.clear();
    birthDateController.clear();
    birthDate = null;
  }

  String _extractErrorMessage(dynamic e) {
    if (e is ApiException) {
      return e.userMessage;
    }
    return e.toString();
  }

  // --- ЛОГИКА FASTAPI REST API (Через AuthRepository) ---

  Future<void> _startSignUp() async {
    try {
      await authRepository.preRegister(
        emailController.text.trim(),
        passwordController.text,
      );
      setState(() => currentStep = AuthStep.registerOTP);
    } catch (e) {
      _showError(_extractErrorMessage(e));
    }
  }

  Future<void> _verifySignUpOTP() async {
    try {
      await authRepository.verifySignUpOtp(
        emailController.text.trim(),
        otpController.text.trim(),
      );
      // API confirms the account but does not return a token. Log in before
      // sending the profile update, which requires an authenticated user.
      try {
        await authRepository.login(
          emailController.text.trim(),
          passwordController.text,
        );
        setState(() => currentStep = AuthStep.registerProfile);
      } catch (error) {
        setState(() => currentStep = AuthStep.login);
        _showError(
          'Аккаунт подтверждён. Войдите с указанными email и паролем, чтобы продолжить настройку профиля.',
        );
      }
    } catch (e) {
      _showError(_extractErrorMessage(e));
    }
  }

  Future<void> _completeProfile() async {
    try {
      final typedDate = _parseBirthDate(birthDateController.text);
      if (typedDate != null) birthDate = typedDate;
      if (birthDate == null) throw "Укажите дату рождения";
      await authRepository.completeProfile(
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
        birthDate: birthDate!,
      );
      _navigateToHome('client');
    } catch (e) {
      _showError(_extractErrorMessage(e));
    }
  }

  DateTime? _parseBirthDate(String value) {
    final match = RegExp(
      r'^(\d{2})\.(\d{2})\.(\d{4})$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final day = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (year < 1900 ||
        date.year != year ||
        date.month != month ||
        date.day != day ||
        date.isAfter(DateTime.now()))
      return null;
    return date;
  }

  Future<void> _login() async {
    try {
      final userRole = await authRepository.login(
        emailController.text.trim(),
        passwordController.text,
      );
      _navigateToHome(userRole);
    } catch (e) {
      _showError(_extractErrorMessage(e));
    }
  }

  Future<void> _sendPasswordReset() async {
    try {
      await authRepository.sendPasswordReset(emailController.text.trim());
      setState(() => currentStep = AuthStep.checkEmail);
    } catch (e) {
      _showError(_extractErrorMessage(e));
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    otpController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    birthDateController.dispose();
    super.dispose();
  }

  void _navigateToHome([String? role]) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MainNavigationScreen(forcedRole: role, apiClient: apiClient),
      ),
    );
  }

  void _showError(String msg) {
    showOakleNotice(context, msg, isError: true);
  }

  // --- ВСПЛЫВАЮЩИЕ ОКНА ---

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
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [warmWhite, const Color(0xFFF1EAFF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getStepTitle(),
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                                _buildTextField(
                                  emailController,
                                  'Email',
                                  Icons.mail_outline,
                                ),
                                _buildPasswordField(
                                  passwordController,
                                  "Пароль",
                                  obscurePassword,
                                  (v) =>
                                      setDialogState(() => obscurePassword = v),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () {
                                      _clearInputs();
                                      setDialogState(
                                        () => currentStep =
                                            AuthStep.forgotPasswordEmail,
                                      );
                                    },
                                    child: Text(
                                      'Забыли пароль?',
                                      style: TextStyle(
                                        color: accentPurple,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (currentStep == AuthStep.registerEmail ||
                                  currentStep ==
                                      AuthStep.forgotPasswordEmail) ...[
                                _buildTextField(
                                  emailController,
                                  'Email',
                                  Icons.email_outlined,
                                ),
                                if (currentStep == AuthStep.registerEmail)
                                  _buildPasswordField(
                                    passwordController,
                                    "Пароль",
                                    obscurePassword,
                                    (v) => setDialogState(
                                      () => obscurePassword = v,
                                    ),
                                  ),
                              ],
                              if (currentStep == AuthStep.registerOTP) ...[
                                Text(
                                  "Введите 6-значный код из письма",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: textSecondary),
                                ),
                                const SizedBox(height: 10),
                                _buildTextField(
                                  otpController,
                                  'Код подтверждения',
                                  Icons.vpn_key_outlined,
                                  isNum: true,
                                ),
                              ],
                              if (currentStep == AuthStep.checkEmail)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    'Если для этого адреса есть аккаунт, мы отправили письмо со ссылкой для смены пароля. Откройте ссылку на этом устройстве.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: textSecondary),
                                  ),
                                ),
                              if (currentStep == AuthStep.registerProfile) ...[
                                _buildTextField(
                                  firstNameController,
                                  'Имя',
                                  Icons.person_outline,
                                ),
                                _buildTextField(
                                  lastNameController,
                                  'Фамилия',
                                  Icons.person_outline,
                                ),
                                TextFormField(
                                  controller: birthDateController,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [BirthDateInputFormatter()],
                                  decoration: InputDecoration(
                                    labelText: 'Дата рождения',
                                    hintText: 'ДД.ММ.ГГГГ',
                                    prefixIcon: const Icon(Icons.cake_outlined),
                                    suffixIcon: IconButton(
                                      tooltip: 'Выбрать в календаре',
                                      icon: const Icon(Icons.calendar_month),
                                      onPressed: () async {
                                        final chosen = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              birthDate ?? DateTime(2000, 1, 1),
                                          firstDate: DateTime(1900),
                                          lastDate: DateTime.now(),
                                        );
                                        if (chosen != null) {
                                          setDialogState(() {
                                            birthDate = chosen;
                                            birthDateController.text =
                                                '${chosen.day.toString().padLeft(2, '0')}.${chosen.month.toString().padLeft(2, '0')}.${chosen.year}';
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  validator: (value) =>
                                      _parseBirthDate(value ?? '') == null
                                      ? 'Введите реальную дату в формате ДД.ММ.ГГГГ'
                                      : null,
                                ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          elevation: 4,
                        ),
                        onPressed: isLoading
                            ? null
                            : () async {
                                if (currentStep == AuthStep.checkEmail) {
                                  Navigator.pop(context);
                                  return;
                                }
                                if (!_formKey.currentState!.validate()) return;
                                setDialogState(() => isLoading = true);

                                if (currentStep == AuthStep.login)
                                  await _login();
                                else if (currentStep == AuthStep.registerEmail)
                                  await _startSignUp();
                                else if (currentStep == AuthStep.registerOTP)
                                  await _verifySignUpOTP();
                                else if (currentStep ==
                                    AuthStep.registerProfile)
                                  await _completeProfile();
                                else if (currentStep ==
                                    AuthStep.forgotPasswordEmail)
                                  await _sendPasswordReset();

                                if (context.mounted) {
                                  setDialogState(() => isLoading = false);
                                }
                              },
                        child: isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(
                                _getButtonText(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                      ),
                      TextButton(
                        onPressed: currentStep == AuthStep.checkEmail
                            ? () {
                                _clearInputs();
                                setDialogState(
                                  () => currentStep = AuthStep.login,
                                );
                              }
                            : () {
                                _clearInputs();
                                Navigator.pop(context);
                              },
                        child: Text(
                          'Отмена',
                          style: TextStyle(color: textSecondary),
                        ),
                      ),
                    ],
                  ),
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
    _hideSystemUI();
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
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
                    SizedBox(
                      height: 320,
                      width: 320,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _InfiniteDustOrbit(
                            color: accentPurple.withOpacity(0.7),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accentPurple.withOpacity(0.2),
                                  blurRadius: 100,
                                  spreadRadius: 30,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/White_Lotus.png',
                              height: 260,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      "Oakle",
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                        color: warmWhite,
                        letterSpacing: -2,
                      ),
                    ),
                    Text(
                      "Найди свой покой",
                      style: TextStyle(color: warmWhite, fontSize: 16),
                    ),
                    const SizedBox(height: 70),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 50),
                      child: Column(
                        children: [
                          _buildMainButton("Войти", true, () {
                            _clearInputs();
                            setState(() => isLogin = true);
                            _showAuthDialog(AuthStep.login);
                          }),
                          const SizedBox(height: 20),
                          _buildMainButton("Регистрация", false, () {
                            _clearInputs();
                            setState(() => isLogin = false);
                            _showAuthDialog(AuthStep.registerEmail);
                          }),
                        ],
                      ),
                    ),
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
        width: double.infinity,
        height: 70,
        decoration: BoxDecoration(
          color: isPrimary ? accentPurple : Colors.white.withOpacity(0.4),
          borderRadius: BorderRadius.circular(28),
          border: isPrimary
              ? null
              : Border.all(color: textPrimary.withOpacity(0.2)),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: accentPurple.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isPrimary ? warmWhite : textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  String _getStepTitle() {
    switch (currentStep) {
      case AuthStep.login:
        return "Вход";
      case AuthStep.registerEmail:
        return "Создать аккаунт";
      case AuthStep.registerOTP:
        return "Подтверждение";
      case AuthStep.registerProfile:
        return "Ваш профиль";
      case AuthStep.forgotPasswordEmail:
        return "Сброс пароля";
      case AuthStep.checkEmail:
        return "Проверьте почту";
    }
  }

  String _getButtonText() {
    if (currentStep == AuthStep.registerOTP) return "Проверить";
    if (currentStep == AuthStep.forgotPasswordEmail) return "Отправить ссылку";
    if (currentStep == AuthStep.checkEmail) return "Готово";
    if (currentStep == AuthStep.registerEmail) return "Далее";
    return isLogin ? "Войти" : "Продолжить";
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNum = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        style: TextStyle(color: textPrimary),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: accentPurple),
          labelStyle: TextStyle(color: textSecondary),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
        validator: (v) => v!.isEmpty ? 'Заполните' : null,
      ),
    );
  }

  Widget _buildPasswordField(
    TextEditingController controller,
    String label,
    bool obscure,
    Function(bool) toggle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(color: textPrimary),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(Icons.lock_person_outlined, color: accentPurple),
          labelStyle: TextStyle(color: textSecondary),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              color: accentPurple,
            ),
            onPressed: () => toggle(!obscure),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
        validator: (v) => v!.length < 8 ? 'Минимум 8 символов' : null,
      ),
    );
  }
}

class _InfiniteDustOrbit extends StatefulWidget {
  final Color color;
  const _InfiniteDustOrbit({required this.color});
  @override
  _InfiniteDustOrbitState createState() => _InfiniteDustOrbitState();
}

class _InfiniteDustOrbitState extends State<_InfiniteDustOrbit>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_OrbitParticle> particles = List.generate(
    40,
    (_) => _OrbitParticle(),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
                  width: p.size,
                  height: p.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF6F8FD),
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

class ResetPasswordScreen extends StatefulWidget {
  final String token;

  const ResetPasswordScreen({super.key, required this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _showPassword = false;
  bool _showConfirmation = false;
  String? _error;

  static const _background = Color(0xFFB0A6E8);
  static const _accent = Color(0xFF7862D6);
  static const _surface = Color(0xFFF6F8FD);
  static const _text = Color(0xFF323045);
  static const _muted = Color(0xFF706D8C);

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await authRepository.updatePassword(widget.token, _password.text);
      await tokenStorage.clearToken();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final rootContext = navigatorKey.currentContext;
        if (rootContext != null) {
          showOakleNotice(
            rootContext,
            'Пароль изменён. Теперь войдите с новым паролем.',
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      final message =
          error is ApiException &&
              (error.statusCode == 400 || error.statusCode == 422)
          ? 'Не удалось изменить пароль. Возможно, ссылка уже использована или истекла, либо пароль не подходит требованиям сервера.'
          : friendlyApiError(error);
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _background,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 36,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton.filledTonal(
                        tooltip: 'Назад ко входу',
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const AuthScreen(),
                                ),
                                (_) => false,
                              ),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const CircleAvatar(
                              radius: 34,
                              backgroundColor: Color(0xFFE8E3FA),
                              child: Icon(
                                Icons.lock_reset_rounded,
                                color: _accent,
                                size: 34,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Новый пароль',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _text,
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Придумайте пароль и введите его ещё раз для подтверждения.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, height: 1.4),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _password,
                              obscureText: !_showPassword,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: _decoration(
                                label: 'Новый пароль',
                                icon: Icons.lock_outline_rounded,
                                visible: _showPassword,
                                onToggle: () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                              ),
                              validator: (value) {
                                if ((value ?? '').length < 8) {
                                  return 'Пароль должен содержать минимум 8 символов';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirmation,
                              obscureText: !_showConfirmation,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.newPassword],
                              onFieldSubmitted: (_) =>
                                  _saving ? null : _submit(),
                              decoration: _decoration(
                                label: 'Повторите пароль',
                                icon: Icons.lock_outline_rounded,
                                visible: _showConfirmation,
                                onToggle: () => setState(
                                  () => _showConfirmation = !_showConfirmation,
                                ),
                              ),
                              validator: (value) => value != _password.text
                                  ? 'Пароли не совпадают'
                                  : null,
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFE9E9),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      color: Color(0xFFC62828),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: Color(0xFF9E1B1B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 54,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed:
                                    _saving || widget.token.trim().isEmpty
                                    ? null
                                    : _submit,
                                child: _saving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Сохранить новый пароль',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            if (widget.token.trim().isEmpty) ...[
                              const SizedBox(height: 14),
                              const Text(
                                'В ссылке нет кода сброса. Запросите новое письмо.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF9E1B1B)),
                              ),
                            ],
                          ],
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
    ),
  );

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    required bool visible,
    required VoidCallback onToggle,
  }) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: _accent),
    suffixIcon: IconButton(
      tooltip: visible ? 'Скрыть пароль' : 'Показать пароль',
      onPressed: onToggle,
      icon: Icon(
        visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        color: _muted,
      ),
    ),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE6E2F2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _accent, width: 1.6),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_navigation_screen.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Контроллеры для входа
  final loginEmailController = TextEditingController();
  final loginPasswordController = TextEditingController();

  // Контроллеры для регистрации
  final regEmailController = TextEditingController();
  final regPasswordController = TextEditingController();
  final fioController = TextEditingController();
  final ageController = TextEditingController();

  String? selectedGender;
  String selectedRole = 'client'; // 🟣 По умолчанию роль - клиент

  final _formKey = GlobalKey<FormState>();
  bool isLogin = true;

  final Color purple = const Color(0xFF5E3B8C);

  /// 🟣 Метод входа / регистрации
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final supabase = Supabase.instance.client;

      if (isLogin) {
        await supabase.auth.signInWithPassword(
          email: loginEmailController.text.trim(),
          password: loginPasswordController.text,
        );
      } else {
        // Проверка выбора пола перед отправкой
        if (selectedGender == null) {
          throw "Пожалуйста, выберите пол";
        }

        await supabase.auth.signUp(
          email: regEmailController.text.trim(),
          password: regPasswordController.text,
          data: {
            'full_name': fioController.text.trim(),
            'gender': selectedGender,
            'age': int.parse(ageController.text.trim()),
            'role': selectedRole, // 🟣 Сохраняем роль в базу
          },
        );
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainNavigationScreen()),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.toString()}')),
      );
    }
  }

  void _showAuthDialog() {
    // Очистка полей
    loginEmailController.clear();
    loginPasswordController.clear();
    regEmailController.clear();
    regPasswordController.clear();
    fioController.clear();
    ageController.clear();
    selectedGender = null;
    selectedRole = 'client';

    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(isLogin ? 'С возвращением!' : 'Создать аккаунт',
              style: TextStyle(color: purple, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🟣 ВЫБОР РОЛИ (Красивые переключатели в твоем стиле)
                  if (!isLogin) ...[
                    _buildSectionTitle("Кто вы?"),
                    Row(
                      children: [
                        _customRadioButton(
                          title: "Клиент",
                          isSelected: selectedRole == 'client',
                          onTap: () => setStateDialog(() => selectedRole = 'client'),
                        ),
                        const SizedBox(width: 15),
                        _customRadioButton(
                          title: "Психолог",
                          isSelected: selectedRole == 'specialist',
                          onTap: () => setStateDialog(() => selectedRole = 'specialist'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(),
                  ],

                  if (!isLogin) ...[
                    _buildTextField(fioController, 'ФИО', Icons.person_outline),

                    // 🟣 Твой оригинальный выбор пола
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Row(
                        children: [
                          const Text("Пол:  ", style: TextStyle(fontWeight: FontWeight.w500)),
                          _genderRadio(setStateDialog, 'Мужской'),
                          const SizedBox(width: 20),
                          _genderRadio(setStateDialog, 'Женский'),
                        ],
                      ),
                    ),

                    _buildTextField(ageController, 'Возраст', Icons.calendar_today, isNum: true),
                  ],

                  _buildTextField(
                      isLogin ? loginEmailController : regEmailController,
                      'Email',
                      Icons.email_outlined
                  ),

                  TextFormField(
                    controller: isLogin ? loginPasswordController : regPasswordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      prefixIcon: Icon(Icons.lock_outline, color: purple, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                        onPressed: () => setStateDialog(() => obscurePassword = !obscurePassword),
                      ),
                    ),
                    validator: (value) => value == null || value.length < 6 ? 'Минимум 6 символов' : null,
                  ),

                  if (isLogin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {},
                        child: Text('Забыли пароль?', style: TextStyle(color: purple, fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: purple,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        Navigator.pop(context);
                        _submit();
                      }
                    },
                    child: Text(isLogin ? 'Войти' : 'Зарегистрироваться', style: const TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Маленькие вспомогательные виджеты для чистоты кода ---

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey))),
  );

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNum = false}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: purple, size: 20),
      ),
      validator: (value) => value == null || value.isEmpty ? 'Заполните поле' : null,
    );
  }

  Widget _customRadioButton({required String title, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? purple : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? purple : Colors.grey.shade300),
        ),
        child: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  Widget _genderRadio(StateSetter setStateDialog, String gender) {
    return GestureDetector(
      onTap: () => setStateDialog(() => selectedGender = gender),
      child: Row(
        children: [
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: purple)),
            child: selectedGender == gender
                ? Center(child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: purple)))
                : null,
          ),
          const SizedBox(width: 6),
          Text(gender, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6FF),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 20),
                Center(child: Image.asset('assets/images/lotus.png', height: 180, width: 180)),
                Text("Welcome", style: TextStyle(fontSize: 49, fontWeight: FontWeight.bold, color: purple)),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: () { setState(() => isLogin = true); _showAuthDialog(); },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: purple,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: const Text('Вход', style: TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () { setState(() => isLogin = false); _showAuthDialog(); },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: purple, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text('Регистрация', style: TextStyle(fontSize: 18, color: purple)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Тест для Психолога
                  FloatingActionButton(
                    heroTag: "test_pro",
                    mini: true,
                    backgroundColor: Colors.green,
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        // Передаем параметр 'specialist' напрямую
                        MaterialPageRoute(builder: (_) => const MainNavigationScreen(forcedRole: 'specialist')),
                      );
                    },
                    child: const Icon(Icons.psychology, size: 18, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  // Тест для Клиента
                  FloatingActionButton(
                    heroTag: "test_client",
                    mini: true,
                    backgroundColor: purple,
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        // Передаем параметр 'client' напрямую
                        MaterialPageRoute(builder: (_) => const MainNavigationScreen(forcedRole: 'client')),
                      );
                    },
                    child: const Text('test', style: TextStyle(fontSize: 10, color: Colors.white)),
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
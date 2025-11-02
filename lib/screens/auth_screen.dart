import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
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
  final fioController = TextEditingController(); // 🟣 Для регистрации
  final ageController = TextEditingController(); // 🟣 Возраст

  String? selectedGender; // 🟣 Мужской / Женский

  final _formKey = GlobalKey<FormState>();

  bool isLogin = true;

  /// 🟣 Метод входа / регистрации
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      if (isLogin) {
        final email = loginEmailController.text.trim();
        final password = loginPasswordController.text;

        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } else {
        final email = regEmailController.text.trim();
        final password = regPasswordController.text;
        final fio = fioController.text.trim();
        final age = int.parse(ageController.text.trim());

        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': fio,
            'gender': selectedGender,
            'age': age,
          },
        );
      }

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

  /// 🟣 Диалог входа / регистрации
  /// Замените текущий метод _showAuthDialog() этим кодом
  void _showAuthDialog() {
    // 🟣 Каждый раз при открытии окна — очищаем поля и скрываем пароль
    loginEmailController.clear();
    loginPasswordController.clear();
    regEmailController.clear();
    regPasswordController.clear();
    fioController.clear();
    ageController.clear();
    selectedGender = null;

    bool obscurePassword = true; // 🟣 Локальное состояние для диалога

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          // Уменьшаем горизонтальные отступы диалога на 10px с каждой стороны,
          // чтобы общая ширина диалога увеличилась на 20px.
          insetPadding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 24.0),

          title: Text(isLogin ? 'Вход' : 'Регистрация'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // 🟣 Только при регистрации — ФИО
                if (!isLogin)
                  TextFormField(
                    controller: fioController,
                    decoration: const InputDecoration(labelText: 'ФИО'),
                    validator: (value) =>
                    value == null || value.isEmpty ? 'Введите ФИО' : null,
                  ),

                // 🟣 Только при регистрации — ПОЛ
                if (!isLogin)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const Text("Пол:  "),
                        GestureDetector(
                          onTap: () {
                            setStateDialog(() => selectedGender = 'Мужской');
                          },
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.deepPurple),
                                ),
                                child: selectedGender == 'Мужской'
                                    ? Center(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                )
                                    : null,
                              ),
                              const SizedBox(width: 6),
                              const Text("Мужской"),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        GestureDetector(
                          onTap: () {
                            setStateDialog(() => selectedGender = 'Женский');
                          },
                          child: Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.deepPurple),
                                ),
                                child: selectedGender == 'Женский'
                                    ? Center(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                )
                                    : null,
                              ),
                              const SizedBox(width: 6),
                              const Text("Женский"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // 🟣 Только при регистрации — ВОЗРАСТ
                if (!isLogin)
                  TextFormField(
                    controller: ageController,
                    decoration: const InputDecoration(labelText: 'Возраст'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Введите возраст';
                      final n = int.tryParse(value);
                      if (n == null || n < 1 || n > 150) return 'Возраст 1–150';
                      return null;
                    },
                  ),

                TextFormField(
                  controller: isLogin ? loginEmailController : regEmailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (value) =>
                  value == null || value.isEmpty ? 'Введите email' : null,
                ),

                TextFormField(
                  controller:
                  isLogin ? loginPasswordController : regPasswordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setStateDialog(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) =>
                  value == null || value.length < 6 ? 'Минимум 6 символов' : null,
                ),

                if (isLogin)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Функция восстановления пароля в разработке')),
                          );
                        },
                        child: const Text(
                          'Забыли пароль?',
                          style: TextStyle(
                            color: Colors.deepPurple,
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Выравниваем actions влево и делаем две кнопки в строке (на одном уровне)
          actionsAlignment: MainAxisAlignment.start,
          actions: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      Navigator.pop(context);
                      _submit();
                    }
                  },
                  child: Text(isLogin ? 'Войти' : 'Зарегистрироваться'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Отмена'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF5E3B8C); // 🟣 Тёмно-фиолетовый
    const bgColor = Color(0xFFF6F6FF); // Светлый фон

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 0), // 🟣 поднял выше
                Center(
                  child: Image.asset(
                    'assets/images/lotus.png',
                    height: 200, // 🟣 уменьшил, чтобы поместилось
                    width: 200,
                  ),
                ),

                // 🟣 Welcome
                Text(
                  "Welcome",
                  style: TextStyle(
                    fontSize: 49, // Саня, мы всё помним)))))))))))))))))))))))))))
                    fontWeight: FontWeight.bold,
                    color: purple,
                  ),
                ),

                const Spacer(), // 🟣 Добавляет "воздух"

                // 🔘 Кнопки
                Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          setState(() => isLogin = true);
                          _showAuthDialog();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: purple,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'Вход',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () {
                          setState(() => isLogin = false);
                          _showAuthDialog();
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: purple, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'Регистрация',
                          style: TextStyle(fontSize: 18, color: purple),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 🧪 Test-кнопка
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: purple,
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => MainNavigationScreen()),
                  );

                },
                child: const Text('test', style: TextStyle(fontSize: 12, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';

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

        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': fio},
        );
      }

      // 🟣 После успешного входа или регистрации — переход на домашний экран
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.toString()}')),
      );
    }
  }

  /// 🟣 Диалог входа / регистрации
  void _showAuthDialog() {
    // 🟣 Каждый раз при открытии окна — очищаем поля и скрываем пароль
    loginEmailController.clear();
    loginPasswordController.clear();
    regEmailController.clear();
    regPasswordController.clear();
    fioController.clear();

    bool obscurePassword = true; // 🟣 Локальное состояние для диалога

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(isLogin ? 'Вход' : 'Регистрация'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isLogin) // 🟣 Только при регистрации
                  TextFormField(
                    controller: fioController,
                    decoration: const InputDecoration(labelText: 'ФИО'),
                    validator: (value) =>
                    value == null || value.isEmpty ? 'Введите ФИО' : null,
                  ),

                TextFormField(
                  controller:
                  isLogin ? loginEmailController : regEmailController,
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
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        // 🟣 Управляем только локальным состоянием в диалоге
                        setStateDialog(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) => value == null || value.length < 6
                      ? 'Минимум 6 символов'
                      : null,
                ),

                if (isLogin)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                Text('Функция восстановления пароля в разработке')),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  _submit();
                }
              },
              child: Text(isLogin ? 'Войти' : 'Зарегистрироваться'),
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
                const SizedBox(height: 30), // 🟣 Регулирует положение лотуса
                Center(
                  child: Image.asset(
                    'assets/images/lotus.png',
                    height: 240, // 🟣 Можно изменить размер
                    width: 240,
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
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => HomeScreen()),
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

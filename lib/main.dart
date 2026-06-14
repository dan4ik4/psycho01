import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/auth_screen.dart';
// import 'screens/home_screen.dart'; // Если не используется в main, можно оставить закомментированным
import 'screens/main_navigation_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> main() async {
  // 1. Обязательная инициализация привязок Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Загрузка переменных окружения (.env)
  await dotenv.load(fileName: ".env");

  // 3. Инициализация Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Получаем текущую сессию Supabase
    final session = Supabase.instance.client.auth.currentSession;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Психологическое приложение',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru', 'RU'), // Русский
        Locale('en', 'US'), // Английский (на всякий случай)
      ],
      locale: const Locale('ru', 'RU'),
      // Проверка авторизации
      home: session == null ? AuthScreen() : const MainNavigationScreen(),
    );
  }
}
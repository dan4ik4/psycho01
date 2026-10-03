import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/api/api_client.dart';
import 'core/auth/token_storage.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/mood/data/mood_repository.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final tokenStorage = TokenStorage();
final apiClient = ApiClient(
  tokenStorage: tokenStorage,
  onUnauthorized: () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
    );
  },
);
final authRepository = AuthRepository(
  apiClient: apiClient,
  tokenStorage: tokenStorage,
);
final moodRepository = MoodRepository(apiClient: apiClient);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'SoulBuddy',
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
        Locale('ru', 'RU'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ru', 'RU'),
      home: const BootstrapScreen(), // Изменено на стартовый роутер
    );
  }
}

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final hasToken = await tokenStorage.hasToken();
    if (!hasToken) {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }

    try {
      final response = await apiClient.dio.get('/users/me');
      final role = response.data['is_psychologist'] == true ? 'specialist' : 'client';
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainNavigationScreen(forcedRole: role)));
    } catch (e) {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1E1C2A),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF7862D6)),
      ),
    );
  }
}
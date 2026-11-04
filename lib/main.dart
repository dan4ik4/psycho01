import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/api/api_client.dart';
import 'core/auth/token_storage.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/mood/data/mood_repository.dart';
import 'screens/auth_screen.dart';
import 'screens/main_navigation_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
final Completer<void> initialDeepLinkResolved = Completer<void>();
String? pendingResetToken;
bool appBootstrapFinished = false;

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
  await dotenv.load(fileName: ".env.example");
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const MethodChannel _deepLinkChannel = MethodChannel(
    'soulbuddy/deep_links',
  );

  @override
  void initState() {
    super.initState();
    _deepLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLink' && call.arguments is String) {
        _handleIncomingLink(Uri.tryParse(call.arguments as String));
      }
    });
    _deepLinkChannel
        .invokeMethod<String>('getInitialLink')
        .then((link) {
          if (link != null) _handleIncomingLink(Uri.tryParse(link));
        })
        .catchError((_) {})
        .whenComplete(() {
          if (!initialDeepLinkResolved.isCompleted) {
            initialDeepLinkResolved.complete();
          }
        });
  }

  void _handleIncomingLink(Uri? uri) {
    if (uri == null) return;
    if (uri.host != 'reset-password' && uri.path != '/reset-password') return;
    final token =
        uri.queryParameters['token'] ?? uri.queryParameters['access_token'];
    if (token == null || token.isEmpty) return;
    if (!appBootstrapFinished) {
      pendingResetToken = token;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(token: token)),
      );
    });
  }

  @override
  void dispose() {
    _deepLinkChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Oakle',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU'), Locale('en', 'US')],
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
    await initialDeepLinkResolved.future;
    if (!mounted) return;
    if (pendingResetToken != null) {
      final token = pendingResetToken!;
      pendingResetToken = null;
      appBootstrapFinished = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(token: token)),
      );
      return;
    }
    final hasToken = await tokenStorage.hasToken();
    if (!hasToken) {
      if (mounted) {
        appBootstrapFinished = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
      return;
    }

    try {
      final response = await apiClient.dio.get('/users/me');
      final role = response.data['is_psychologist'] == true
          ? 'specialist'
          : 'client';
      if (mounted) {
        appBootstrapFinished = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                MainNavigationScreen(forcedRole: role, apiClient: apiClient),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        appBootstrapFinished = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1E1C2A),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF7862D6))),
    );
  }
}

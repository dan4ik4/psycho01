import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:god_save_this_shit_app/core/api/api_client.dart';
import 'package:god_save_this_shit_app/core/auth/token_storage.dart';
import 'package:god_save_this_shit_app/screens/home_screen.dart';

class _EmptyListDio implements Dio {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) => Future.value(
    Response<T>(
      requestOptions: RequestOptions(path: path),
      data: <dynamic>[] as T,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('updates greeting when profile name arrives after first build', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final apiClient = ApiClient(
      tokenStorage: TokenStorage(),
      dioOverride: _EmptyListDio(),
    );

    Widget buildHome(String name) => MaterialApp(
      home: HomeScreen(
        onOpenProfile: () {},
        apiClient: apiClient,
        displayName: name,
      ),
    );

    await tester.pumpWidget(buildHome('Пользователь'));
    await tester.pump();
    expect(find.text('Здравствуйте, Пользователь'), findsOneWidget);

    await tester.pumpWidget(buildHome('Анна Иванова'));
    await tester.pump();
    expect(find.text('Здравствуйте, Анна Иванова'), findsOneWidget);
  });
}
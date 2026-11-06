import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notebyme/backend.dart';
import 'package:notebyme/database.dart';
import 'package:notebyme/ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android opens local storage and submits username/PIN login', (
    tester,
  ) async {
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    final directory = await Directory.systemTemp.createTemp('notes-login-');
    NotesDatabase? database;
    var loginCalls = 0;
    final backend = Backend(
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/login'));
        expect(request.method, 'POST');
        expect(request.headers['Origin'], nativeOrigin);
        expect(jsonDecode(request.body), {
          'username': 'mobile-test',
          'password': '0042',
        });
        loginCalls++;
        return http.Response(
          jsonEncode({
            'user': {'id': 'mobile-user'},
            'session': 'test-session',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    try {
      // Use the actual Android plugin and app startup configuration, not FFI.
      database = await NotesDatabase.open(
        filename: '${directory.path}/notes.sqlite',
      );
      expect(
        (await database.db.rawQuery(
          'PRAGMA busy_timeout',
        )).single.values.single,
        5000,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            submit: (username, pin, register) async {
              final session = await backend.login(username, pin);
              expect(session.userId, 'mobile-user');
              expect(session.token, 'test-session');
            },
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('username')), 'mobile-test');
      await tester.enterText(find.byKey(const Key('pin')), '0042');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng nhập'));
      await tester.pumpAndSettle();
      expect(loginCalls, 1);
      expect(find.byKey(const Key('login-message')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      backend.close();
      await database?.close();
      // Only the fresh test directory is disposable; never touch user notes.
      await directory.delete(recursive: true);
    }
  });
}

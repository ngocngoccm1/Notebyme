import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebyme/notes_controller.dart';
import 'package:notebyme/ui.dart';
import 'support.dart';

void main() {
  testWidgets('native login accepts a four-digit PIN starting with zero', (
    tester,
  ) async {
    String? entered;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          submit: (name, pin, register) async {
            entered = '$name:$pin:$register';
          },
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('username')), 'ngoc');
    await tester.enterText(find.byKey(const Key('pin')), '0042');
    await tester.tap(find.text('Tạo tài khoản'));
    await tester.pump();
    expect(entered, 'ngoc:0042:true');
    expect(find.text('Email'), findsNothing);
  });
  testWidgets('a five-thousand-note list builds only visible rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryRepository();
    for (var i = 0; i < 5000; i++) {
      repository.forUser('a')['n-$i'] = sample('n-$i');
    }
    final controller = NotesController(
      userId: 'a',
      repository: repository,
      backend: FakeBackend(),
      onExpired: () {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NotesWorkspace(controller: controller, logout: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.items.value.length, 5000);
    expect(find.byType(InkWell).evaluate().length, lessThan(35));
    expect(find.byKey(const ValueKey('row-n-4999')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
  });
  testWidgets(
    'typing does not rebuild the note list or write SQLite on every key',
    (tester) async {
      final repository = MemoryRepository();
      repository.forUser('a')['n'] = sample('n');
      final controller = NotesController(
        userId: 'a',
        repository: repository,
        backend: FakeBackend(),
        onExpired: () {},
        syncDelay: const Duration(hours: 1),
      );
      var listUpdates = 0;
      controller.items.addListener(() => listUpdates++);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteEditor(id: 'n', controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initial = listUpdates;
      for (var i = 0; i < 50; i++) {
        await tester.enterText(find.byKey(const Key('note-body')), 'text-$i');
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(repository.saves, 0);
      expect(listUpdates, initial);
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pump();
      expect(repository.saves, 1);
      expect((await repository.get('a', 'n'))!.body, 'text-49');
      await tester.pumpWidget(const SizedBox());
      await controller.close();
    },
  );
}

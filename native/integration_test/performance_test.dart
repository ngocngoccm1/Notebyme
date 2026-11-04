import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:notebyme/database.dart';
import 'package:notebyme/notes_controller.dart';
import 'package:notebyme/ui.dart';
import '../test/support.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile 5000 notes and a long document', (tester) async {
    final directory = await Directory.systemTemp.createTemp(
      'notes-performance-',
    );
    final database = await NotesDatabase.open(
      filename: '${directory.path}/benchmark.sqlite',
    );
    final controller = NotesController(
      userId: 'performance-test',
      repository: database,
      backend: FakeBackend(),
      onExpired: () {},
      syncDelay: const Duration(hours: 1),
    );
    try {
      await database.merge(
        'performance-test',
        List.generate(
          5000,
          (i) => sample(
            'n-$i',
            body: 'Ghi chú thử hiệu năng, không có dữ liệu cá nhân.',
          ),
        ),
      );
      await database.merge('performance-test', [
        sample(
          'large',
          body: List.filled(1000, 'Một dòng trong ghi chú dài.').join('\n'),
        ),
      ]);
      await controller.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: NotesWorkspace(controller: controller, logout: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.fling(
        find.byKey(const Key('notes-list')),
        const Offset(0, -400),
        1000,
      );
      await tester.pumpAndSettle();
      await binding.traceAction(() async {
        for (var i = 0; i < 20; i++) {
          await tester.fling(
            find.byKey(const Key('notes-list')),
            const Offset(0, -600),
            1000,
          );
          await tester.pumpAndSettle();
        }
      }, reportKey: 'scrolling_timeline');
      controller.selected.value = 'large';
      await tester.pumpAndSettle();
      final initial = (await database.get('performance-test', 'large'))!.body;
      await binding.traceAction(() async {
        for (var i = 0; i < 50; i++) {
          await tester.enterText(
            find.byKey(const Key('note-body')),
            '$initial\nNhập nhanh $i',
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await controller.flush();
        await tester.pump();
      }, reportKey: 'typing_timeline');
      expect(
        (await database.get('performance-test', 'large'))!.body,
        endsWith('Nhập nhanh 49'),
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await controller.close();
      await database.close();
      // This is a fresh, test-only directory. Never delete the app data folder.
      if (directory.absolute.path.startsWith(
        Directory.systemTemp.absolute.path,
      )) {
        await directory.delete(recursive: true);
      }
    }
  });
}

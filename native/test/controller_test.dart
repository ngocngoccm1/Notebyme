import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:notebyme/notes_controller.dart';
import 'package:notebyme/models.dart';
import 'support.dart';

void main() {
  test(
    'one hundred rapid edits produce one local write, without waiting for network',
    () async {
      final repository = MemoryRepository(), backend = FakeBackend();
      final controller = NotesController(
        userId: 'a',
        repository: repository,
        backend: backend,
        onExpired: () {},
      );
      var note = sample('n');
      for (var i = 0; i < 100; i++) {
        note = note.edit(body: 'edit-$i');
        controller.stage(note);
      }
      expect(repository.saves, 0);
      expect(await controller.flush(), true);
      expect(repository.saves, 1);
      expect((await repository.get('a', 'n'))!.body, 'edit-99');
      await controller.close();
    },
  );
  test(
    'edits during upload are not acknowledged as an older revision',
    () async {
      final repository = MemoryRepository(), backend = FakeBackend();
      final before = sample('n', body: 'before', dirty: true, revision: 1);
      repository.forUser('a')['n'] = before;
      final entered = Completer<void>(), uploaded = Completer<void>();
      backend.onSave = (_) async {
        entered.complete();
        await uploaded.future;
      };
      final controller = NotesController(
        userId: 'a',
        repository: repository,
        backend: backend,
        onExpired: () {},
      );
      final syncing = controller.sync();
      await entered.future;
      controller.stage(before.edit(body: 'during upload'));
      await controller.flush();
      uploaded.complete();
      await syncing;
      final current = await repository.get('a', 'n');
      expect(current!.body, 'during upload');
      expect(current.dirty, true);
      await controller.close();
    },
  );
  test(
    'closing an account prevents a late response from merging into the database',
    () async {
      final repository = MemoryRepository(), backend = FakeBackend();
      final entered = Completer<void>(), response = Completer<List<Note>>();
      backend.onLoad = () async {
        entered.complete();
        return response.future;
      };
      final controller = NotesController(
        userId: 'a',
        repository: repository,
        backend: backend,
        onExpired: () {},
      );
      final syncing = controller.sync();
      await entered.future;
      await controller.close();
      response.complete([sample('private-a')]);
      await syncing;
      expect(repository.merges, 0);
      expect(await repository.get('b', 'private-a'), null);
      expect(backend.closed, true);
    },
  );
  test(
    'a failed local write is retained for retry and never reported as saved',
    () async {
      final repository = MemoryRepository()..failWrites = true;
      final controller = NotesController(
        userId: 'a',
        repository: repository,
        backend: FakeBackend(),
        onExpired: () {},
      );
      controller.stage(sample('n').edit(body: 'keep this'));
      expect(await controller.flush(), false);
      expect(controller.status.value, contains('Chưa lưu'));
      repository.failWrites = false;
      expect(await controller.flush(), true);
      expect((await repository.get('a', 'n'))!.body, 'keep this');
      await controller.close();
    },
  );
}

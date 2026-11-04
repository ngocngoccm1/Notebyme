import 'package:flutter_test/flutter_test.dart';
import 'package:notebyme/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'support.dart';

void main() {
  late NotesDatabase database;
  setUp(() async {
    sqfliteFfiInit();
    database = await NotesDatabase.open(
      filename: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() => database.close());
  test(
    'SQLite isolates accounts even when note identifiers are identical',
    () async {
      await database.saveLocal('a', [sample('same').edit(body: 'account a')]);
      await database.saveLocal('b', [sample('same').edit(body: 'account b')]);
      expect((await database.get('a', 'same'))!.body, 'account a');
      await database.clear('a');
      expect((await database.get('b', 'same'))!.body, 'account b');
    },
  );
  test(
    'SQLite does not clear newer dirty changes or overwrite them during merge',
    () async {
      final first = sample('n').edit(body: 'first'),
          second = sample('n').edit(body: 'first').edit(body: 'second');
      await database.saveLocal('a', [first]);
      await database.saveLocal('a', [second]);
      await database.acknowledge('a', [first]);
      await database.merge('a', [clean(first)]);
      final current = (await database.get('a', 'n'))!;
      expect(current.body, 'second');
      expect(current.dirty, true);
    },
  );
  test('large note list loads previews without full document bodies', () async {
    final notes = List.generate(
      5000,
      (i) => sample(
        'n-$i',
        body: List.filled(20, 'A long document paragraph.').join('\n'),
      ),
    );
    await database.merge('a', notes);
    final summary = await database.list('a', '');
    expect(summary.length, 5000);
    expect(summary.every((n) => n.preview.length <= 100), true);
    expect((await database.get('a', 'n-4999'))!.body.length, greaterThan(100));
  });
}

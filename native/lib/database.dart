import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'models.dart';

abstract interface class NoteRepository {
  Future<List<NoteSummary>> list(String userId, String query);
  Future<Note?> get(String userId, String id);
  Future<void> saveLocal(String userId, List<Note> notes);
  Future<List<Note>> dirty(String userId);
  Future<void> acknowledge(String userId, List<Note> notes);
  Future<void> merge(String userId, List<Note> notes);
  Future<bool> hasDirty(String userId);
  Future<void> clear(String userId);
}

class NotesDatabase implements NoteRepository {
  NotesDatabase(this.db);
  final Database db;

  static Future<NotesDatabase> open({
    String? filename,
    DatabaseFactory? factory,
  }) async {
    if (factory == null) {
      if (Platform.isWindows || Platform.isLinux) {
        sqfliteFfiInit();
        factory = databaseFactoryFfi;
      } else {
        factory = mobile.databaseFactory;
      }
    }
    if (filename == null) {
      final directory = await getApplicationSupportDirectory();
      await directory.create(recursive: true);
      filename = path.join(directory.path, 'notes.sqlite');
    }
    final db = await factory.openDatabase(
      filename,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode = WAL');
          // Android execSQL rejects PRAGMAs that return a result row.
          await db.rawQuery('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE notes (user_id TEXT NOT NULL,id TEXT NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,updated_at TEXT NOT NULL,deleted INTEGER NOT NULL,dirty INTEGER NOT NULL,revision INTEGER NOT NULL,PRIMARY KEY(user_id,id))',
          );
          await db.execute(
            'CREATE INDEX notes_list ON notes(user_id,deleted,updated_at DESC)',
          );
        },
      ),
    );
    return NotesDatabase(db);
  }

  @override
  Future<List<NoteSummary>> list(String userId, String query) async {
    final rows = await db.rawQuery(
      'SELECT id,title,substr(body,1,100) AS preview,updated_at,dirty FROM notes WHERE user_id=? AND deleted=0 ${query.isEmpty ? '' : 'AND (instr(lower(title),?)>0 OR instr(lower(body),?)>0)'} ORDER BY updated_at DESC,id',
      [
        userId,
        if (query.isNotEmpty) ...[query.toLowerCase(), query.toLowerCase()],
      ],
    );
    return rows.map(NoteSummary.fromRow).toList();
  }

  @override
  Future<Note?> get(String userId, String id) async {
    final rows = await db.query(
      'notes',
      where: 'user_id=? AND id=?',
      whereArgs: [userId, id],
      limit: 1,
    );
    return rows.isEmpty ? null : Note.fromRow(rows.single);
  }

  @override
  Future<void> saveLocal(String userId, List<Note> notes) async {
    await db.transaction((transaction) async {
      final batch = transaction.batch();
      for (final note in notes) {
        batch.rawInsert(
          'INSERT INTO notes(user_id,id,title,body,updated_at,deleted,dirty,revision) VALUES(?,?,?,?,?,?,1,?) ON CONFLICT(user_id,id) DO UPDATE SET title=excluded.title,body=excluded.body,updated_at=excluded.updated_at,deleted=excluded.deleted,dirty=1,revision=excluded.revision WHERE excluded.revision>=notes.revision',
          [
            userId,
            note.id,
            note.title,
            note.body,
            note.updatedAt,
            note.deleted ? 1 : 0,
            note.revision,
          ],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<Note>> dirty(String userId) async => (await db.query(
    'notes',
    where: 'user_id=? AND dirty=1',
    whereArgs: [userId],
  )).map(Note.fromRow).toList();
  @override
  Future<void> acknowledge(String userId, List<Note> notes) async {
    final batch = db.batch();
    for (final note in notes) {
      batch.rawUpdate(
        'UPDATE notes SET dirty=0 WHERE user_id=? AND id=? AND revision=?',
        [userId, note.id, note.revision],
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> merge(String userId, List<Note> notes) async {
    await db.transaction((transaction) async {
      final batch = transaction.batch();
      for (final note in notes) {
        batch.rawInsert(
          'INSERT INTO notes(user_id,id,title,body,updated_at,deleted,dirty,revision) VALUES(?,?,?,?,?,?,0,0) ON CONFLICT(user_id,id) DO UPDATE SET title=excluded.title,body=excluded.body,updated_at=excluded.updated_at,deleted=excluded.deleted WHERE notes.dirty=0',
          [
            userId,
            note.id,
            note.title,
            note.body,
            note.updatedAt,
            note.deleted ? 1 : 0,
          ],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<bool> hasDirty(String userId) async => (await db.rawQuery(
    'SELECT 1 FROM notes WHERE user_id=? AND dirty=1 LIMIT 1',
    [userId],
  )).isNotEmpty;
  @override
  Future<void> clear(String userId) =>
      db.delete('notes', where: 'user_id=?', whereArgs: [userId]).then((_) {});
  Future<void> close() => db.close();
}

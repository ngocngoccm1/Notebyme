import 'package:notebyme/backend.dart';
import 'package:notebyme/database.dart';
import 'package:notebyme/models.dart';

Note clean(Note n) => Note(
  id: n.id,
  title: n.title,
  body: n.body,
  updatedAt: n.updatedAt,
  deleted: n.deleted,
  revision: n.revision,
);
Note sample(
  String id, {
  String body = 'body',
  bool dirty = false,
  int revision = 0,
}) => Note(
  id: id,
  title: id,
  body: body,
  updatedAt: '2026-11-04T00:00:00.000Z',
  dirty: dirty,
  revision: revision,
);

class MemoryRepository implements NoteRepository {
  final rows = <String, Map<String, Note>>{};
  int saves = 0, merges = 0;
  bool failWrites = false;
  Map<String, Note> forUser(String id) => rows.putIfAbsent(id, () => {});
  @override
  Future<List<NoteSummary>> list(String userId, String query) async =>
      forUser(userId).values
          .where((n) => !n.deleted && '${n.title} ${n.body}'.contains(query))
          .map(
            (n) => NoteSummary(
              id: n.id,
              title: n.title,
              preview: n.body.substring(0, n.body.length.clamp(0, 100)),
              updatedAt: n.updatedAt,
              dirty: n.dirty,
            ),
          )
          .toList();
  @override
  Future<Note?> get(String userId, String id) async => forUser(userId)[id];
  @override
  Future<void> saveLocal(String userId, List<Note> notes) async {
    if (failWrites) throw Exception('disk full');
    saves++;
    for (final n in notes) {
      if ((forUser(userId)[n.id]?.revision ?? -1) <= n.revision) {
        forUser(userId)[n.id] = n;
      }
    }
  }

  @override
  Future<List<Note>> dirty(String userId) async =>
      forUser(userId).values.where((n) => n.dirty).toList();
  @override
  Future<void> acknowledge(String userId, List<Note> notes) async {
    for (final note in notes) {
      final current = forUser(userId)[note.id];
      if (current?.revision == note.revision) {
        forUser(userId)[note.id] = clean(current!);
      }
    }
  }

  @override
  Future<void> merge(String userId, List<Note> notes) async {
    merges++;
    for (final note in notes) {
      if (forUser(userId)[note.id]?.dirty != true) {
        forUser(userId)[note.id] = clean(note);
      }
    }
  }

  @override
  Future<bool> hasDirty(String userId) async =>
      forUser(userId).values.any((n) => n.dirty);
  @override
  Future<void> clear(String userId) async {
    rows.remove(userId);
  }
}

class FakeBackend implements NotesBackend {
  List<Note> remote = [];
  Future<void> Function(List<Note>)? onSave;
  Future<List<Note>> Function()? onLoad;
  bool closed = false;
  @override
  Future<List<Note>> loadNotes() async =>
      onLoad == null ? remote : await onLoad!();
  @override
  Future<void> saveNotes(List<Note> notes) async {
    remote = notes.map(clean).toList();
    await onSave?.call(notes);
  }

  @override
  Future<void> logout() async {}
  @override
  void close() {
    closed = true;
  }
}

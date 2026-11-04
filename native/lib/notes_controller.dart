import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'backend.dart';
import 'database.dart';
import 'models.dart';

class NotesController {
  NotesController({
    required this.userId,
    required this.repository,
    required this.backend,
    required this.onExpired,
    this.saveDelay = const Duration(milliseconds: 300),
    this.syncDelay = const Duration(milliseconds: 1500),
  }) {
    unawaited(refresh());
  }
  final String userId;
  final NoteRepository repository;
  final NotesBackend backend;
  final VoidCallback onExpired;
  final Duration saveDelay, syncDelay;
  final items = ValueNotifier<List<NoteSummary>>([]);
  final status = ValueNotifier<String>('Đang tải ghi chú trên máy...');
  final selected = ValueNotifier<String?>(null);
  final _pending = <String, Note>{};
  Timer? _saveTimer, _syncTimer, _searchTimer, _periodic;
  Future<void> _writes = Future.value();
  Future<void>? _syncing;
  bool _closed = false;
  int _queryGeneration = 0;
  String _query = '';

  Future<void> refresh() async {
    final generation = ++_queryGeneration;
    try {
      final result = await repository.list(userId, _query);
      if (!_closed && generation == _queryGeneration) items.value = result;
    } catch (_) {
      if (!_closed) {
        status.value = 'Chưa đọc được dữ liệu trên máy. Thử mở lại app.';
      }
    }
  }

  void search(String text) {
    _query = text.trim();
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 180), refresh);
  }

  Future<Note?> get(String id) async =>
      _pending[id] ?? await repository.get(userId, id);
  Future<String> create() async {
    final note = Note(
      id: const Uuid().v4(),
      title: '',
      body: '',
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      dirty: true,
      revision: 1,
    );
    stage(note);
    await flush();
    if (!_closed) selected.value = note.id;
    return note.id;
  }

  void stage(Note note) {
    if (_closed) return;
    _pending[note.id] = note;
    // Only this small status notifier changes while typing. The editor and
    // complete note list are never rebuilt on every character.
    status.value = 'Đang lưu...';
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, flush);
    _syncTimer?.cancel();
    _syncTimer = Timer(syncDelay, sync);
  }

  Future<bool> flush() {
    _saveTimer?.cancel();
    final snapshot = Map<String, Note>.from(_pending);
    _pending.clear();
    final work = _writes.then((_) async {
      if (snapshot.isEmpty) return true;
      try {
        await repository.saveLocal(userId, snapshot.values.toList());
        if (!_closed) {
          status.value = _pending.isEmpty ? 'Đã lưu trên máy' : 'Đang lưu...';
          unawaited(refresh());
        }
        return true;
      } catch (_) {
        for (final note in snapshot.values) {
          if ((_pending[note.id]?.revision ?? -1) < note.revision) {
            _pending[note.id] = note;
          }
        }
        if (!_closed) {
          status.value = 'Chưa lưu được trên máy. Giữ app mở và thử lại.';
        }
        return false;
      }
    });
    _writes = work.then<void>((_) {});
    return work;
  }

  Future<void> remove(String id) async {
    final note = await get(id);
    if (note == null || _closed) return;
    stage(note.edit(deleted: true));
    selected.value = null;
    await flush();
  }

  Future<bool> hasDirty() async =>
      _pending.isNotEmpty || await repository.hasDirty(userId);

  Future<void> sync() {
    if (_closed) return Future.value();
    // One request sequence per account. A delayed old response cannot merge
    // into the next account because controllers and database scopes are distinct.
    return _syncing ??= _runSync().whenComplete(() => _syncing = null);
  }

  Future<void> _runSync() async {
    if (!await flush() || _closed) return;
    status.value = 'Đang đồng bộ...';
    try {
      final pending = await repository.dirty(userId);
      for (var offset = 0; offset < pending.length; offset += 4) {
        final end = offset + 4 < pending.length ? offset + 4 : pending.length;
        final batch = pending.sublist(offset, end);
        await backend.saveNotes(batch);
        if (_closed) return;
        await repository.acknowledge(userId, batch);
      }
      final remote = await backend.loadNotes();
      if (_closed) return;
      // Persist edits made during download before merging. SQLite preserves all
      // dirty rows, and acknowledgements compare the sent local revision.
      if (!await flush() || _closed) return;
      await repository.merge(userId, remote);
      if (_closed) return;
      await refresh();
      status.value = await hasDirty()
          ? 'Đã lưu trên máy · Còn thay đổi chưa đồng bộ'
          : 'Đã đồng bộ';
    } on BackendError catch (error) {
      if (_closed) return;
      if (error.status == 401) {
        onExpired();
        return;
      }
      status.value = error.message;
    } catch (_) {
      if (!_closed) status.value = 'Chưa đồng bộ. Bản nháp vẫn ở trên máy.';
    }
  }

  void resume() {
    if (_closed) return;
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 2), (_) => sync());
    unawaited(sync());
  }

  void pause() {
    _periodic?.cancel();
    unawaited(flush());
  }

  Future<void> close() async {
    _closed = true;
    _saveTimer?.cancel();
    _syncTimer?.cancel();
    _searchTimer?.cancel();
    _periodic?.cancel();
    backend.close();
    await flush();
    items.dispose();
    status.dispose();
    selected.dispose();
  }
}

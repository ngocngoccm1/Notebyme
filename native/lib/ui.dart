import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'backend.dart';
import 'models.dart';
import 'notes_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.submit, this.message = ''});
  final Future<void> Function(String username, String pin, bool register)
  submit;
  final String message;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController(), _pin = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String _error = '';
  Future<void> _submit(bool register) async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.submit(_username.text, _pin.text, register);
      if (mounted) _pin.clear();
    } on BackendError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Chưa đăng nhập được. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 370),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Notes.',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ghi nhanh. Lưu trên máy. Đồng bộ khi có mạng.',
                      style: TextStyle(color: Color(0xff60675f), height: 1.5),
                    ),
                    const SizedBox(height: 36),
                    TextFormField(
                      key: const Key('username'),
                      controller: _username,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      maxLength: 32,
                      decoration: const InputDecoration(
                        labelText: 'Tên đăng nhập',
                        counterText: '',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Nhập tên đăng nhập'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('pin'),
                      controller: _pin,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Mật khẩu 4 chữ số',
                      ),
                      onFieldSubmitted: (_) => _submit(false),
                      validator: (value) =>
                          value == null ||
                              !RegExp(r'^[0-9]{4}$').hasMatch(value)
                          ? 'Nhập đúng 4 chữ số'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : () => _submit(false),
                      child: Text(_busy ? 'Đang kết nối...' : 'Đăng nhập'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _busy ? null : () => _submit(true),
                      child: const Text('Tạo tài khoản'),
                    ),
                    if (_error.isNotEmpty || widget.message.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        _error.isNotEmpty ? _error : widget.message,
                        key: const Key('login-message'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class NotesWorkspace extends StatelessWidget {
  const NotesWorkspace({
    super.key,
    required this.controller,
    required this.logout,
  });
  final NotesController controller;
  final Future<void> Function() logout;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Notes.',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: 'Ghi chú mới',
          onPressed: controller.create,
          icon: const Icon(Icons.add),
        ),
        IconButton(
          tooltip: 'Đồng bộ',
          onPressed: controller.sync,
          icon: const Icon(Icons.sync_outlined),
        ),
        IconButton(
          tooltip: 'Đăng xuất',
          onPressed: logout,
          icon: const Icon(Icons.logout_outlined),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(30),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ValueListenableBuilder<String>(
              valueListenable: controller.status,
              builder: (_, message, _) => Tooltip(
                message: message,
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xff60675f),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 820;
          return ValueListenableBuilder<String?>(
            valueListenable: controller.selected,
            builder: (context, id, _) {
              final editor = id == null
                  ? const _EmptyEditor()
                  : NoteEditor(
                      key: ValueKey(id),
                      id: id,
                      controller: controller,
                      showBack: !wide,
                    );
              if (wide) {
                return Row(
                  children: [
                    SizedBox(
                      width: 310,
                      child: NotesList(controller: controller),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: editor),
                  ],
                );
              }
              if (id == null) return NotesList(controller: controller);
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) controller.selected.value = null;
                },
                child: editor,
              );
            },
          );
        },
      ),
    ),
  );
}

class NotesList extends StatefulWidget {
  const NotesList({super.key, required this.controller});
  final NotesController controller;
  @override
  State<NotesList> createState() => _NotesListState();
}

class _NotesListState extends State<NotesList> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          key: const Key('search-notes'),
          controller: _search,
          onChanged: widget.controller.search,
          decoration: const InputDecoration(
            hintText: 'Tìm ghi chú...',
            prefixIcon: Icon(Icons.search, size: 20),
          ),
        ),
      ),
      Expanded(
        child: ValueListenableBuilder<List<NoteSummary>>(
          valueListenable: widget.controller.items,
          builder: (context, notes, _) {
            if (notes.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Chưa có ghi chú phù hợp.',
                    style: TextStyle(color: Color(0xff60675f)),
                  ),
                ),
              );
            }
            return ListView.builder(
              key: const Key('notes-list'),
              itemExtent: 94,
              itemCount: notes.length,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemBuilder: (context, index) {
                final note = notes[index];
                final date = DateTime.tryParse(note.updatedAt)?.toLocal();
                final time = date == null
                    ? ''
                    : '${date.day}/${date.month} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                return InkWell(
                  key: ValueKey('row-${note.id}'),
                  onTap: () => widget.controller.selected.value = note.id,
                  child: Container(
                    color: widget.controller.selected.value == note.id
                        ? const Color(0xffe7eee5)
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.title.trim().isEmpty
                              ? 'Không có tiêu đề'
                              : note.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          note.preview.replaceAll('\n', ' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xff60675f),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$time${note.dirty ? ' · Chưa đồng bộ' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xff6b7469),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note_outlined, size: 42, color: Color(0xff697d66)),
        SizedBox(height: 14),
        Text(
          'Chọn một ghi chú hoặc tạo mới.',
          style: TextStyle(color: Color(0xff60675f)),
        ),
      ],
    ),
  );
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.id,
    required this.controller,
    this.showBack = false,
  });
  final String id;
  final NotesController controller;
  final bool showBack;
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final _title = TextEditingController(), _body = TextEditingController();
  final _titleFocus = FocusNode();
  Note? _note;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final note = await widget.controller.get(widget.id);
      if (!mounted) return;
      if (note == null) {
        setState(() => _failed = true);
        return;
      }
      _title.text = note.title;
      _body.text = note.body;
      setState(() => _note = note);
      if (note.title.isEmpty && note.body.isEmpty) _titleFocus.requestFocus();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _changed(String _) {
    final note = _note;
    if (note == null) return;
    _note = note.edit(title: _title.text, body: _body.text);
    widget.controller.stage(_note!);
    // Text controllers repaint their own field. No setState / list refresh here.
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa ghi chú?'),
        content: const Text(
          'Ghi chú này sẽ được xóa trên các thiết bị sau khi đồng bộ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.remove(widget.id);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Text('Chưa mở được ghi chú. Vui lòng chọn lại.'),
      );
    }
    if (_note == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              if (widget.showBack)
                TextButton.icon(
                  onPressed: () => widget.controller.selected.value = null,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Danh sách'),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Xóa ghi chú',
                onPressed: _remove,
                icon: const Icon(Icons.delete_outline, size: 21),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: TextField(
            key: const Key('note-title'),
            controller: _title,
            focusNode: _titleFocus,
            onChanged: _changed,
            maxLength: 500,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              hintText: 'Tiêu đề',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              counterText: '',
              contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
            child: TextField(
              key: const Key('note-body'),
              controller: _body,
              onChanged: _changed,
              expands: true,
              minLines: null,
              maxLines: null,
              maxLength: 100000,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: const TextStyle(fontSize: 16, height: 1.65),
              decoration: const InputDecoration(
                hintText: 'Bắt đầu viết...',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

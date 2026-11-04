import 'dart:async';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'backend.dart';
import 'database.dart';
import 'models.dart';
import 'notes_controller.dart';
import 'session_store.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesApp());
}

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});
  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  final _sessions = SecureSessionStore();
  NotesDatabase? _database;
  NotesController? _notes;
  late final AppLifecycleListener _lifecycle;
  bool _opening = true, _switching = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          _notes?.resume();
        } else {
          _notes?.pause();
        }
      },
      onExitRequested: () async {
        if (_notes != null && !await _notes!.flush()) {
          return AppExitResponse.cancel;
        }
        return AppExitResponse.exit;
      },
    );
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      _database = await NotesDatabase.open();
      Session? session;
      try {
        session = await _sessions.read();
      } catch (_) {
        _message = 'Không đọc được phiên cũ. Vui lòng đăng nhập lại.';
      }
      if (!mounted) return;
      if (session != null) _activate(session);
      setState(() => _opening = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _opening = false;
          _message =
              'Chưa mở được dữ liệu trên máy. Kiểm tra dung lượng và thử mở lại app.';
        });
      }
    }
  }

  void _activate(Session session) {
    late final NotesController notes;
    notes = NotesController(
      userId: session.userId,
      repository: _database!,
      backend: Backend(token: session.token),
      onExpired: () => _expired(notes),
    );
    _notes = notes;
    notes.resume();
  }

  Future<void> _login(String username, String pin, bool register) async {
    if (_database == null) {
      throw const BackendError('LOCAL_STORAGE_UNAVAILABLE');
    }
    final client = Backend();
    try {
      final session = await client.login(username, pin, register: register);
      try {
        await _sessions.write(session);
      } catch (_) {
        /* Current in-memory session remains usable. */
      }
      if (!mounted) return;
      setState(() {
        _message = '';
        _activate(session);
      });
    } finally {
      client.close();
    }
  }

  Future<void> _expired(NotesController notes) async {
    if (_switching || _notes != notes || !mounted) return;
    _switching = true;
    setState(() {
      _notes = null;
      _opening = true;
      _message = 'Phiên đã hết hạn. Đăng nhập lại để đồng bộ bản nháp.';
    });
    try {
      await _sessions.clear();
    } catch (_) {
      /* Never block re-authentication on Keychain failure. */
    }
    await notes.close();
    if (mounted) {
      setState(() {
        _opening = false;
        _switching = false;
      });
    }
  }

  Future<void> _logout() async {
    final notes = _notes;
    if (notes == null || _switching || !await notes.flush() || !mounted) return;
    if (await notes.hasDirty()) {
      if (!mounted) return;
      final discard = await showDialog<bool>(
        context: _navigatorKey.currentState!.overlay!.context,
        builder: (context) => AlertDialog(
          title: const Text('Còn thay đổi chưa đồng bộ'),
          content: const Text(
            'Đăng xuất sẽ xóa bản ghi chú trên máy này. Bạn vẫn muốn đăng xuất?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Giữ lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Đăng xuất'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    _switching = true;
    notes.pause();
    setState(() => _opening = true);
    try {
      if (!await notes.flush()) {
        throw const BackendError('LOCAL_STORAGE_UNAVAILABLE');
      }
      try {
        await notes.backend.logout();
      } on BackendError catch (error) {
        if (error.status != 401) rethrow;
      }
      try {
        await _sessions.clear();
      } catch (_) {
        /* The server session is already revoked. */
      }
      if (!mounted) return;
      setState(() {
        _notes = null;
        _message = 'Đã đăng xuất.';
      });
      await notes.close();
      await notes.repository.clear(notes.userId);
    } on BackendError catch (error) {
      if (_notes == notes) notes.status.value = error.message;
    } catch (_) {
      if (_notes == notes) {
        notes.status.value = 'Chưa đăng xuất được. Vui lòng thử lại.';
      } else {
        _message = 'Đã đăng xuất. Chưa xóa được bản lưu trên máy.';
      }
    } finally {
      _switching = false;
      if (mounted) setState(() => _opening = false);
      if (_notes == notes) notes.resume();
    }
  }

  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_notes?.close() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigatorKey,
    debugShowCheckedModeBanner: false,
    title: 'Notes',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff7f7f5),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff355e48),
        surface: const Color(0xfff7f7f5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff7f7f5),
        surfaceTintColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xffd5dbd0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xffd5dbd0)),
        ),
      ),
    ),
    home: _opening
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _notes != null
        ? NotesWorkspace(controller: _notes!, logout: _logout)
        : LoginScreen(submit: _login, message: _message),
  );
}

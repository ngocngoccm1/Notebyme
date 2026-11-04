import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

abstract interface class SessionStore {
  Future<Session?> read();
  Future<void> write(Session session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'notebyme-native-session-v1';
  // The standalone Mac build uses its app's own legacy Keychain item. This
  // avoids a Keychain Sharing entitlement that needs paid provisioning.
  final _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  @override
  Future<Session?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null
        ? null
        : Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> write(Session session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

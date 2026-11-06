import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

const backendUrl =
    'https://clyshqnbxapwipacbaxd.supabase.co/functions/v1/notebyme-api';
const nativeOrigin = 'notebyme://native';
String encodeJson(Object value) => jsonEncode(value);
dynamic decodeJson(String value) => jsonDecode(value);
List<Note> decodeNotes(String value) =>
    ((jsonDecode(value) as Map<String, dynamic>)['notes'] as List)
        .map((row) => Note.fromRow(Map<String, Object?>.from(row as Map)))
        .toList();

class BackendError implements Exception {
  const BackendError(this.code, {this.status = 0, this.requestId = ''});
  final String code, requestId;
  final int status;
  String get message {
    const messages = {
      'NETWORK_ERROR': 'Không kết nối được máy chủ. Bản nháp vẫn ở trên máy.',
      'NETWORK_DNS':
          'App chưa phân giải được địa chỉ máy chủ. Thử đổi Wi-Fi/4G hoặc kiểm tra DNS riêng trên điện thoại.',
      'NETWORK_TLS':
          'App chưa xác thực được kết nối HTTPS. Kiểm tra ngày giờ tự động trên điện thoại.',
      'NETWORK_TIMEOUT': 'Máy chủ phản hồi quá lâu. Vui lòng thử kết nối lại.',
      'NETWORK_SOCKET':
          'Điện thoại chưa mở được kết nối mạng cho app. Kiểm tra quyền dùng Wi-Fi/dữ liệu di động của Notes.',
      'NETWORK_HTTP':
          'Kết nối bị ngắt trước khi app nhận đủ phản hồi. Thử lại.',
      'LOGIN_FAILED': 'Tên đăng nhập hoặc mật khẩu không đúng.',
      'INVALID_USERNAME':
          'Tên đăng nhập gồm 1–32 chữ, số, dấu chấm, gạch dưới hoặc gạch ngang.',
      'INVALID_PIN': 'Mật khẩu cần đúng 4 chữ số.',
      'USERNAME_TAKEN': 'Tên đăng nhập đã có người sử dụng.',
      'LOGIN_RATE_LIMITED': 'Đã thử sai nhiều lần. Vui lòng chờ 15 phút.',
      'RATE_LIMITED': 'Bạn thao tác quá nhanh. Vui lòng thử lại sau.',
      'SESSION_EXPIRED': 'Phiên đã hết hạn. Đăng nhập lại để tiếp tục.',
      'LOCAL_STORAGE_UNAVAILABLE':
          'Chưa mở được dữ liệu trên máy. Vui lòng đóng và mở lại app để thử lại.',
      'INVALID_NOTES':
          'Tiêu đề tối đa 500 ký tự, nội dung tối đa 100.000 ký tự.',
      'SESSION_BUSY': 'Đang có thao tác khác. Ứng dụng sẽ thử lại.',
    };
    final message =
        messages[code] ?? 'Máy chủ chưa xử lý được. Vui lòng thử lại.';
    final diagnostic = code.startsWith('NETWORK_') ? '\nMã lỗi: $code' : '';
    return requestId.isEmpty
        ? '$message$diagnostic'
        : '$message$diagnostic\nMã tra cứu: $requestId';
  }
}

abstract interface class NotesBackend {
  Future<List<Note>> loadNotes();
  Future<void> saveNotes(List<Note> notes);
  Future<void> logout();
  void close();
}

class Backend implements NotesBackend {
  Backend({this.token, http.Client? client})
    : _client = client ?? http.Client();
  final String? token;
  final http.Client _client;
  bool _closed = false;

  Future<http.Response> _send(
    String path, {
    String method = 'GET',
    Object? data,
    int retry = 0,
  }) async {
    if (_closed) throw const BackendError('CANCELLED');
    final headers = {
      'Origin': nativeOrigin,
      'Content-Type': 'application/json',
      'X-App-Session': ?token,
    };
    String? encoded;
    if (data != null) {
      // Pending note bodies can be large. Serialization never runs on the UI isolate.
      encoded = await compute(encodeJson, data);
    }
    http.Response response;
    try {
      final request = http.Request(method, Uri.parse('$backendUrl$path'))
        ..headers.addAll(headers);
      if (encoded != null) request.body = encoded;
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw BackendError(_closed ? 'CANCELLED' : 'NETWORK_TIMEOUT');
    } on HandshakeException {
      throw BackendError(_closed ? 'CANCELLED' : 'NETWORK_TLS');
    } on SocketException catch (error) {
      final dns = error.message.toLowerCase().contains('host lookup');
      throw BackendError(
        _closed
            ? 'CANCELLED'
            : dns
            ? 'NETWORK_DNS'
            : 'NETWORK_SOCKET',
      );
    } on http.ClientException {
      throw BackendError(_closed ? 'CANCELLED' : 'NETWORK_HTTP');
    } catch (_) {
      throw BackendError(_closed ? 'CANCELLED' : 'NETWORK_ERROR');
    }
    if (response.statusCode >= 400) {
      Map<String, dynamic> body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw BackendError('BACKEND_UNAVAILABLE', status: response.statusCode);
      }
      if (body['error'] == 'SESSION_BUSY' && retry < 2 && !_closed) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return _send(path, method: method, data: data, retry: retry + 1);
      }
      throw BackendError(
        body['error'] as String? ?? 'BACKEND_UNAVAILABLE',
        status: response.statusCode,
        requestId: body['requestId'] as String? ?? '',
      );
    }
    return response;
  }

  Future<Session> login(
    String username,
    String pin, {
    bool register = false,
  }) async {
    final response = await _send(
      register ? '/register' : '/login',
      method: 'POST',
      data: {'username': username.trim(), 'password': pin},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return Session(
      (body['user'] as Map<String, dynamic>)['id'] as String,
      body['session'] as String,
    );
  }

  @override
  Future<List<Note>> loadNotes() async {
    final response = await _send('/notes');
    return compute(decodeNotes, response.body);
  }

  @override
  Future<void> saveNotes(List<Note> notes) async {
    await _send(
      '/notes',
      method: 'PUT',
      data: {'notes': notes.map((note) => note.toRemote()).toList()},
    );
  }

  @override
  Future<void> logout() async {
    await _send('/logout', method: 'POST', data: <String, Object?>{});
  }

  @override
  void close() {
    _closed = true;
    _client.close();
  }
}

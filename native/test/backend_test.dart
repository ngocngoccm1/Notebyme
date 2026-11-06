import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notebyme/backend.dart';

void main() {
  final failures = <String, Exception>{
    'NETWORK_DNS': const SocketException('Failed host lookup: diagnostic'),
    'NETWORK_SOCKET': const SocketException('Connection refused'),
    'NETWORK_TLS': const HandshakeException('certificate'),
    'NETWORK_TIMEOUT': TimeoutException('timeout'),
    'NETWORK_HTTP': http.ClientException('interrupted'),
  };
  for (final failure in failures.entries) {
    test(
      'transport failure reports ${failure.key} without credentials',
      () async {
        final client = Backend(
          client: MockClient((_) async => throw failure.value),
        );
        try {
          await expectLater(
            client.login('mobile-test', '0042'),
            throwsA(
              isA<BackendError>()
                  .having((e) => e.code, 'code', failure.key)
                  .having((e) => e.message, 'message', isNot(contains('0042'))),
            ),
          );
        } finally {
          client.close();
        }
      },
    );
  }
}

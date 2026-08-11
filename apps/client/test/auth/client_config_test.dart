import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/config/client_config.dart';

void main() {
  test('empty API configuration keeps the client in local mode', () {
    final config = ClientConfig.fromValue('');

    expect(config.apiBaseUri, isNull);
  });

  test('production API configuration requires HTTPS', () {
    final config = ClientConfig.fromValue('https://api.example.com');

    expect(config.apiBaseUri, Uri.parse('https://api.example.com'));
  });

  test('cleartext API is allowed only for loopback development', () {
    expect(
      ClientConfig.fromValue('http://127.0.0.1:8000').apiBaseUri,
      Uri.parse('http://127.0.0.1:8000'),
    );
    expect(
      () => ClientConfig.fromValue('http://api.example.com'),
      throwsArgumentError,
    );
  });
}

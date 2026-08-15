import 'package:employee_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('normalizes a valid API base URL', () {
      final config = AppConfig.fromEnvironment(
        appEnvironment: 'staging',
        apiBaseUrl: 'https://api.example.test/api/v1/',
      );

      expect(config.appEnvironment, 'staging');
      expect(config.apiBaseUrl, 'https://api.example.test/api/v1');
    });

    test('rejects a non-HTTP API base URL', () {
      expect(
        () => AppConfig.fromEnvironment(
          appEnvironment: 'development',
          apiBaseUrl: 'ftp://invalid.example.test',
        ),
        throwsFormatException,
      );
    });
  });
}

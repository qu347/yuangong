import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

class AppConfig {
  const AppConfig({required this.appEnvironment, required this.apiBaseUrl});

  final String appEnvironment;
  final String apiBaseUrl;

  factory AppConfig.fromEnvironment({
    String appEnvironment = const String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    ),
    String apiBaseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000/api/v1',
    ),
  }) {
    final uri = Uri.tryParse(apiBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      throw const FormatException('API_BASE_URL 必须是有效的 HTTP 或 HTTPS 地址。');
    }

    return AppConfig(
      appEnvironment: appEnvironment.trim().isEmpty
          ? 'development'
          : appEnvironment.trim(),
      apiBaseUrl: apiBaseUrl.replaceFirst(RegExp(r'/+$'), ''),
    );
  }
}

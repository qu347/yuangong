import 'package:employee_app/core/config/app_config.dart';
import 'package:employee_app/features/dashboard/presentation/dashboard_page.dart';
import 'package:employee_app/features/health/data/health_response.dart';
import 'package:employee_app/features/health/presentation/health_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows healthy backend and environment details', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              appEnvironment: 'test',
              apiBaseUrl: 'https://api.example.test/api/v1',
            ),
          ),
          healthControllerProvider.overrideWith(
            (ref) async => const HealthResponse(
              status: 'ok',
              service: 'employee-api',
              version: '0.1.0',
              database: 'ok',
            ),
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('后端连接正常'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
    expect(find.text('https://api.example.test/api/v1'), findsOneWidget);
  });
}

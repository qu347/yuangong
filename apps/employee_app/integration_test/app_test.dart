import 'package:employee_app/app/app.dart';
import 'package:employee_app/core/config/app_config.dart';
import 'package:employee_app/features/health/data/health_response.dart';
import 'package:employee_app/features/health/presentation/health_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts without contacting a real backend', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(
              appEnvironment: 'integration-test',
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
        child: const EmployeeApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('后端连接正常'), findsOneWidget);
  });
}

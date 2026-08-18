import 'package:employee_app/features/shell/presentation/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses bottom navigation below the desktop breakpoint', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 700);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveShell(
          currentPath: '/dashboard',
          onDestinationSelected: (_) {},
          child: const SizedBox(),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('uses a navigation rail at the desktop breakpoint', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveShell(
          currentPath: '/dashboard',
          onDestinationSelected: (_) {},
          child: const SizedBox(),
        ),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('exposes logout as a separate shell action', (tester) async {
    var logoutCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveShell(
          currentPath: '/employees',
          onDestinationSelected: (_) {},
          onLogout: () {
            logoutCount += 1;
          },
          child: const SizedBox(),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('shell_logout')));

    expect(logoutCount, 1);
  });
}

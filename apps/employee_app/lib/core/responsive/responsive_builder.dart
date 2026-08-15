import 'package:flutter/widgets.dart';

import 'app_breakpoints.dart';

class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    required this.compact,
    required this.desktop,
    super.key,
  });

  final WidgetBuilder compact;
  final WidgetBuilder desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppBreakpoints.desktop) {
          return desktop(context);
        }
        return compact(context);
      },
    );
  }
}

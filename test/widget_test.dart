import 'package:chrono/main.dart';
import 'package:chrono/state/app_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app builds on the welcome screen', (tester) async {
    final state = AppState();
    await tester.pumpWidget(ChronoApp(state: state));
    expect(find.byType(ChronoApp), findsOneWidget);

    // Unmount, then stop the per-minute clock timer before the test ends.
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}

import 'package:chrono/main.dart';
import 'package:chrono/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app builds on the welcome screen', (tester) async {
    await tester.pumpWidget(ChronoApp(state: AppState()));
    expect(find.byType(ChronoApp), findsOneWidget);
  });
}

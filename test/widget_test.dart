import 'package:flutter_test/flutter_test.dart';
import 'package:hc4rl/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HC4RLApp());
    expect(find.text('HC4RL'), findsOneWidget);
  });
}

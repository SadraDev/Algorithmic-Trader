import 'package:flutter_test/flutter_test.dart';
import 'package:front/main.dart';

void main() {
  testWidgets('Algorithmic Trader Dashboard renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AlgorithmicTraderApp());

    // Verify that the Dashboard title and Active Algorithm Workers section load
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('ACTIVE ALGORITHM WORKERS'), findsOneWidget);
  });
}

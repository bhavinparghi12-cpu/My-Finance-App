import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance_app/main.dart';

void main() {
  testWidgets('App basic smoke test', (WidgetTester tester) async {
    // FinanceApp થી ટેસ્ટ થશે
    await tester.pumpWidget(const FinanceApp());
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:neuralsafe/main.dart';

void main() {
  testWidgets('Calculator screen renders with initial display of 0',
      (WidgetTester tester) async {
    await tester.pumpWidget(const NeuralSafeApp());

    expect(find.text('0'), findsNWidgets(2));
  });
}

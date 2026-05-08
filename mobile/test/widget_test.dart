import 'package:flutter_test/flutter_test.dart';

import 'package:pargig/main.dart';

void main() {
  testWidgets('App boots to splash', (WidgetTester tester) async {
    await tester.pumpWidget(const PargigApp());
    expect(find.text('PARGIG'), findsOneWidget);
  });
}

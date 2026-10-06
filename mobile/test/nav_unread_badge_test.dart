import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pargig/widgets/nav_unread_badge.dart';

Future<void> pumpBadge(WidgetTester tester, int count) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: NavUnreadBadge(
            icon: Icons.chat_bubble_outline,
            color: const Color(0xFF4A5565),
            count: count,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows nothing once everything is read', (tester) async {
    await pumpBadge(tester, 0);
    // No "0" pill — reading all messages clears the badge entirely.
    expect(find.text('0'), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
  });

  testWidgets('shows the exact number of unread messages', (tester) async {
    await pumpBadge(tester, 1);
    expect(find.text('1'), findsOneWidget);

    await pumpBadge(tester, 7);
    expect(find.text('7'), findsOneWidget);

    await pumpBadge(tester, 42);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('caps at 99+ so the pill cannot outgrow the icon',
      (tester) async {
    await pumpBadge(tester, 99);
    expect(find.text('99'), findsOneWidget);

    await pumpBadge(tester, 100);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('100'), findsNothing);

    await pumpBadge(tester, 5000);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('a negative count is treated as read, not rendered',
      (tester) async {
    // Defensive: the API should never send this, but a stray -1 must not
    // paint a badge reading "-1".
    await pumpBadge(tester, -1);
    expect(find.text('-1'), findsNothing);
  });

  testWidgets('lays out without overflow at the largest label',
      (tester) async {
    await pumpBadge(tester, 100);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

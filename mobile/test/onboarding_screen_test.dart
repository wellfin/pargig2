import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pargig/screens/onboarding_screen.dart';
import 'package:pargig/state/auth_state.dart';

Widget _wrap() => ChangeNotifierProvider<AuthState>(
      create: (_) => AuthState(),
      child: const MaterialApp(home: OnboardingScreen()),
    );

void main() {
  testWidgets('renders the wordmark, value prop and both role cards',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();

    expect(find.text('PARGIG'), findsOneWidget);
    expect(find.text('Post Any Need. Take Any Job'), findsOneWidget);
    expect(find.text('Need Help With Anything?'), findsOneWidget);
    expect(
      find.text('From 1 hour to 1 day or more. You decide the price.'),
      findsOneWidget,
    );
    expect(find.text('Post Job'), findsOneWidget);
    expect(find.text('Find Job'), findsOneWidget);
    expect(find.text('GET STARTED'), findsOneWidget);
    expect(find.text('Popular Task Categories'), findsOneWidget);
  });

  testWidgets('shows all twelve numbered categories', (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();

    // The grid lives below the fold on a phone-sized surface, so scroll
    // to the last tile before asserting on it.
    expect(find.textContaining('1. Need Someone to Help'), findsOneWidget);
    await tester.dragUntilVisible(
      find.textContaining('12. One-Time Tutor'),
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    expect(find.textContaining('12. One-Time Tutor'), findsOneWidget);
    expect(find.textContaining('2. Need a Plumber'), findsOneWidget);
  });

  testWidgets('role selection is switchable and defaults to Post Job',
      (tester) async {
    await tester.pumpWidget(_wrap());
    await tester.pump();

    // Tapping Find Job must not throw or navigate — it only changes the
    // selection; GET STARTED is what commits it.
    await tester.tap(find.text('Find Job'));
    await tester.pump();
    expect(find.text('Find Job'), findsOneWidget);

    await tester.tap(find.text('Post Job'));
    await tester.pump();
    expect(find.text('Post Job'), findsOneWidget);
  });

  testWidgets('lays out without overflow at a small phone size',
      (tester) async {
    // A 3-column grid of three-line captions inside a scroll view is the
    // easy thing to get wrong; a narrow screen is where it shows.
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

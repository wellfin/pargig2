import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pargig/screens/rate_experience_screen.dart';

Widget _wrap(RateExperienceArgs args) => MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: const RouteSettings(name: '/rate-experience'),
        builder: (_) => const RateExperienceScreen(),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  settings: RouteSettings(
                    name: '/rate-experience',
                    arguments: args,
                  ),
                  builder: (_) => const RateExperienceScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> open(WidgetTester tester, RateExperienceArgs args) async {
  await tester.pumpWidget(_wrap(args));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  const jobId = 'job123';

  group('job giver rating the worker (mandatory)', () {
    const args = RateExperienceArgs(
      jobId: jobId,
      jobTitle: 'Home Deep Cleaning',
      clientName: 'Suresh Kumar',
      nextRoute: '/my-posted-jobs',
      mandatory: true,
    );

    testWidgets('shows Required, not an Optional skip link', (tester) async {
      await open(tester, args);
      expect(find.text('Required'), findsOneWidget);
      expect(find.text('Optional'), findsNothing);
    });

    testWidgets('offers no back button', (tester) async {
      await open(tester, args);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('system back cannot leave the screen', (tester) async {
      await open(tester, args);
      expect(find.text('Rate Experience'), findsOneWidget);

      // Simulate the Android back gesture.
      final dynamic widgetsBinding = WidgetsBinding.instance;
      await widgetsBinding.handlePopRoute();
      await tester.pumpAndSettle();

      // Still here — the rating has not been given.
      expect(find.text('Rate Experience'), findsOneWidget);
      expect(find.text('open'), findsNothing);
    });

    testWidgets('Submit stays disabled until a star is picked',
        (tester) async {
      await open(tester, args);
      OutlinedButton submitButton() => tester.widget<OutlinedButton>(
            find.ancestor(
              of: find.text('Submit Rating'),
              matching: find.byType(OutlinedButton),
            ),
          );
      expect(submitButton().onPressed, isNull);

      // All five start empty (star_border); tapping the last fills it.
      expect(find.byIcon(Icons.star_border), findsNWidgets(5));
      await tester.tap(find.byIcon(Icons.star_border).last);
      await tester.pumpAndSettle();
      expect(submitButton().onPressed, isNotNull);
    });
  });

  group('worker rating the client (optional)', () {
    const args = RateExperienceArgs(jobId: jobId, jobTitle: 'Fix the tap');

    testWidgets('keeps the Optional skip link and the back button',
        (tester) async {
      await open(tester, args);
      expect(find.text('Optional'), findsOneWidget);
      expect(find.text('Required'), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('system back still leaves the screen', (tester) async {
      await open(tester, args);
      final dynamic widgetsBinding = WidgetsBinding.instance;
      await widgetsBinding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });
}

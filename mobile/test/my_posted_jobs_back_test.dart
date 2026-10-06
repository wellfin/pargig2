import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pargig/screens/my_posted_jobs_screen.dart';
import 'package:pargig/state/auth_state.dart';

/// Stand-in for the real /home, so the test can assert we landed there
/// without booting the whole home screen (which needs the network).
const _homeMarker = 'HOME-SCREEN';

Widget _app({required bool clearedStack}) {
  return ChangeNotifierProvider<AuthState>(
    create: (_) => AuthState(),
    child: MaterialApp(
      routes: {
        '/': (_) => Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      if (clearedStack) {
                        // Exactly what the rate-worker flow does: wipes
                        // every route below, leaving My Posted Jobs alone.
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/my-posted-jobs',
                          (_) => false,
                        );
                      } else {
                        Navigator.pushNamed(context, '/my-posted-jobs');
                      }
                    },
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
        '/my-posted-jobs': (_) => const MyPostedJobsScreen(),
        '/home': (_) => const Scaffold(body: Center(child: Text(_homeMarker))),
      },
    ),
  );
}

Future<void> _openAndTapBack(WidgetTester tester,
    {required bool clearedStack}) async {
  await tester.pumpWidget(_app(clearedStack: clearedStack));
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));

  expect(find.text('My Posted Jobs'), findsOneWidget);

  await tester.tap(find.byIcon(Icons.arrow_back));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('back goes home when the stack was cleared', (tester) async {
    // The reported bug: after release payment → rate worker, the stack is
    // empty beneath this screen and maybePop did nothing at all.
    await _openAndTapBack(tester, clearedStack: true);

    expect(find.text('My Posted Jobs'), findsNothing);
    expect(find.text(_homeMarker), findsOneWidget);
  });

  testWidgets('back still pops normally when there is a route below',
      (tester) async {
    await _openAndTapBack(tester, clearedStack: false);

    // Popped back to the launcher screen, not pushed home over the top.
    expect(find.text('My Posted Jobs'), findsNothing);
    expect(find.text('go'), findsOneWidget);
    expect(find.text(_homeMarker), findsNothing);
  });
}

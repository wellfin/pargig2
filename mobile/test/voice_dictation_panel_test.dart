import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pargig/widgets/voice_dictation_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_tts talks to the platform over a method channel that does not
  // exist in a test host. Record the calls instead so the button's effect
  // is observable.
  final ttsCalls = <MethodCall>[];
  setUp(() {
    ttsCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      ttsCalls.add(call);
      return 1;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  Future<TextEditingController> pump(WidgetTester tester, String initial) async {
    final ctrl = TextEditingController(text: initial);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: VoiceDictationPanel(
                description: ctrl,
                onChanged: () => setState(() {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return ctrl;
  }

  testWidgets('shows the mic and a Play button', (tester) async {
    await pump(tester, '');
    expect(find.text('Tap to start recording'), findsOneWidget);
    expect(find.text('Transcribed Text:'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('Play does nothing while the description is empty',
      (tester) async {
    await pump(tester, '');
    await tester.tap(find.text('Play'));
    await tester.pump();

    // No speak call should have been made — there is nothing to read.
    expect(ttsCalls.where((c) => c.method == 'speak'), isEmpty);
  });

  testWidgets('Play speaks the description text', (tester) async {
    await pump(tester, 'Need complete deep cleaning of my apartment');
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    final speak = ttsCalls.where((c) => c.method == 'speak');
    expect(speak, isNotEmpty);
    expect(speak.last.arguments,
        contains('Need complete deep cleaning of my apartment'));
  });

  testWidgets('voice is configured to match Job Details playback',
      (tester) async {
    await pump(tester, 'Wall painting for one bedroom');
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    // Same language, rate and pitch as job_details_screen, so the giver's
    // preview is not subtly different from what the worker hears.
    final methods = ttsCalls.map((c) => c.method).toList();
    expect(methods, contains('setLanguage'));
    expect(methods, contains('setSpeechRate'));
    expect(methods, contains('setPitch'));
    expect(
      ttsCalls.firstWhere((c) => c.method == 'setSpeechRate').arguments,
      0.45,
    );
  });

  testWidgets('button flips to Stop while speaking and stops on tap',
      (tester) async {
    await pump(tester, 'Fix the leaking kitchen tap please');
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    expect(ttsCalls.where((c) => c.method == 'stop'), isNotEmpty);
  });
}

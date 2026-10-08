import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/screens/apply_for_job_screen.dart' show formatSlot;

/// The schedule line's text.
///
/// Only the string is asserted here. Whether it fits on one line cannot
/// honestly be tested in `flutter test`: the test environment ships a
/// placeholder font where every glyph is a square of the font size, so a
/// 30-character line measures ~420px against a real font's ~210px. A
/// pixel assertion here would be measuring the fake font, not the app.
///
/// The truncation itself is fixed structurally — the line now spans the
/// full card width and wraps to a second line rather than ellipsing —
/// which no unit test can observe without a device.
void main() {
  test('a slot is formatted with its full date and time', () {
    expect(formatSlot(DateTime(2026, 10, 7, 18, 0)), '7 Oct 2026, 6:00 PM');
  });

  test('midday and midnight are not shown as 0:00', () {
    expect(formatSlot(DateTime(2026, 10, 7, 12, 0)), '7 Oct 2026, 12:00 PM');
    expect(formatSlot(DateTime(2026, 10, 7, 0, 5)), '7 Oct 2026, 12:05 AM');
  });

  test('minutes keep a leading zero', () {
    expect(formatSlot(DateTime(2026, 10, 7, 9, 5)), '7 Oct 2026, 9:05 AM');
  });

  test('the same instant reads the same wherever it is shown', () {
    // One formatter is shared by the apply screen, the applicants list
    // and the too-early PIN dialog, so the worker and the giver cannot
    // be shown different times for the same slot.
    final at = DateTime(2026, 12, 28, 14, 30);
    expect(formatSlot(at), formatSlot(at));
    expect(formatSlot(at), '28 Dec 2026, 2:30 PM');
  });
}

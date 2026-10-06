import 'package:flutter/material.dart';

/// A bottom-nav icon with a numeric unread badge.
///
/// Replaces the plain red dot the Messages tab used to wear. The dot only
/// said "something is waiting"; the count says how much, so the user can
/// tell one new message from twenty without opening the tab.
///
/// [count] is a number of unread MESSAGES, not rooms — that is what
/// /chat/unread returns (it sums per-room unread across every room). At
/// zero the badge is not rendered at all, so reading everything clears it.
///
/// Shared by every screen that draws the bottom bar (Home, Messages,
/// Wallet) so the three copies cannot drift apart.
class NavUnreadBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;

  /// Above this the badge reads "99+" — a four-digit number would be
  /// wider than the icon it sits on.
  static const int maxDisplayed = 99;

  const NavUnreadBadge({
    super.key,
    required this.icon,
    required this.color,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) {
    final label = count > maxDisplayed ? '$maxDisplayed+' : '$count';
    return SizedBox(
      width: 30,
      height: 26,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 24, color: color),
          if (count > 0)
            Positioned(
              // Pulled further out than the old dot: the pill is wider,
              // and centring it on the icon's corner would cover the glyph.
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 17),
                height: 17,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7000B),
                  // Rounded rather than a circle so "12" and "99+" stay
                  // legible instead of being squeezed into a dot.
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.4),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

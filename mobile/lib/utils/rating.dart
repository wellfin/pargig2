/// Star-rating display helpers.
///
/// The backend stores a user's rating as `{average, count}`, both
/// defaulting to 0 (see userModel). So a brand-new worker's *real*
/// average is 0.0 — and printing that renders "★ 0.0", which reads as
/// "rated terribly" rather than "not rated yet". Every screen showing a
/// rating has to make the same decision about that, and they were each
/// making a different one: some printed 0.0, one hardcoded 4.8.
///
/// The rule here: until at least one person has actually rated them, show
/// [unratedDefault]. After that, show the real average — never a
/// flattering placeholder over the top of genuine feedback.
library;

const double kUnratedDefault = 5.0;

/// Number of ratings a user has received. 0 when never rated.
int ratingCountValue(dynamic rating) {
  if (rating is Map) {
    final c = rating['count'];
    if (c is num) return c.toInt();
  }
  return 0;
}

/// True once at least one real rating exists.
bool hasRatings(dynamic rating) => ratingCountValue(rating) > 0;

/// The average as a number, or null when the user has never been rated.
///
/// Accepts both shapes the API returns: the `{average, count}` subdocument
/// and a bare number from endpoints that flatten it.
double? ratingAverage(dynamic rating) {
  if (rating is num) return rating > 0 ? rating.toDouble() : null;
  if (rating is Map) {
    final avg = rating['average'];
    if (avg is! num) return null;
    // A stored average of 0 with no count is the "never rated" default,
    // not a genuine zero score — treat it as absent.
    if (!hasRatings(rating) || avg <= 0) return null;
    return avg.toDouble();
  }
  return null;
}

/// One-decimal rating for display, e.g. "4.6". Falls back to
/// [unratedDefault] for a user nobody has rated yet.
String displayRating(dynamic rating, {double unratedDefault = kUnratedDefault}) {
  final avg = ratingAverage(rating);
  return (avg ?? unratedDefault).toStringAsFixed(1);
}

/// Review count suffix, e.g. "(24)" — empty while the user is unrated, so
/// a new worker doesn't advertise "(0)" next to their default stars.
String ratingCountLabel(dynamic rating) {
  final n = ratingCountValue(rating);
  return n > 0 ? '($n)' : '';
}

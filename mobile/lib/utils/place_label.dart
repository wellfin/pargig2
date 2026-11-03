import 'package:geocoding/geocoding.dart';

/// Turns a reverse-geocode result into the place name people recognise.
///
/// One function for every screen that names a location, because two
/// copies drifted: the home header said "Sector 135, Noida, Uttar
/// Pradesh" while the job search said "Dalelpur, Meerut Division, Uttar
/// Pradesh" — the same phone, standing still, named two different
/// places.
///
/// Two things caused that, and both are handled here.
String labelForPlacemarks(List<Placemark> placemarks) {
  final best = _bestPlacemark(placemarks);
  return best == null ? '' : _format(best);
}

/// Picks the most useful candidate from the list.
///
/// `placemarks.first` is not reliable: the geocoder returns several
/// candidates for one point and the order is not fixed, so the same
/// coordinates can come back as the town on one call and a neighbouring
/// village on the next. Choosing by what a candidate actually names is
/// stable where position in the list is not.
Placemark? _bestPlacemark(List<Placemark> placemarks) {
  if (placemarks.isEmpty) return null;

  Placemark? best;
  var bestScore = -1;
  for (final p in placemarks) {
    final score = _score(p);
    if (score > bestScore) {
      bestScore = score;
      best = p;
    }
  }
  return best;
}

/// The chosen candidate, for a screen that also fills city / state /
/// pincode fields. Those fields have to come from the same candidate
/// the label did: a screen taking `placemarks.first` for the fields
/// while the label came from elsewhere describes two different places
/// on one form.
Placemark? bestPlacemark(List<Placemark> placemarks) =>
    _bestPlacemark(placemarks);

/// A street-level line for an editable Address field — "Tower 4,
/// Sector 135, Noida" — where [labelForPlacemarks] gives the shorter
/// name of the area.
String addressLineForPlacemarks(List<Placemark> placemarks) {
  final p = _bestPlacemark(placemarks);
  if (p == null) return '';
  final parts = <String?>[_street(p), p.subLocality, p.locality]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
  // Nothing street-level worth showing: the area name beats an empty
  // address box.
  return parts.isEmpty ? _format(p) : parts.join(', ');
}

/// The street, or null when what the geocoder calls a street is not one.
///
/// Android fills `street` with an Open Location Code ("FCPR+G76") when
/// the point has no named road. That is a map reference, not an
/// address — it is what put "FCPR+G76, Sector 145, Noida" in front of
/// people who had just set their location to somewhere else entirely.
String? _street(Placemark p) {
  final s = p.street?.trim() ?? '';
  if (s.isEmpty) return null;
  if (_isPlusCode(s)) return null;
  if (s.toLowerCase() == 'unnamed road') return null;
  return s;
}

/// Open Location Code: a short code, '+', then two or three more —
/// "FCPR+G76", "7JVW52GR+2V". The alphabet excludes vowels and a few
/// confusable digits, which is what keeps this from matching a real
/// street name that happens to contain a '+'.
final _plusCode = RegExp(
  r'^[23456789CFGHJMPQRVWX]{2,8}\+[23456789CFGHJMPQRVWX]{2,3}$',
  caseSensitive: false,
);

bool _isPlusCode(String s) => _plusCode.hasMatch(s.trim());

/// How much a candidate tells us, weighted towards the parts people use
/// to say where they are. A sector or locality name is what someone
/// recognises; a state alone is not worth choosing over one.
int _score(Placemark p) {
  var score = 0;
  if (_has(p.subLocality)) score += 4;
  if (_has(p.locality)) score += 4;
  // A real street is worth preferring between two otherwise equal
  // candidates, but never worth more than naming the locality.
  if (_street(p) != null) score += 2;
  if (_has(p.administrativeArea)) score += 1;
  if (_has(p.postalCode)) score += 1;
  return score;
}

bool _has(String? s) => s != null && s.trim().isNotEmpty;

/// "Sector 135, Noida, Uttar Pradesh".
///
/// `subAdministrativeArea` is deliberately left out. In India it is
/// often an administrative division ("Meerut Division") that nobody uses
/// to describe where they are, and including it pushed the state out of
/// a three-part label while adding nothing a person would say.
String _format(Placemark p) {
  final parts = <String?>[p.subLocality, p.locality, p.administrativeArea]
      .whereType<String>()
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      // A sub-locality that repeats the locality ("Noida, Noida") reads
      // like a mistake.
      .toSet()
      .toList();

  // Nothing recognisable: fall back to whatever the candidate does name
  // rather than returning empty, which would leave the field blank.
  if (parts.isEmpty) {
    for (final s in [p.subAdministrativeArea, p.country]) {
      if (_has(s)) return s!.trim();
    }
    return '';
  }
  return parts.join(', ');
}

import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:pargig/utils/place_label.dart';

Placemark place({
  String? street,
  String? subLocality,
  String? locality,
  String? subAdmin,
  String? admin,
  String? postalCode,
  String? country,
}) => Placemark(
  street: street,
  subLocality: subLocality,
  locality: locality,
  subAdministrativeArea: subAdmin,
  administrativeArea: admin,
  postalCode: postalCode,
  country: country,
);

void main() {
  test('names the place the way people say it', () {
    expect(
      labelForPlacemarks([
        place(
          subLocality: 'Sector 135',
          locality: 'Noida',
          subAdmin: 'Gautam Buddha Nagar',
          admin: 'Uttar Pradesh',
        ),
      ]),
      'Sector 135, Noida, Uttar Pradesh',
    );
  });

  test('leaves out the administrative division', () {
    // "Meerut Division" is not something anyone says to describe where
    // they are, and including it pushed the state out of the label.
    final label = labelForPlacemarks([
      place(
        locality: 'Noida',
        subAdmin: 'Meerut Division',
        admin: 'Uttar Pradesh',
      ),
    ]);
    expect(label, 'Noida, Uttar Pradesh');
    expect(label.contains('Division'), isFalse);
  });

  group('picking between candidates', () {
    test('prefers the one that names a locality over a bare region', () {
      // The reported bug: the same spot named "Sector 135, Noida" in one
      // place and "Dalelpur, Meerut Division" in another, because each
      // screen took whichever candidate happened to be first.
      final fromGeocoder = [
        place(subAdmin: 'Meerut Division', admin: 'Uttar Pradesh'),
        place(
          subLocality: 'Sector 135',
          locality: 'Noida',
          admin: 'Uttar Pradesh',
          postalCode: '201301',
        ),
      ];
      expect(
        labelForPlacemarks(fromGeocoder),
        'Sector 135, Noida, Uttar Pradesh',
      );
    });

    test('order in the list does not change the answer', () {
      final a = place(subAdmin: 'Meerut Division', admin: 'Uttar Pradesh');
      final b = place(
        subLocality: 'Sector 135',
        locality: 'Noida',
        admin: 'Uttar Pradesh',
      );
      expect(labelForPlacemarks([a, b]), labelForPlacemarks([b, a]));
    });

    test('prefers the fuller of two named candidates', () {
      expect(
        labelForPlacemarks([
          place(locality: 'Noida', admin: 'Uttar Pradesh'),
          place(
            subLocality: 'Sector 135',
            locality: 'Noida',
            admin: 'Uttar Pradesh',
          ),
        ]),
        'Sector 135, Noida, Uttar Pradesh',
      );
    });
  });

  test('does not repeat a name back to itself', () {
    expect(
      labelForPlacemarks([
        place(subLocality: 'Noida', locality: 'Noida', admin: 'Uttar Pradesh'),
      ]),
      'Noida, Uttar Pradesh',
    );
  });

  test('skips blanks rather than leaving gaps', () {
    expect(
      labelForPlacemarks([
        place(subLocality: '   ', locality: 'Noida', admin: 'Uttar Pradesh'),
      ]),
      'Noida, Uttar Pradesh',
    );
  });

  test('falls back to something rather than nothing', () {
    // A point with no locality at all still names where it is, instead
    // of leaving the field empty.
    expect(
      labelForPlacemarks([place(subAdmin: 'Meerut Division')]),
      'Meerut Division',
    );
    expect(labelForPlacemarks([place(country: 'India')]), 'India');
  });

  test('an empty result is empty, not ", ,"', () {
    expect(labelForPlacemarks([]), '');
    expect(labelForPlacemarks([place()]), '');
  });

  group('address line', () {
    test('reads street, area, town', () {
      expect(
        addressLineForPlacemarks([
          place(
            street: 'Tower 4',
            subLocality: 'Sector 135',
            locality: 'Noida',
            admin: 'Uttar Pradesh',
          ),
        ]),
        'Tower 4, Sector 135, Noida',
      );
    });

    test('drops a plus code where a street should be', () {
      // The reported bug: "FCPR+G76, Sector 145, N..." sitting in the
      // location box. A plus code is a map reference, not an address,
      // and reading one back to someone tells them nothing.
      expect(
        addressLineForPlacemarks([
          place(
            street: 'FCPR+G76',
            subLocality: 'Sector 145',
            locality: 'Noida',
          ),
        ]),
        'Sector 145, Noida',
      );
    });

    test('drops a long-form plus code too', () {
      expect(
        addressLineForPlacemarks([
          place(street: '7JVW52GR+2V', locality: 'Noida'),
        ]),
        'Noida',
      );
    });

    test('keeps a street name that merely contains a plus', () {
      expect(
        addressLineForPlacemarks([
          place(street: 'A+ Plaza Road', locality: 'Noida'),
        ]),
        'A+ Plaza Road, Noida',
      );
    });

    test('drops Unnamed Road', () {
      expect(
        addressLineForPlacemarks([
          place(street: 'Unnamed Road', subLocality: 'Sector 135'),
        ]),
        'Sector 135',
      );
    });

    test('falls back to the area name when nothing is street-level', () {
      expect(
        addressLineForPlacemarks([
          place(street: 'FCPR+G76', admin: 'Uttar Pradesh'),
        ]),
        'Uttar Pradesh',
      );
      expect(addressLineForPlacemarks([]), '');
    });

    test('a plus code never becomes the short label either', () {
      expect(
        labelForPlacemarks([
          place(street: 'FCPR+G76', locality: 'Noida', admin: 'Uttar Pradesh'),
        ]),
        'Noida, Uttar Pradesh',
      );
    });
  });

  group('bestPlacemark', () {
    test('is the candidate the label came from', () {
      final vague = place(subAdmin: 'Meerut Division', admin: 'Uttar Pradesh');
      final useful = place(
        subLocality: 'Sector 135',
        locality: 'Noida',
        admin: 'Uttar Pradesh',
        postalCode: '201301',
      );
      // City / state / pincode boxes get filled from this, so it has to
      // be the same candidate that named the place — otherwise one form
      // describes two locations.
      expect(bestPlacemark([vague, useful])?.postalCode, '201301');
      expect(bestPlacemark([useful, vague])?.locality, 'Noida');
    });

    test('is null for nothing', () {
      expect(bestPlacemark([]), isNull);
    });

    test('prefers a real street between equal candidates', () {
      expect(
        bestPlacemark([
          place(subLocality: 'Sector 135', locality: 'Noida'),
          place(
            street: 'Tower 4',
            subLocality: 'Sector 135',
            locality: 'Noida',
          ),
        ])?.street,
        'Tower 4',
      );
    });

    test('a plus code does not count as a street', () {
      expect(
        bestPlacemark([
          place(street: 'FCPR+G76', subLocality: 'Sector 145'),
          place(subLocality: 'Sector 145', locality: 'Noida'),
        ])?.locality,
        'Noida',
      );
    });
  });
}

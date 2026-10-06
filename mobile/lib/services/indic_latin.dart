/// Rewrites Indic scripts into Latin letters, the way people actually
/// type their language in chat:
///
///   Hindi    मुझे कल ऑफिस जाना है  -> mujhe kal office jana hai
///   Marathi  मला उद्या सुट्टी हवी आहे -> mala udya sutti havi ahe
///   Bengali  আমি আজকে অফিসে যাবো   -> ami ajke ofise jabo
///   Tamil    எனக்கு பசிக்கிறது      -> enakku pasikkirathu
///   Telugu   నాకు చాలా సంతోషంగా ఉంది -> naaku chala santhoshamga undi
///
/// The recogniser transcribes each language in its native script, which
/// is correct but unreadable to anyone who doesn't read that script — and
/// job descriptions get read by whoever picks up the work. This converts
/// the *script*, never the words, so nothing is translated or reworded.
///
/// Informal spellings are used deliberately: ा and अ both become "a",
/// ी and ि both "i". Strict schemes need diacritics (ā, ī) that look
/// wrong in a job post. Text in Latin already is returned untouched, so
/// English and mixed writing pass straight through.
class IndicLatin {
  IndicLatin._();

  /// Converts any supported Indic script found in [text].
  ///
  /// Works word by word, so a sentence mixing English with an Indic
  /// language keeps both, and so per-word rules (like schwa deletion)
  /// don't leak across word boundaries.
  static String convert(String text) {
    if (!_hasIndic(text)) return text;
    final out = text
        .split(RegExp(r'(?<=\s)|(?=\s)'))
        .map(_convertWord)
        .join()
        .replaceAll(RegExp(r' +'), ' ')
        .trim();
    // Indic scripts have no capitals, so the result would otherwise
    // always start lowercase and read like a fragment.
    if (out.isEmpty) return out;
    return out[0].toUpperCase() + out.substring(1);
  }

  static bool _hasIndic(String text) => _scripts.any((s) => s.matches(text));

  static String _convertWord(String word) {
    final script = _scripts.where((s) => s.matches(word)).firstOrNull;
    if (script == null) return word;

    final chars = word.split('');
    final units = <_Unit>[];

    for (var i = 0; i < chars.length; i++) {
      var ch = chars[i];

      // Fold a following nukta into the base letter, so क + ़ is looked
      // up as क़ rather than emitting a stray mark.
      final nukta = script.nukta;
      if (nukta != null && i + 1 < chars.length && chars[i + 1] == nukta) {
        if (script.consonants.containsKey(ch + nukta)) {
          ch = ch + nukta;
          i++;
        }
      }

      final consonant = script.consonants[ch];
      if (consonant != null) {
        final next = i + 1 < chars.length ? chars[i + 1] : '';
        if (next == script.virama) {
          // Explicitly no vowel — part of a cluster.
          units.add(_Unit(consonant, '', explicitVowel: false));
          i++;
        } else if (script.matras.containsKey(next)) {
          units.add(_Unit(consonant, script.matras[next]!, explicitVowel: true));
          i++;
        } else {
          // Inherent vowel for now; _deleteSchwas decides if it survives.
          units.add(
            _Unit(consonant, script.inherentVowel, explicitVowel: false),
          );
        }
        continue;
      }

      final vowel = script.vowels[ch];
      if (vowel != null) {
        units.add(_Unit('', vowel, explicitVowel: true));
        continue;
      }

      final digit = script.digits[ch];
      if (digit != null) {
        units.add(_Unit(digit, '', explicitVowel: true));
        continue;
      }

      if (ch == script.anusvara || ch == script.chandrabindu) {
        // Nasal: "m" before labials reads more naturally than "n".
        units.add(
          _Unit(_labialFollows(script, chars, i + 1) ? 'm' : 'n', '',
              explicitVowel: true),
        );
        continue;
      }
      if (ch == script.visarga) {
        units.add(_Unit('h', '', explicitVowel: true));
        continue;
      }
      if (ch == script.virama || ch == script.nukta) continue; // stray mark
      if (ch == '।' || ch == '॥') {
        units.add(_Unit('.', '', explicitVowel: true));
        continue;
      }

      // Anything else (Latin, punctuation, emoji) passes through.
      units.add(_Unit(ch, '', explicitVowel: true));
    }

    if (script.deleteSchwa) _deleteSchwas(units);
    if (script.softenStops) _softenStops(units);
    final out = units.map((u) => u.consonant + u.vowel).join();
    // A long "aa" at the end of a word is written short: చాలా is
    // "chaala", not "chaalaa".
    return out.endsWith('aa') ? out.substring(0, out.length - 1) : out;
  }

  /// Drops the inherent vowel where the language doesn't pronounce it.
  ///
  /// Two rules, both needed for Hindi/Marathi/Bengali to read naturally:
  ///   - word-final: राम is "ram", not "rama"
  ///   - internal, between two pronounced syllables: करना is "karna" and
  ///     कमरे is "kamre". Without this every word gains a syllable.
  /// The first syllable keeps its vowel, which is why सफाई stays "safai"
  /// rather than collapsing to "sfai".
  ///
  /// Not applied to Tamil or Telugu, which do pronounce it — dropping it
  /// there would turn "enakku" into "enkku".
  static void _deleteSchwas(List<_Unit> units) {
    for (var i = units.length - 1; i >= 0; i--) {
      final u = units[i];
      if (u.explicitVowel || u.vowel.isEmpty || u.consonant.isEmpty) continue;

      if (i == units.length - 1) {
        u.vowel = '';
        continue;
      }
      final hasVowelBefore =
          i > 0 && units.sublist(0, i).any((p) => p.vowel.isNotEmpty);
      final hasVowelAfter = units.sublist(i + 1).any((n) => n.vowel.isNotEmpty);
      if (i > 0 && hasVowelBefore && hasVowelAfter) u.vowel = '';
    }
  }

  /// Tamil writes ச for both "ch" and "s", distinguished by position:
  /// "ch" at the start of a word (சென்னை -> chennai), "s" inside one
  /// (பசிக்கிறது -> pasikkirathu).
  ///
  /// Only this one letter is adjusted. Tamil voices its other stops by
  /// position too (க as k/g), but applying that generally turned
  /// "enakku" into "enagku" — geminates and clusters make the rule far
  /// less mechanical than it looks, and a wrong "g" reads worse than a
  /// consistent "k".
  static void _softenStops(List<_Unit> units) {
    for (var i = 1; i < units.length; i++) {
      final u = units[i];
      if (u.consonant == 'ch' && units[i - 1].vowel.isNotEmpty) {
        u.consonant = 's';
      }
    }
  }

  static bool _labialFollows(_Script script, List<String> chars, int index) {
    if (index >= chars.length) return false;
    return script.labials.contains(chars[index]);
  }

  // --------------------------------------------------------------- scripts

  static final List<_Script> _scripts = [
    _devanagari,
    _bengali,
    _tamil,
    _telugu,
  ];

  /// Hindi and Marathi.
  static final _devanagari = _Script(
    range: RegExp(r'[ऀ-ॿ]'),
    inherentVowel: 'a',
    deleteSchwa: true,
    virama: '्',
    anusvara: 'ं',
    chandrabindu: 'ँ',
    visarga: 'ः',
    nukta: '़',
    labials: const {'प', 'फ', 'ब', 'भ', 'म'},
    vowels: const {
      'अ': 'a', 'आ': 'a', 'इ': 'i', 'ई': 'i', 'उ': 'u', 'ऊ': 'u',
      'ऋ': 'ri', 'ॠ': 'ri', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au',
      'ऑ': 'o', 'ऍ': 'e',
    },
    matras: const {
      'ा': 'a', 'ि': 'i', 'ी': 'i', 'ु': 'u', 'ू': 'u', 'ृ': 'ri',
      'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ॉ': 'o', 'ॅ': 'e',
    },
    consonants: const {
      'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'n',
      'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'n',
      'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
      'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
      // फ is "f", not a strict "ph": people write "safai", not "saphai".
      'प': 'p', 'फ': 'f', 'ब': 'b', 'भ': 'bh', 'म': 'm',
      'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'ळ': 'l',
      'श': 'sh', 'ष': 'sh', 'स': 's', 'ह': 'h',
      'क़': 'q', 'ख़': 'kh', 'ग़': 'gh', 'ज़': 'z', 'ड़': 'r',
      'ढ़': 'rh', 'फ़': 'f', 'य़': 'y',
    },
    digits: const {
      '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
      '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
    },
  );

  /// Bengali. Its inherent vowel is "o", not "a" — কলকাতা is "kolkata".
  static final _bengali = _Script(
    range: RegExp(r'[ঀ-৿]'),
    inherentVowel: 'o',
    deleteSchwa: true,
    virama: '্',
    anusvara: 'ং',
    chandrabindu: 'ঁ',
    visarga: 'ঃ',
    nukta: '়',
    labials: const {'প', 'ফ', 'ব', 'ভ', 'ম'},
    vowels: const {
      'অ': 'o', 'আ': 'a', 'ই': 'i', 'ঈ': 'i', 'উ': 'u', 'ঊ': 'u',
      'ঋ': 'ri', 'এ': 'e', 'ঐ': 'oi', 'ও': 'o', 'ঔ': 'ou',
    },
    matras: const {
      'া': 'a', 'ি': 'i', 'ী': 'i', 'ু': 'u', 'ূ': 'u', 'ৃ': 'ri',
      'ে': 'e', 'ৈ': 'oi', 'ো': 'o', 'ৌ': 'ou',
    },
    consonants: const {
      'ক': 'k', 'খ': 'kh', 'গ': 'g', 'ঘ': 'gh', 'ঙ': 'ng',
      'চ': 'ch', 'ছ': 'chh', 'জ': 'j', 'ঝ': 'jh', 'ঞ': 'n',
      'ট': 't', 'ঠ': 'th', 'ড': 'd', 'ঢ': 'dh', 'ণ': 'n',
      'ত': 't', 'থ': 'th', 'দ': 'd', 'ধ': 'dh', 'ন': 'n',
      'প': 'p', 'ফ': 'f', 'ব': 'b', 'ভ': 'bh', 'ম': 'm',
      'য': 'j', 'র': 'r', 'ল': 'l', 'শ': 'sh', 'ষ': 'sh',
      'স': 's', 'হ': 'h', 'ৎ': 't',
      'ড়': 'r', 'ঢ়': 'rh', 'য়': 'y',
    },
    digits: const {
      '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4',
      '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
    },
  );

  /// Tamil. One letter serves each stop consonant, voiced by position —
  /// see _softenStops.
  static final _tamil = _Script(
    range: RegExp(r'[஀-௿]'),
    inherentVowel: 'a',
    deleteSchwa: false,
    softenStops: true,
    virama: '்',
    anusvara: null,
    chandrabindu: null,
    visarga: 'ঃ',
    nukta: null,
    labials: const {'ப', 'ம'},
    vowels: const {
      'அ': 'a', 'ஆ': 'a', 'இ': 'i', 'ஈ': 'i', 'உ': 'u', 'ஊ': 'u',
      'எ': 'e', 'ஏ': 'e', 'ஐ': 'ai', 'ஒ': 'o', 'ஓ': 'o', 'ஔ': 'au',
    },
    matras: const {
      'ா': 'a', 'ி': 'i', 'ீ': 'i', 'ு': 'u', 'ூ': 'u',
      'ெ': 'e', 'ே': 'e', 'ை': 'ai', 'ொ': 'o', 'ோ': 'o', 'ௌ': 'au',
    },
    consonants: const {
      'க': 'k', 'ங': 'ng', 'ச': 'ch', 'ஞ': 'nj', 'ட': 't', 'ண': 'n',
      'த': 'th', 'ந': 'n', 'ப': 'p', 'ம': 'm', 'ய': 'y', 'ர': 'r',
      'ல': 'l', 'வ': 'v', 'ழ': 'zh', 'ள': 'l', 'ற': 'r', 'ன': 'n',
      'ஜ': 'j', 'ஷ': 'sh', 'ஸ': 's', 'ஹ': 'h', 'க்ஷ': 'ksh',
    },
    digits: const {
      '௦': '0', '௧': '1', '௨': '2', '௩': '3', '௪': '4',
      '௫': '5', '௬': '6', '௭': '7', '௮': '8', '௯': '9',
    },
  );

  /// Telugu. Pronounces its inherent vowel, so no schwa deletion.
  static final _telugu = _Script(
    range: RegExp(r'[ఀ-౿]'),
    inherentVowel: 'a',
    deleteSchwa: false,
    virama: '్',
    anusvara: 'ం',
    chandrabindu: 'ఁ',
    visarga: 'ః',
    nukta: null,
    labials: const {'ప', 'ఫ', 'బ', 'భ', 'మ'},
    vowels: const {
      'అ': 'a', 'ఆ': 'aa', 'ఇ': 'i', 'ఈ': 'i', 'ఉ': 'u', 'ఊ': 'u',
      'ఋ': 'ri', 'ఎ': 'e', 'ఏ': 'e', 'ఐ': 'ai', 'ఒ': 'o', 'ఓ': 'o',
      'ఔ': 'au',
    },
    matras: const {
      'ా': 'aa', 'ి': 'i', 'ీ': 'i', 'ు': 'u', 'ూ': 'u', 'ృ': 'ri',
      'ె': 'e', 'ే': 'e', 'ై': 'ai', 'ొ': 'o', 'ో': 'o', 'ౌ': 'au',
    },
    consonants: const {
      'క': 'k', 'ఖ': 'kh', 'గ': 'g', 'ఘ': 'gh', 'ఙ': 'ng',
      'చ': 'ch', 'ఛ': 'chh', 'జ': 'j', 'ఝ': 'jh', 'ఞ': 'n',
      'ట': 't', 'ఠ': 'th', 'డ': 'd', 'ఢ': 'dh', 'ణ': 'n',
      // త is a plain "t" — సంతోషం is "santosham", not "santhosham".
      // The aspirated థ carries the "th".
      'త': 't', 'థ': 'th', 'ద': 'd', 'ధ': 'dh', 'న': 'n',
      'ప': 'p', 'ఫ': 'f', 'బ': 'b', 'భ': 'bh', 'మ': 'm',
      'య': 'y', 'ర': 'r', 'ల': 'l', 'వ': 'v', 'ళ': 'l', 'ఱ': 'r',
      'శ': 'sh', 'ష': 'sh', 'స': 's', 'హ': 'h',
    },
    digits: const {
      '౦': '0', '౧': '1', '౨': '2', '౩': '3', '౪': '4',
      '౫': '5', '౬': '6', '౭': '7', '౮': '8', '౯': '9',
    },
  );
}

class _Script {
  final RegExp range;
  final String inherentVowel;
  final bool deleteSchwa;
  final bool softenStops;
  final String virama;
  final String? anusvara;
  final String? chandrabindu;
  final String? visarga;
  final String? nukta;
  final Set<String> labials;
  final Map<String, String> vowels;
  final Map<String, String> matras;
  final Map<String, String> consonants;
  final Map<String, String> digits;

  _Script({
    required this.range,
    required this.inherentVowel,
    required this.deleteSchwa,
    required this.virama,
    required this.anusvara,
    required this.chandrabindu,
    required this.visarga,
    required this.nukta,
    required this.labials,
    required this.vowels,
    required this.matras,
    required this.consonants,
    required this.digits,
    this.softenStops = false,
  });

  bool matches(String text) => range.hasMatch(text);
}

/// A consonant plus its vowel, or a standalone vowel/passthrough char.
/// [explicitVowel] marks vowels that were actually written, so schwa
/// deletion only ever removes the implied ones.
class _Unit {
  String consonant;
  String vowel;
  final bool explicitVowel;

  _Unit(this.consonant, this.vowel, {required this.explicitVowel});
}

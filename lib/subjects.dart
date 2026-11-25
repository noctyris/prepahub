/// Retire les préfixes ou suffixes de type de cours pour regrouper les notes
/// d'une même matière : « TD Maths », « TP Maths » et « Maths » deviennent
/// « Maths ».
final _leadingType = RegExp(
  r"^(?:(?:td|tp|cm|ci|cours)\b(?:[\s\-:./]+(?:de|du|d['’]))?[\s\-:./]*)*",
  caseSensitive: false,
);
final _trailingType = RegExp(
  r'(?:[\s\-:./]+(?:td|tp|cm|ci|cours))+\s*$',
  caseSensitive: false,
);

String canonicalSubject(String matiere) {
  final original = matiere.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (original.isEmpty) return original;
  var value = original
      .replaceFirst(_leadingType, '')
      .replaceFirst(_trailingType, '')
      .trim();
  return value.isEmpty ? original : value;
}

const _accents = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ç': 'c',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'î': 'i',
  'ï': 'i',
  'ô': 'o',
  'ö': 'o',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ÿ': 'y',
  'œ': 'oe',
};

/// Normalise un texte pour la recherche : minuscules, sans accents et sans
/// ponctuation.
String foldText(String value) {
  var result = value.toLowerCase();
  for (final entry in _accents.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

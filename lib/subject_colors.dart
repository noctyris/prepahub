import 'package:material_ui/material_ui.dart';

/// Couleurs d'une matière, dérivées de sa graine et du thème courant.
class SubjectPalette {
  final Color accent;
  final Color container;
  final Color onContainer;

  const SubjectPalette({
    required this.accent,
    required this.container,
    required this.onContainer,
  });
}

final Map<(int, Brightness), SubjectPalette> _paletteCache = {};

/// Construit une palette lisible en clair comme en sombre à partir de la
/// couleur choisie pour la matière dans l'emploi du temps.
SubjectPalette subjectPalette(int seed, Brightness brightness) {
  return _paletteCache.putIfAbsent((seed, brightness), () {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(seed),
      brightness: brightness,
    );
    return SubjectPalette(
      accent: scheme.primary,
      container: scheme.primaryContainer,
      onContainer: scheme.onPrimaryContainer,
    );
  });
}

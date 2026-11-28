import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prepahub/subject_colors.dart';

void main() {
  test('adapte la palette d’une matière au thème', () {
    final light = subjectPalette(0xFF1565C0, Brightness.light);
    final dark = subjectPalette(0xFF1565C0, Brightness.dark);

    expect(light.accent, isNot(dark.accent));
    expect(light.container, isNot(dark.container));
    expect(light.onContainer, isNot(dark.onContainer));
  });

  test('réutilise la même palette pour une graine et un thème donnés', () {
    final first = subjectPalette(0xFF1565C0, Brightness.light);
    final second = subjectPalette(0xFF1565C0, Brightness.light);

    expect(identical(first, second), isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:prepahub/api/parse.dart';
import 'package:prepahub/colloscope.dart';

Colle _colle(String matiere, DateTime date) =>
    Colle(matiere: matiere, date: date, prof: '', salle: '');

void main() {
  test('propose les matières des khôlles passées, regroupées et triées', () {
    final now = DateTime(2026, 11, 25, 12);
    final subjects = pastColleSubjects([
      _colle('TP Maths', DateTime(2026, 11, 24)),
      _colle('TD Maths', DateTime(2026, 11, 20)),
      _colle('Physique', DateTime(2026, 11, 23)),
      _colle('Anglais', DateTime(2026, 12, 2)),
    ], now: now);

    expect(subjects, ['Maths', 'Physique']);
  });

  test('se rabat sur toutes les khôlles quand aucune n’est passée', () {
    final now = DateTime(2026, 11, 25);
    final subjects = pastColleSubjects([
      _colle('TD Maths', now.add(const Duration(days: 2))),
      _colle('Anglais', now.add(const Duration(days: 3))),
    ], now: now);

    expect(subjects, ['Anglais', 'Maths']);
  });
}

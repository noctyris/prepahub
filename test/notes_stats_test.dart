import 'package:flutter_test/flutter_test.dart';
import 'package:prepahub/api/parse.dart';
import 'package:prepahub/notes_stats.dart';
import 'package:prepahub/subjects.dart';

Note _note(
  String matiere,
  double value, {
  double? moyenne,
  double? ecartType,
}) => Note(
  matiere: matiere,
  note: value,
  professeur: '',
  rang: Rang(),
  moyenne: moyenne,
  ecartType: ecartType,
);

void main() {
  test('regroupe TD, TP et cours dans la même matière', () {
    expect(canonicalSubject('TD Maths'), 'Maths');
    expect(canonicalSubject('TP Maths'), 'Maths');
    expect(canonicalSubject('Cours de Maths'), 'Maths');
    expect(canonicalSubject('Maths - Cours'), 'Maths');
    expect(canonicalSubject('Physique'), 'Physique');
  });

  test('calcule une moyenne pondérée par matière', () {
    final analytics = NotesAnalytics([
      Semaine(
        debut: '',
        fin: '',
        notes: [_note('TD Maths', 10), _note('Physique', 16)],
      ),
    ]);

    expect(
      analytics.weightedAverage({'Maths': 2, 'Physique': 1}),
      closeTo(12, 0.001),
    );
    expect(analytics.simpleAverage(), closeTo(13, 0.001));
  });

  test('calcule une distribution normale à partir des moyennes de classe', () {
    final analytics = NotesAnalytics([
      Semaine(
        debut: '',
        fin: '',
        notes: [
          _note('Maths', 14, moyenne: 10, ecartType: 2),
          _note('Physique', 16, moyenne: 14, ecartType: 2),
        ],
      ),
    ]);

    final normal = analytics.normalDistribution();

    expect(normal, isNotNull);
    expect(normal!.moyenne, closeTo(12, 0.001));
    expect(normal.ecartType, closeTo(2.8284, 0.001));
  });

  test('trouve la tranche d’une moyenne', () {
    expect(gradeBucket(0), 0);
    expect(gradeBucket(4), 1);
    expect(gradeBucket(12), 3);
    expect(gradeBucket(20), 4);
    expect(gradeBucket(null), isNull);
  });

  test('simule la note nécessaire dans une matière', () {
    final analytics = NotesAnalytics([
      Semaine(
        debut: '',
        fin: '',
        notes: [_note('Maths', 10), _note('Physique', 16)],
      ),
    ]);

    final required = analytics.requiredGrade(
      subject: 'Maths',
      target: 14,
      coefficients: {'Maths': 2, 'Physique': 1},
    );

    expect(required, closeTo(16, 0.001));
  });

  test('garde les semaines sans note comme trous dans les courbes', () {
    final analytics = NotesAnalytics([
      Semaine(numero: 1, debut: '', fin: '', notes: [_note('Maths', 12)]),
      Semaine(numero: 2, debut: '', fin: '', notes: []),
      Semaine(numero: 3, debut: '', fin: '', notes: [_note('TP Maths', 16)]),
    ]);

    expect(analytics.weeklySeries(subject: 'Maths'), [12.0, null, 16.0]);
    expect(analytics.subjects, ['Maths']);
  });
}

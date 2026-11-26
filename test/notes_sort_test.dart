import 'package:flutter_test/flutter_test.dart';
import 'package:prepahub/api/parse.dart';
import 'package:prepahub/app_settings.dart';
import 'package:prepahub/notes_sort.dart';

Note _note(String matiere, double? value, {int? rang}) => Note(
  matiere: matiere,
  note: value,
  professeur: '',
  rang: Rang(rang: rang, total: 30),
);

List<String> _subjects(List<Note> notes) => [
  for (final note in notes) note.matiere,
];

void main() {
  final notes = [
    _note('Physique', 12, rang: 5),
    _note('Maths', 16, rang: 2),
    _note('Anglais', 9, rang: 12),
  ];

  test('trie par note croissante et décroissante', () {
    expect(
      _subjects(
        orderedNotes(notes, NotesSort.grade, NotesSortDirection.ascending),
      ),
      ['Anglais', 'Physique', 'Maths'],
    );
    expect(
      _subjects(
        orderedNotes(notes, NotesSort.grade, NotesSortDirection.descending),
      ),
      ['Maths', 'Physique', 'Anglais'],
    );
  });

  test('trie par rang croissant et décroissant', () {
    expect(
      _subjects(
        orderedNotes(notes, NotesSort.rank, NotesSortDirection.ascending),
      ),
      ['Maths', 'Physique', 'Anglais'],
    );
    expect(
      _subjects(
        orderedNotes(notes, NotesSort.rank, NotesSortDirection.descending),
      ),
      ['Anglais', 'Physique', 'Maths'],
    );
  });

  test('trie par matière dans les deux sens', () {
    expect(
      _subjects(
        orderedNotes(notes, NotesSort.subject, NotesSortDirection.ascending),
      ),
      ['Anglais', 'Maths', 'Physique'],
    );
    expect(
      _subjects(
        orderedNotes(notes, NotesSort.subject, NotesSortDirection.descending),
      ),
      ['Physique', 'Maths', 'Anglais'],
    );
  });

  test('garde les notes sans valeur en fin de liste', () {
    final withMissing = [_note('Sans note', null), _note('Maths', 10)];

    expect(
      _subjects(
        orderedNotes(
          withMissing,
          NotesSort.grade,
          NotesSortDirection.descending,
        ),
      ),
      ['Maths', 'Sans note'],
    );
  });

  test('inverse l’ordre des semaines avec le temps décroissant', () {
    final weeks = [
      Semaine(
        numero: 1,
        debut: '01/09',
        fin: '06/09',
        notes: [_note('Maths', 10)],
      ),
      Semaine(
        numero: 2,
        debut: '08/09',
        fin: '13/09',
        notes: [_note('Physique', 12)],
      ),
    ];

    final ordered = orderedWeeks(
      weeks,
      NotesSort.time,
      NotesSortDirection.descending,
    );

    expect([for (final week in ordered) week.numero], [2, 1]);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:prepahub/api/parse.dart';
import 'package:prepahub/notes_store.dart';

void main() {
  test('une semaine et ses notes survivent à un aller-retour JSON', () {
    final semaine = Semaine(
      numero: 12,
      debut: '23/11',
      fin: '28/11',
      notes: [
        Note(
          matiere: 'Maths',
          note: 14.5,
          professeur: 'Mme Martin',
          rang: Rang(rang: 3, total: 42),
          moyenne: 11.2,
          ecartType: 4.1,
        ),
      ],
    );

    final copy = Semaine.fromJson(semaine.toJson());

    expect(copy.numero, 12);
    expect(copy.debut, '23/11');
    expect(copy.notes, hasLength(1));
    expect(copy.notes.first.matiere, 'Maths');
    expect(copy.notes.first.note, 14.5);
    expect(copy.notes.first.professeur, 'Mme Martin');
    expect(copy.notes.first.rang.rang, 3);
    expect(copy.notes.first.rang.total, 42);
    expect(copy.notes.first.moyenne, 11.2);
    expect(copy.notes.first.local, isFalse);
  });

  test('une note locale conserve son identifiant', () {
    final note = Note(
      id: 'local-1',
      matiere: 'Physique',
      note: 12,
      professeur: '',
      rang: Rang(),
      local: true,
    );

    final copy = Note.fromJson(note.toJson());

    expect(copy.id, 'local-1');
    expect(copy.local, isTrue);
    expect(copy.note, 12);
  });

  test('les signatures ignorent les notes locales et suivent la semaine', () {
    final semaine = Semaine(
      numero: 3,
      debut: '01/12',
      fin: '06/12',
      notes: [
        Note(
          matiere: 'Anglais',
          note: 15,
          professeur: 'M. Durand',
          rang: Rang(),
        ),
        Note(
          id: 'local-2',
          matiere: 'Anglais',
          note: 15,
          professeur: '',
          rang: Rang(),
          local: true,
        ),
      ],
    );

    final signatures = NotesStore.signatures([semaine]);

    expect(signatures, hasLength(1));
    expect(signatures.first, contains('3|01/12|anglais|15.00'));
  });
}

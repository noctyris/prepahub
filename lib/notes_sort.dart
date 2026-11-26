import 'api/parse.dart';
import 'app_settings.dart';
import 'subjects.dart';

int _compareNullable(num? a, num? b, NotesSortDirection direction) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  final result = a.compareTo(b);
  return direction == NotesSortDirection.ascending ? result : -result;
}

/// Trie les notes d'une semaine. Les notes sans valeur restent en fin de liste.
List<Note> orderedNotes(
  Iterable<Note> notes,
  NotesSort sort,
  NotesSortDirection direction,
) {
  final source = notes.toList();
  final indices = List<int>.generate(source.length, (index) => index);

  int compare(Note a, Note b) {
    switch (sort) {
      case NotesSort.time:
        return 0;
      case NotesSort.grade:
        return _compareNullable(a.note, b.note, direction);
      case NotesSort.rank:
        return _compareNullable(a.rang.rang, b.rang.rang, direction);
      case NotesSort.subject:
        final result = foldText(a.matiere).compareTo(foldText(b.matiere));
        return direction == NotesSortDirection.ascending ? result : -result;
    }
  }

  indices.sort((i, j) {
    final result = compare(source[i], source[j]);
    if (result != 0) return result;
    if (sort == NotesSort.time && direction == NotesSortDirection.descending) {
      return j.compareTo(i);
    }
    return i.compareTo(j);
  });

  return [for (final index in indices) source[index]];
}

/// Ordonne les semaines et les notes qu'elles contiennent. Seul le critère
/// « temps » change l'ordre des semaines ; les autres gardent la chronologie
/// du portail.
List<Semaine> orderedWeeks(
  Iterable<Semaine> semaines,
  NotesSort sort,
  NotesSortDirection direction,
) {
  final source = semaines.toList();
  final indices = List<int>.generate(source.length, (index) => index);

  if (sort == NotesSort.time) {
    int compare(Semaine a, Semaine b) {
      final left = a.numero;
      final right = b.numero;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      final result = left.compareTo(right);
      return direction == NotesSortDirection.ascending ? result : -result;
    }

    indices.sort((i, j) {
      final result = compare(source[i], source[j]);
      return result != 0 ? result : i.compareTo(j);
    });
  }

  return [
    for (final index in indices)
      Semaine(
        numero: source[index].numero,
        debut: source[index].debut,
        fin: source[index].fin,
        notes: orderedNotes(source[index].notes, sort, direction),
      ),
  ];
}

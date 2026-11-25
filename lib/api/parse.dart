import 'package:html/parser.dart' show parse;

class Rang {
  final int? rang;
  final int? total;
  Rang({this.rang, this.total});
}

class Note {
  final String? id;
  final String matiere;
  final double? note;
  final String professeur;
  final Rang rang;
  final double? moyenne;
  final double? ecartType;
  final bool local;
  Note({
    this.id,
    required this.matiere,
    this.note,
    required this.professeur,
    required this.rang,
    this.moyenne,
    this.ecartType,
    this.local = false,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'matiere': matiere,
    'note': note,
    'professeur': professeur,
    'rang': rang.rang,
    'rangTotal': rang.total,
    'moyenne': moyenne,
    'ecartType': ecartType,
    if (local) 'local': true,
  };

  factory Note.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    int? asInt(Object? value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return Note(
      id: json['id']?.toString(),
      matiere: json['matiere']?.toString() ?? '',
      note: asDouble(json['note']),
      professeur: json['professeur']?.toString() ?? '',
      rang: Rang(
        rang: asInt(json['rang']),
        total: asInt(json['rangTotal']),
      ),
      moyenne: asDouble(json['moyenne']),
      ecartType: asDouble(json['ecartType']),
      local: json['local'] == true,
    );
  }
}

class Semaine {
  final int? numero;
  final String debut;
  final String fin;
  final List<Note> notes;
  Semaine({
    this.numero,
    required this.debut,
    required this.fin,
    required this.notes,
  });

  Map<String, dynamic> toJson() => {
    'numero': numero,
    'debut': debut,
    'fin': fin,
    'notes': [for (final note in notes) note.toJson()],
  };

  factory Semaine.fromJson(Map<String, dynamic> json) => Semaine(
    numero: json['numero'] is num
        ? (json['numero'] as num).toInt()
        : int.tryParse(json['numero']?.toString() ?? ''),
    debut: json['debut']?.toString() ?? '',
    fin: json['fin']?.toString() ?? '',
    notes: [
      for (final item in (json['notes'] as List? ?? const []))
        if (item is Map) Note.fromJson(Map<String, dynamic>.from(item)),
    ],
  );
}

class SemaineColles {
  final int? numero;
  final String debut;
  final String fin;
  final List<Colle> colles;
  SemaineColles({
    this.numero,
    required this.debut,
    required this.fin,
    required this.colles,
  });
}

class Colle {
  final String matiere;
  final DateTime date;
  final String prof;
  final String salle;
  Colle({
    required this.matiere,
    required this.date,
    required this.prof,
    required this.salle,
  });
}

class Cours {
  final String matiere;
  final int jour;
  final String heureDebut;
  final String heureFin;
  final int restrictions;
  final String prof;
  final String salle;
  final int semestre;
  Cours({
    required this.matiere,
    required this.jour,
    required this.heureDebut,
    required this.heureFin,
    required this.restrictions,
    required this.prof,
    required this.salle,
    this.semestre = 1,
  });

  /// Masque des semaines où le cours a lieu (bit 0 = semaine 1).
  /// `0` signifie que le cours a lieu toutes les semaines.
  bool appliesToWeek(int semaine) =>
      restrictions == 0 || (restrictions & (1 << (semaine - 1))) != 0;
}

double? parseFr(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

({String prof, Rang rang, double? moyenne, double? et}) parseDetail(String d) {
  var prof = '';
  var rang = Rang();
  double? moyenne;
  double? et;

  for (final raw in d.split(';')) {
    final part = raw.trim();
    if (part.startsWith('Rg:')) {
      final bits = part.substring(3).trim().split('/');
      rang = Rang(
        rang: int.tryParse(bits[0].trim()),
        total: bits.length > 1 ? int.tryParse(bits[1].trim()) : null,
      );
    } else if (part.startsWith('Moy:')) {
      moyenne = parseFr(part.substring(4));
    } else if (part.startsWith('ET:')) {
      et = parseFr(part.substring(3));
    } else if (part.isNotEmpty) {
      prof = part;
    }
  }
  return (prof: prof, rang: rang, moyenne: moyenne, et: et);
}

({int? numero, String debut, String fin}) parseSemaine(String s) {
  String dates;
  int? numero;
  final i = s.indexOf(':');
  if (i >= 0) {
    final tag = s.substring(0, i).trim();
    numero = tag.startsWith('S') ? int.tryParse(tag.substring(1)) : null;
    dates = s.substring(i + 1).trim();
  } else {
    dates = s.trim();
  }
  final j = dates.indexOf('-');
  final debut = j >= 0 ? dates.substring(0, j).trim() : dates;
  final fin = j >= 0 ? dates.substring(j + 1).trim() : '';
  return (numero: numero, debut: debut, fin: fin);
}

List<Semaine> parseNotes(String html) {
  final doc = parse(html);
  final semaines = <Semaine>[];

  for (final table in doc.querySelectorAll('table')) {
    final th = table.querySelector('th');
    if (th?.text.trim() != 'Semaine') continue;

    final rows = table.querySelectorAll('tr');
    if (rows.isEmpty) continue;
    final headers = rows.first
        .querySelectorAll('th')
        .map((e) => e.text.trim())
        .toList();

    for (final row in rows.skip(1)) {
      final cells = row.querySelectorAll('th, td');
      if (cells.isEmpty) continue;
      final raw = cells.first.text.trim();
      final s = parseSemaine(raw);

      final notes = <Note>[];
      final matieres = headers.skip(1).toList();
      final cellsRest = cells.skip(1).toList();
      for (var i = 0; i < matieres.length && i < cellsRest.length; i++) {
        final span = cellsRest[i].querySelector('span');
        if (span == null) continue;
        final noteTxt = span.text.trim();
        final detail = span.attributes['title'] ?? '';
        final d = parseDetail(detail);
        notes.add(
          Note(
            matiere: matieres[i],
            note: parseFr(noteTxt),
            professeur: d.prof,
            rang: d.rang,
            moyenne: d.moyenne,
            ecartType: d.et,
          ),
        );
      }
      semaines.add(
        Semaine(numero: s.numero, debut: s.debut, fin: s.fin, notes: notes),
      );
    }
  }
  return semaines;
}

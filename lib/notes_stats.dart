import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'api/parse.dart';
import 'subjects.dart';

/// Coefficients appliqués à chaque matière pour le calcul de la moyenne
/// pondérée. Une valeur absente vaut 1.
class SubjectCoefficientsStore {
  static const _key = 'notes_coefficients';

  static Future<Map<String, double>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return {};
      final data = jsonDecode(raw);
      if (data is! Map) return {};
      final result = <String, double>{};
      for (final entry in data.entries) {
        final value = entry.value;
        if (value is num && value >= 0) {
          result[canonicalSubject(entry.key.toString())] = value.toDouble();
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<String, double> coefficients) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final entry in coefficients.entries)
            if (entry.value > 0) entry.key: entry.value,
        }),
      );
    } catch (_) {}
  }
}

class WeekNotes {
  final String label;
  final List<Note> notes;

  const WeekNotes(this.label, this.notes);
}

/// Tranche de 4 points contenant [value], ou `null` si la valeur manque.
int? gradeBucket(double? value) {
  if (value == null || !value.isFinite) return null;
  var bucket = (value / 4).floor();
  if (bucket < 0) bucket = 0;
  if (bucket > 4) bucket = 4;
  return bucket;
}

/// Agrège les notes du portail, les notes locales et les semaines pour les
/// graphiques et la moyenne pondérée.
class NotesAnalytics {
  final List<WeekNotes> weeks;
  final List<Note> localNotes;

  NotesAnalytics(List<Semaine> semaines, [List<Note> localNotes = const []])
    : weeks = [
        for (var i = 0; i < semaines.length; i++)
          WeekNotes(
            semaines[i].numero != null ? 'S${semaines[i].numero}' : 'S${i + 1}',
            semaines[i].notes,
          ),
      ],
      localNotes = List.unmodifiable(localNotes);

  List<Note> get allNotes => [
    for (final week in weeks)
      for (final note in week.notes)
        if (note.note != null) note,
    for (final note in localNotes)
      if (note.note != null) note,
  ];

  List<Note> notesFor(String? subject) {
    if (subject == null) return allNotes;
    return [
      for (final note in allNotes)
        if (canonicalSubject(note.matiere) == subject) note,
    ];
  }

  List<String> get subjects {
    final values = <String>{
      for (final note in allNotes)
        if (canonicalSubject(note.matiere).isNotEmpty)
          canonicalSubject(note.matiere),
    }.toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<String> get weekLabels => [for (final week in weeks) week.label];

  double? _average(Iterable<Note> notes) {
    final values = [
      for (final note in notes)
        if (note.note != null) note.note!,
    ];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double? averageForWeek(WeekNotes week, {String? subject}) {
    if (subject == null) return _average(week.notes);
    return _average(
      week.notes.where((note) => canonicalSubject(note.matiere) == subject),
    );
  }

  double subjectAverage(String subject) => _average(notesFor(subject)) ?? 0;

  List<double?> weeklySeries({String? subject}) => [
    for (final week in weeks) averageForWeek(week, subject: subject),
  ];

  List<({String label, double moyenne})> weeklyAverages({String? subject}) => [
    for (final week in weeks)
      if (averageForWeek(week, subject: subject) case final average?)
        (label: week.label, moyenne: average),
  ];

  double? simpleAverage({String? subject}) => _average(notesFor(subject));

  /// Cinq tranches de 4 points : 0–4, 4–8, 8–12, 12–16, 16–20.
  List<int> distribution({String? subject}) {
    final counts = List<int>.filled(5, 0);
    for (final note in notesFor(subject)) {
      counts[gradeBucket(note.note)!]++;
    }
    return counts;
  }

  /// Moyenne et écart type de la distribution de classe, calculés à partir
  /// des informations fournies par le portail pour les notes affichées.
  ({double moyenne, double ecartType})? normalDistribution({String? subject}) {
    final notes = [
      for (final note in notesFor(subject))
        if (note.moyenne != null &&
            note.ecartType != null &&
            note.ecartType! > 0)
          note,
    ];
    if (notes.isEmpty) return null;
    final moyenne =
        notes.map((note) => note.moyenne!).reduce((a, b) => a + b) /
        notes.length;
    var variance = 0.0;
    for (final note in notes) {
      final ecart = note.moyenne! - moyenne;
      variance += note.ecartType! * note.ecartType! + ecart * ecart;
    }
    variance /= notes.length;
    final ecartType = math.sqrt(variance);
    if (!ecartType.isFinite || ecartType <= 0) return null;
    return (moyenne: moyenne, ecartType: ecartType);
  }

  ({double sum, double weight}) _weightedTotals(
    Map<String, double> coefficients,
  ) {
    var sum = 0.0;
    var weight = 0.0;
    for (final subject in subjects) {
      final notes = notesFor(subject);
      if (notes.isEmpty) continue;
      final coefficient = coefficients[subject] ?? 1;
      if (coefficient <= 0) continue;
      sum += coefficient * _average(notes)!;
      weight += coefficient;
    }
    return (sum: sum, weight: weight);
  }

  double? weightedAverage(Map<String, double> coefficients) {
    final totals = _weightedTotals(coefficients);
    if (totals.weight <= 0) return null;
    return totals.sum / totals.weight;
  }

  /// Note nécessaire dans [subject] pour atteindre [target] de moyenne
  /// pondérée. Peut sortir de 0–20 : l'écran appelant explique alors que
  /// l'objectif est déjà atteint ou hors de portée.
  double? requiredGrade({
    required String subject,
    required double target,
    required Map<String, double> coefficients,
  }) {
    final coefficient = coefficients[subject] ?? 1;
    if (coefficient <= 0) return null;
    final notes = notesFor(subject);
    final totals = _weightedTotals(coefficients);
    if (notes.isEmpty) {
      final weight = totals.weight + coefficient;
      if (weight <= 0) return null;
      return (target * weight - totals.sum) / coefficient;
    }
    final count = notes.length;
    final average = _average(notes)!;
    final numerator =
        target * totals.weight - totals.sum + coefficient * average;
    return numerator * (count + 1) / coefficient - count * average;
  }
}

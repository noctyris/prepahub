import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DevoirBucket { overdue, today, tomorrow, thisWeek, later, done }

class Devoir {
  final String id;
  final String titre;
  final String matiere;
  final DateTime echeance;
  final bool fait;
  final DateTime creeLe;

  Devoir({
    required this.id,
    required this.titre,
    required this.matiere,
    required DateTime echeance,
    this.fait = false,
    DateTime? creeLe,
  }) : echeance = DateTime(echeance.year, echeance.month, echeance.day),
       creeLe = creeLe ?? DateTime.now();

  Devoir copyWith({
    String? titre,
    String? matiere,
    DateTime? echeance,
    bool? fait,
  }) => Devoir(
    id: id,
    titre: titre ?? this.titre,
    matiere: matiere ?? this.matiere,
    echeance: echeance ?? this.echeance,
    fait: fait ?? this.fait,
    creeLe: creeLe,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'titre': titre,
    'matiere': matiere,
    'echeance': echeance.toIso8601String(),
    'fait': fait,
    'creeLe': creeLe.toIso8601String(),
  };

  factory Devoir.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString();
    final echeance = DateTime.tryParse(json['echeance']?.toString() ?? '');
    final creeLe = DateTime.tryParse(json['creeLe']?.toString() ?? '');
    return Devoir(
      id: rawId == null || rawId.isEmpty
          ? DateTime.now().microsecondsSinceEpoch.toString()
          : rawId,
      titre: json['titre']?.toString().trim() ?? '',
      matiere: json['matiere']?.toString().trim() ?? '',
      echeance: echeance ?? DateTime.now(),
      fait: json['fait'] == true,
      creeLe: creeLe,
    );
  }

  DevoirBucket bucket(DateTime now) {
    if (fait) return DevoirBucket.done;
    final today = DateTime(now.year, now.month, now.day);
    final days = daysBetween(today, echeance);
    if (days < 0) return DevoirBucket.overdue;
    if (days == 0) return DevoirBucket.today;
    if (days == 1) return DevoirBucket.tomorrow;
    if (days <= 7 - today.weekday) return DevoirBucket.thisWeek;
    return DevoirBucket.later;
  }
}

class DevoirDraft {
  final String? titre;
  final String? matiere;

  const DevoirDraft({this.titre, this.matiere});
}

int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

String _fold(String value) {
  var result = value.toLowerCase();
  const accents = {
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
  for (final entry in accents.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Un cours de sport ou un DS ne déclenche pas la suggestion de fin de cours.
bool isInstructiveMatiere(String matiere) {
  final folded = _fold(matiere);
  if (folded.isEmpty) return false;
  final words = folded.split(' ');
  const excludedWords = {
    'eps',
    'sport',
    'ds',
    'controle',
    'controles',
    'examen',
    'examens',
  };
  if (words.any(excludedWords.contains)) return false;
  if (folded.contains('devoir surveille')) return false;
  if (folded.contains('education physique')) return false;
  return true;
}

class DevoirsStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/devoirs.json');
  }

  static String encode(List<Devoir> devoirs) =>
      jsonEncode([for (final devoir in devoirs) devoir.toJson()]);

  static List<Devoir> decode(String source) {
    final data = jsonDecode(source);
    if (data is! List) {
      throw const FormatException('Le fichier des devoirs est invalide');
    }
    return [
      for (final item in data)
        if (item is Map) Devoir.fromJson(Map<String, dynamic>.from(item)),
    ];
  }

  static Future<List<Devoir>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      return decode(await file.readAsString());
    } catch (_) {
      try {
        await file.rename('${file.path}.bak');
      } catch (_) {}
      return [];
    }
  }

  static Future<void> save(List<Devoir> devoirs) async {
    final file = await _file();
    await file.writeAsString(encode(devoirs), flush: true);
  }
}

class DevoirSettings {
  final bool eveningEnabled;
  final bool endOfClassEnabled;
  final int eveningHour;
  final int eveningMinute;

  const DevoirSettings({
    required this.eveningEnabled,
    required this.endOfClassEnabled,
    required this.eveningHour,
    required this.eveningMinute,
  });

  static const defaults = DevoirSettings(
    eveningEnabled: true,
    endOfClassEnabled: true,
    eveningHour: 18,
    eveningMinute: 30,
  );

  DevoirSettings copyWith({
    bool? eveningEnabled,
    bool? endOfClassEnabled,
    int? eveningHour,
    int? eveningMinute,
  }) => DevoirSettings(
    eveningEnabled: eveningEnabled ?? this.eveningEnabled,
    endOfClassEnabled: endOfClassEnabled ?? this.endOfClassEnabled,
    eveningHour: eveningHour ?? this.eveningHour,
    eveningMinute: eveningMinute ?? this.eveningMinute,
  );
}

class DevoirSettingsStore {
  static const _eveningEnabledKey = 'devoirs_rappel_soir_actif';
  static const _endOfClassEnabledKey = 'devoirs_fin_cours_actif';
  static const _eveningHourKey = 'devoirs_rappel_soir_heure';
  static const _eveningMinuteKey = 'devoirs_rappel_soir_minute';

  static Future<DevoirSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return DevoirSettings(
        eveningEnabled:
            prefs.getBool(_eveningEnabledKey) ??
            DevoirSettings.defaults.eveningEnabled,
        endOfClassEnabled:
            prefs.getBool(_endOfClassEnabledKey) ??
            DevoirSettings.defaults.endOfClassEnabled,
        eveningHour:
            (prefs.getInt(_eveningHourKey) ??
                    DevoirSettings.defaults.eveningHour)
                .clamp(0, 23)
                .toInt(),
        eveningMinute:
            (prefs.getInt(_eveningMinuteKey) ??
                    DevoirSettings.defaults.eveningMinute)
                .clamp(0, 59)
                .toInt(),
      );
    } catch (_) {
      return DevoirSettings.defaults;
    }
  }

  static Future<void> save(DevoirSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_eveningEnabledKey, settings.eveningEnabled);
    await prefs.setBool(_endOfClassEnabledKey, settings.endOfClassEnabled);
    await prefs.setInt(_eveningHourKey, settings.eveningHour);
    await prefs.setInt(_eveningMinuteKey, settings.eveningMinute);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'api/parse.dart';

class EDTPage extends StatefulWidget {
  const EDTPage({super.key});

  @override
  State<EDTPage> createState() => _EDTPageState();
}

class _EDTPageState extends State<EDTPage> {
  String wom = DateTime.now().isoWeekNumber.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Emploi du temps')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Semaine n°$wom'),
            ),
          ),
        ],
      ),
    );
  }
}

extension DateTimeExtension on DateTime {
  int get isoWeekNumber {
    final thursday = add(Duration(days: 4 - weekday));

    final jan4 = DateTime.utc(thursday.year, 1, 4);
    final firstThursday = jan4.add(Duration(days: 4 - jan4.weekday));

    return 1 + thursday.difference(firstThursday).inDays ~/ 7;
  }
}

Cours _fromJson(Map<String, dynamic> j) => Cours(
  matiere: (j['matiere'] as String?) ?? '',
  jour: (j['jour'] as num?)?.toInt() ?? 1,
  heureDebut: (j['heureDebut'] as String?) ?? '08:00',
  heureFin: (j['heureFin'] as String?) ?? '10:00',
  restrictions: (j['restrictions'] as num?)?.toInt() ?? 0,
  prof: (j['prof'] as String?) ?? '',
  salle: (j['salle'] as String?) ?? '',
  semestre: (j['semestre'] as num?)?.toInt() ?? 1,
);

Map<String, dynamic> _toJson(Cours c) => {
  'matiere': c.matiere,
  'jour': c.jour,
  'heureDebut': c.heureDebut,
  'heureFin': c.heureFin,
  'restrictions': c.restrictions,
  'prof': c.prof,
  'salle': c.salle,
  'semestre': c.semestre,
};

class EdtStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/edt.json');
  }

  static Future<List<Cours>> load() async {
    final f = await _file();
    if (!await f.exists()) return [];
    try {
      final data = jsonDecode(await f.readAsString()) as List;
      return [
        for (final e in data) _fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (_) {
      try {
        await f.rename('${f.path}.bak');
      } catch (_) {}
      return [];
    }
  }

  static Future<void> save(List<Cours> cours) async {
    final f = await _file();
    await f.writeAsString(
      jsonEncode([for (final c in cours) _toJson(c)]),
      flush: true,
    );
  }
}

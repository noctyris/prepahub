import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/parse.dart';
import 'colloscope.dart';

const _jours = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

const _mois = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _two(int n) => n.toString().padLeft(2, '0');

String _formatTime(TimeOfDay t) => '${_two(t.hour)}h${_two(t.minute)}';

String _displayTime(String raw) {
  final parts = raw.replaceAll('h', ':').split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return '${_two(h)}h${_two(m)}';
}

int _minutes(String raw) {
  final parts = raw.replaceAll('h', ':').split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return h * 60 + m;
}

TimeOfDay _parseTime(String raw) {
  final parts = raw.replaceAll('h', ':').split(':');
  return TimeOfDay(
    hour: int.tryParse(parts.first) ?? 8,
    minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
  );
}

DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class EDTPage extends StatefulWidget {
  const EDTPage({super.key});

  @override
  State<EDTPage> createState() => _EDTPageState();
}

class _EDTPageState extends State<EDTPage> {
  static const _prefSemestre = 'edt_semestre';

  List<Cours>? _cours;
  List<Colle>? _colles;
  DateTime _monday = _mondayOf(DateTime.now());
  int _semestre = _defaultSemestre(DateTime.now());

  static int _defaultSemestre(DateTime d) =>
      d.month >= 8 || d.month == 1 ? 1 : 2;

  String get _semestreLabel => _semestre == 1 ? '1er semestre' : '2e semestre';

  bool get _isCurrentWeek => _monday == _mondayOf(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var semestre = _defaultSemestre(DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      semestre = prefs.getInt(_prefSemestre) ?? semestre;
    } catch (_) {}
    List<Cours> cours;
    List<Colle> colles;
    try {
      cours = await EdtStore.load();
    } catch (_) {
      cours = [];
    }
    try {
      colles = await ColloscopeStore.load();
    } catch (_) {
      colles = [];
    }
    if (!mounted) return;
    setState(() {
      _semestre = semestre;
      _cours = cours;
      _colles = colles;
    });
  }

  Future<void> _saveCours(List<Cours> next) async {
    setState(() => _cours = next);
    try {
      await EdtStore.save(next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossible d'enregistrer l'emploi du temps"),
        ),
      );
    }
  }

  Future<void> _editCours([Cours? old]) async {
    final res = await showModalBottomSheet<Cours>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _CoursForm(
        initial: old,
        semestre: _semestre,
        onDelete: old == null ? null : () => _deleteCours(old),
      ),
    );
    if (res == null || !mounted) return;
    final list = [...(_cours ?? const <Cours>[])];
    if (old != null) list.remove(old);
    list.add(res);
    await _saveCours(list);
  }

  Future<void> _deleteCours(Cours c) async {
    await _saveCours([...(_cours ?? const <Cours>[])]..remove(c));
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(
      SnackBar(
        content: Text('Cours de ${c.matiere} supprimé'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => _saveCours([...(_cours ?? const <Cours>[]), c]),
        ),
      ),
    );
  }

  Future<void> _chooseSemestre(int semestre) async {
    if (semestre == _semestre) return;
    final label = semestre == 1 ? '1er semestre' : '2e semestre';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Passer au $label ?'),
        content: Text(
          "L'emploi du temps affiché sera celui du $label. "
          'Tu pourras revenir en arrière depuis le menu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Changer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _semestre = semestre);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefSemestre, semestre);
    } catch (_) {}
  }

  void _shiftWeek(int weeks) {
    setState(() {
      _monday = DateTime(_monday.year, _monday.month, _monday.day + 7 * weeks);
    });
  }

  void _goToCurrentWeek() {
    setState(() => _monday = _mondayOf(DateTime.now()));
  }

  Future<void> _openColles() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ColloscopePage()));
    if (!mounted) return;
    List<Colle> colles;
    try {
      colles = await ColloscopeStore.load();
    } catch (_) {
      colles = [];
    }
    if (!mounted) return;
    setState(() => _colles = colles);
  }

  List<Cours> _weekCours() => [
    for (final c in _cours ?? const <Cours>[])
      if (c.semestre == _semestre && c.appliesToWeek(_monday.isoWeekNumber)) c,
  ];

  List<Colle> _weekColles() => [
    for (final c in _colles ?? const <Colle>[])
      if (_mondayOf(c.date) == _monday) c,
  ];

  @override
  Widget build(BuildContext context) {
    final loading = _cours == null || _colles == null;
    final cours = _weekCours();
    final colles = _weekColles();
    final hasEntries = cours.isNotEmpty || colles.isNotEmpty;
    final semesterHasCours = (_cours ?? const <Cours>[]).any(
      (c) => c.semestre == _semestre,
    );

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCours(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un cours'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Emploi du temps'),
            actions: [
              if (!_isCurrentWeek)
                IconButton(
                  tooltip: 'Revenir à cette semaine',
                  icon: const Icon(Icons.today),
                  onPressed: _goToCurrentWeek,
                ),
              IconButton(
                tooltip: 'Planning des khôlles',
                icon: const Icon(Icons.record_voice_over_outlined),
                onPressed: _openColles,
              ),
              PopupMenuButton<int>(
                tooltip: 'Semestre',
                onSelected: _chooseSemestre,
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                    value: 1,
                    checked: _semestre == 1,
                    child: const Text('1er semestre'),
                  ),
                  CheckedPopupMenuItem(
                    value: 2,
                    checked: _semestre == 2,
                    child: const Text('2e semestre'),
                  ),
                ],
              ),
            ],
          ),
          SliverToBoxAdapter(child: _weekHeader()),
          if (loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!hasEntries)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyWeek(hasCours: semesterHasCours),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverList.list(children: _agenda(cours, colles)),
            ),
        ],
      ),
    );
  }

  Widget _weekHeader() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sunday = DateTime(_monday.year, _monday.month, _monday.day + 6);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card.filled(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Semaine précédente',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shiftWeek(-1),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Semaine ${_monday.isoWeekNumber}',
                      style: tt.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_monday.day} ${_mois[_monday.month - 1]} – '
                      '${sunday.day} ${_mois[sunday.month - 1]}',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$_semestreLabel${_isCurrentWeek ? ' · cette semaine' : ''}',
                      style: tt.labelMedium?.copyWith(color: cs.primary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Semaine suivante',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shiftWeek(1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _agenda(List<Cours> cours, List<Colle> colles) {
    final now = DateTime.now();
    final sections = <Widget>[];

    for (var jour = 1; jour <= 7; jour++) {
      final date = DateTime(
        _monday.year,
        _monday.month,
        _monday.day + jour - 1,
      );
      final entries = <_Slot>[
        for (final c in cours)
          if (c.jour == jour) _Slot.cours(c),
        for (final c in colles)
          if (c.date.weekday == jour) _Slot.colle(c),
      ]..sort((a, b) => a.minutes.compareTo(b.minutes));
      if (entries.isEmpty) continue;

      sections.add(
        _DaySection(
          date: date,
          isToday: _sameDay(date, now),
          entries: entries,
          onEdit: _editCours,
          onColles: _openColles,
        ),
      );
    }
    return sections;
  }
}

class _Slot {
  final Cours? cours;
  final Colle? colle;

  _Slot.cours(this.cours) : colle = null;
  _Slot.colle(this.colle) : cours = null;

  int get minutes => cours != null
      ? _minutes(cours!.heureDebut)
      : colle!.date.hour * 60 + colle!.date.minute;
}

class _DaySection extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final List<_Slot> entries;
  final ValueChanged<Cours> onEdit;
  final VoidCallback onColles;

  const _DaySection({
    required this.date,
    required this.isToday,
    required this.entries,
    required this.onEdit,
    required this.onColles,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_jours[date.weekday - 1]} ${date.day} '
                    '${_mois[date.month - 1]}',
                    style: tt.titleSmall?.copyWith(
                      color: isToday ? cs.primary : null,
                    ),
                  ),
                ),
                if (isToday)
                  Text(
                    'Aujourd’hui',
                    style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  if (entries[i].cours != null)
                    _CoursTile(cours: entries[i].cours!, onEdit: onEdit)
                  else
                    _KholleTile(colle: entries[i].colle!, onTap: onColles),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoursTile extends StatelessWidget {
  final Cours cours;
  final ValueChanged<Cours> onEdit;

  const _CoursTile({required this.cours, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final details = [
      if (cours.salle.isNotEmpty) 'Salle ${cours.salle}',
      if (cours.prof.isNotEmpty) cours.prof,
    ].join(' · ');

    return ListTile(
      onTap: () => onEdit(cours),
      leading: _TimeBadge(
        start: _displayTime(cours.heureDebut),
        end: _displayTime(cours.heureFin),
        background: cs.secondaryContainer,
        foreground: cs.onSecondaryContainer,
      ),
      title: Text(cours.matiere, style: tt.titleMedium),
      subtitle: details.isEmpty ? null : Text(details),
    );
  }
}

class _KholleTile extends StatelessWidget {
  final Colle colle;
  final VoidCallback onTap;

  const _KholleTile({required this.colle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = colle.date;
    final details = [
      if (colle.prof.isNotEmpty) colle.prof,
      if (colle.salle.isNotEmpty) 'Salle ${colle.salle}',
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      leading: _TimeBadge(
        start: '${_two(d.hour)}h${_two(d.minute)}',
        background: cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              colle.matiere,
              overflow: TextOverflow.ellipsis,
              style: tt.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Khôlle',
              style: tt.labelSmall?.copyWith(color: cs.onTertiaryContainer),
            ),
          ),
        ],
      ),
      subtitle: details.isEmpty ? null : Text(details),
    );
  }
}

class _TimeBadge extends StatelessWidget {
  final String start;
  final String? end;
  final Color background;
  final Color foreground;

  const _TimeBadge({
    required this.start,
    this.end,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            start,
            style: tt.labelLarge?.copyWith(color: foreground, height: 1.1),
          ),
          if (end != null) ...[
            const SizedBox(height: 2),
            Text(
              end!,
              style: tt.labelSmall?.copyWith(color: foreground, height: 1.1),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyWeek extends StatelessWidget {
  final bool hasCours;

  const _EmptyWeek({required this.hasCours});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasCours
                  ? Icons.event_busy_rounded
                  : Icons.calendar_month_rounded,
              size: 64,
              color: cs.primary,
            ),
            const SizedBox(height: 16),
            Text(
              hasCours ? 'Rien cette semaine' : 'Aucun cours ce semestre',
              textAlign: TextAlign.center,
              style: tt.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              hasCours
                  ? 'Aucun cours ni khôlle pour cette semaine.'
                  : 'Ajoute tes cours avec le bouton « Ajouter un cours », '
                        'et tes khôlles via le bouton en haut.',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoursForm extends StatefulWidget {
  final Cours? initial;
  final int semestre;
  final VoidCallback? onDelete;

  const _CoursForm({this.initial, required this.semestre, this.onDelete});

  @override
  State<_CoursForm> createState() => _CoursFormState();
}

class _CoursFormState extends State<_CoursForm> {
  late final TextEditingController _matiere;
  late final TextEditingController _prof;
  late final TextEditingController _salle;
  late int _jour;
  late TimeOfDay _debut;
  late TimeOfDay _fin;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _matiere = TextEditingController(text: i?.matiere ?? '');
    _prof = TextEditingController(text: i?.prof ?? '');
    _salle = TextEditingController(text: i?.salle ?? '');
    final jour = i?.jour ?? DateTime.now().weekday;
    _jour = jour >= 1 && jour <= 7 ? jour : 1;
    _debut = i == null
        ? const TimeOfDay(hour: 8, minute: 0)
        : _parseTime(i.heureDebut);
    _fin = i == null
        ? const TimeOfDay(hour: 10, minute: 0)
        : _parseTime(i.heureFin);
  }

  @override
  void dispose() {
    _matiere.dispose();
    _prof.dispose();
    _salle.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool debut}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: debut ? _debut : _fin,
      helpText: debut ? 'Heure de début' : 'Heure de fin',
      cancelText: 'Annuler',
      confirmText: 'OK',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null || !mounted) return;
    setState(() {
      if (debut) {
        _debut = t;
      } else {
        _fin = t;
      }
    });
  }

  void _submit() {
    final matiere = _matiere.text.trim();
    if (matiere.isEmpty) {
      setState(() => _error = 'Indique la matière');
      return;
    }
    if (_fin.hour * 60 + _fin.minute <= _debut.hour * 60 + _debut.minute) {
      setState(() => _error = "L'heure de fin doit suivre l'heure de début");
      return;
    }
    Navigator.pop(
      context,
      Cours(
        matiere: matiere,
        jour: _jour,
        heureDebut: '${_two(_debut.hour)}:${_two(_debut.minute)}',
        heureFin: '${_two(_fin.hour)}:${_two(_fin.minute)}',
        restrictions: widget.initial?.restrictions ?? 0,
        prof: _prof.text.trim(),
        salle: _salle.text.trim(),
        semestre: widget.initial?.semestre ?? widget.semestre,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final editing = widget.initial != null;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            editing ? 'Modifier le cours' : 'Nouveau cours',
            style: tt.headlineSmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _matiere,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: 'Matière',
              prefixIcon: const Icon(Icons.menu_book_outlined),
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _jour,
            decoration: const InputDecoration(
              labelText: 'Jour',
              prefixIcon: Icon(Icons.today_outlined),
              border: OutlineInputBorder(),
            ),
            items: [
              for (var i = 1; i <= 7; i++)
                DropdownMenuItem(value: i, child: Text(_jours[i - 1])),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _jour = v);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(debut: true),
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text('Début ${_formatTime(_debut)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(debut: false),
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text('Fin ${_formatTime(_fin)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _prof,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Professeur (facultatif)',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _salle,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Salle (facultatif)',
              prefixIcon: Icon(Icons.meeting_room_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (widget.onDelete != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDelete!();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer'),
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _submit,
                child: Text(editing ? 'Enregistrer' : 'Ajouter'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

extension DateTimeExtension on DateTime {
  int get isoWeekNumber {
    final thursday = DateTime.utc(year, month, day + 4 - weekday);
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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'api/parse.dart';
import 'subjects.dart';

const _joursCourts = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
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
String _hhmm(DateTime d) => '${_two(d.hour)}h${_two(d.minute)}';
String _dayMonth(DateTime d) => '${d.day} ${_mois[d.month - 1]}';
String _fullDate(DateTime d) =>
    '${_joursCourts[d.weekday - 1]} ${_dayMonth(d)} ${d.year}';

String _icsEscape(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\n', '\\n');

String _icsDate(DateTime d) =>
    '${d.year}${_two(d.month)}${_two(d.day)}T'
    '${_two(d.hour)}${_two(d.minute)}00';

String _icsUtc(DateTime d) {
  final utc = d.toUtc();
  return '${utc.year}${_two(utc.month)}${_two(utc.day)}T'
      '${_two(utc.hour)}${_two(utc.minute)}${_two(utc.second)}Z';
}

/// Construit un calendrier iCalendar des khôlles, importable dans Google
/// Agenda, Apple Calendrier ou Thunderbird.
String buildCollesIcs(List<Colle> colles) {
  final stamp = _icsUtc(DateTime.now());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//PrepaHub//Kholles//FR',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
  ];
  for (final colle in colles) {
    final salle = colle.salle.trim();
    final prof = colle.prof.trim();
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${_icsDate(colle.date)}-'
          '${colle.matiere.replaceAll(RegExp('[^A-Za-z0-9]+'), '-')}@prepahub',
      'DTSTAMP:$stamp',
      'DTSTART:${_icsDate(colle.date)}',
      'DTEND:${_icsDate(colle.date.add(const Duration(hours: 1)))}',
      'SUMMARY:${_icsEscape('Khôlle – ${colle.matiere}')}',
      if (salle.isNotEmpty) 'LOCATION:${_icsEscape(salle)}',
      if (prof.isNotEmpty) 'DESCRIPTION:${_icsEscape('Professeur : $prof')}',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.join('\r\n')}\r\n';
}

/// Matières des khôlles déjà passées, regroupées (TD/TP/cours) et triées.
/// Si aucune khôlle n'est passée, toutes les khôlles servent de repli.
List<String> pastColleSubjects(Iterable<Colle> colles, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final past = [
    for (final colle in colles)
      if (colle.date.isBefore(reference)) colle,
  ];
  final source = past.isNotEmpty ? past : colles;
  final subjects = <String>{
    for (final colle in source)
      if (canonicalSubject(colle.matiere).isNotEmpty)
        canonicalSubject(colle.matiere),
  }.toList();
  subjects.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return subjects;
}

enum _CollePeriod { upcoming, all, past }

DateTime _monday(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

Map<String, dynamic> _toJson(Colle c) => {
  'matiere': c.matiere,
  'date': c.date.toIso8601String(),
  'prof': c.prof,
  'salle': c.salle,
};

Colle _fromJson(Map<String, dynamic> j) => Colle(
  matiere: j['matiere'] as String,
  date: DateTime.parse(j['date'] as String),
  prof: (j['prof'] as String?) ?? '',
  salle: (j['salle'] as String?) ?? '',
);

class ColloscopeStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/colloscope.json');
  }

  static Future<List<Colle>> load() async {
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

  static String encode(List<Colle> colles) =>
      const JsonEncoder.withIndent('  ')
          .convert([for (final c in colles) _toJson(c)]);

  static List<Colle> decode(String raw) {
    final data = jsonDecode(raw) as List;
    return [
      for (final e in data) _fromJson(Map<String, dynamic>.from(e as Map)),
    ];
  }

  static Future<void> save(List<Colle> colles) async {
    final f = await _file();
    await f.writeAsString(
      jsonEncode([for (final c in colles) _toJson(c)]),
      flush: true,
    );
  }
}

class ColloscopePage extends StatefulWidget {
  final VoidCallback? onChanged;

  const ColloscopePage({super.key, this.onChanged});

  @override
  State<ColloscopePage> createState() => _ColloscopePageState();
}

class _ColloscopePageState extends State<ColloscopePage> {
  List<Colle>? _colles;
  final TextEditingController _search = TextEditingController();
  _CollePeriod _period = _CollePeriod.upcoming;
  String? _filterMatiere;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Colle> _sorted(List<Colle> l) =>
      [...l]..sort((a, b) => a.date.compareTo(b.date));

  Future<void> _load() async {
    List<Colle> c;
    try {
      c = await ColloscopeStore.load();
    } catch (_) {
      c = [];
    }
    if (!mounted) return;
    setState(() => _colles = _sorted(c));
  }

  void _snack(String msg, {SnackBarAction? action}) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  Future<void> _commit(List<Colle> next) async {
    setState(() => _colles = _sorted(next));
    try {
      await ColloscopeStore.save(_colles!);
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) _snack("Impossible d'enregistrer les khôlles");
    }
  }

  Future<void> _export() async {
    final colles = _colles ?? [];
    if (colles.isEmpty) {
      _snack('Rien à exporter');
      return;
    }
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Exporter les khôlles',
        fileName: 'kholles.json',
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(ColloscopeStore.encode(colles))),
      );
      if (uri != null && mounted) _snack('Khôlles exportées');
    } catch (_) {
      if (mounted) _snack("Export impossible");
    }
  }

  Future<void> _exportIcs() async {
    final colles = _colles ?? [];
    if (colles.isEmpty) {
      _snack('Rien à exporter');
      return;
    }
    try {
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Exporter le calendrier des khôlles',
        fileName: 'kholles.ics',
        mimeType: 'text/calendar',
        bytes: Uint8List.fromList(utf8.encode(buildCollesIcs(colles))),
      );
      if (uri != null && mounted) _snack('Calendrier exporté');
    } catch (_) {
      if (mounted) _snack('Export impossible');
    }
  }

  Future<void> _import() async {
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Importer les khôlles',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return;
      final incoming = ColloscopeStore.decode(
        utf8.decode(await file.readAsBytes()),
      );

      final current = [..._colles ?? <Colle>[]];
      bool same(Colle a, Colle b) => a.matiere == b.matiere && a.date == b.date;
      var added = 0;
      for (final c in incoming) {
        if (!current.any((x) => same(x, c))) {
          current.add(c);
          added++;
        }
      }
      await _commit(current);
      if (mounted) {
        _snack(
          added == 0
              ? 'Aucune nouvelle khôlle'
              : '$added khôlle${added > 1 ? 's' : ''} importée${added > 1 ? 's' : ''}',
        );
      }
    } catch (_) {
      if (mounted) _snack('Fichier invalide');
    }
  }

  Future<void> _edit([Colle? old]) async {
    final res = await showModalBottomSheet<Colle>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _ColleForm(
        initial: old,
        onDelete: old == null ? null : () => _delete(old),
      ),
    );
    if (res == null || !mounted) return;
    final list = [..._colles!];
    if (old != null) list.remove(old);
    list.add(res);
    await _commit(list);
  }

  Future<void> _delete(Colle c) async {
    await _commit([..._colles!]..remove(c));
    if (!mounted) return;
    _snack(
      'Khôlle de ${c.matiere} supprimée',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => _commit([..._colles!, c]),
      ),
    );
  }

  List<SemaineColles> _weeks(List<Colle> colles) {
    final byWeek = <DateTime, List<Colle>>{};
    for (final c in colles) {
      byWeek.putIfAbsent(_monday(c.date), () => []).add(c);
    }
    final mondays = byWeek.keys.toList()..sort();
    return [
      for (final m in mondays)
        SemaineColles(
          debut: _dayMonth(m),
          fin: _dayMonth(DateTime(m.year, m.month, m.day + 6)),
          colles: byWeek[m]!,
        ),
    ];
  }

  List<String> get _subjectOptions {
    final values = <String>{
      for (final colle in _colles ?? const <Colle>[])
        if (canonicalSubject(colle.matiere).isNotEmpty)
          canonicalSubject(colle.matiere),
    }.toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<Colle> _filtered(List<Colle> colles) {
    final query = foldText(_search.text);
    return [
      for (final colle in colles)
        if ((_filterMatiere == null ||
                canonicalSubject(colle.matiere) == _filterMatiere) &&
            (query.isEmpty ||
                foldText('${colle.matiere} ${colle.prof} ${colle.salle}')
                    .contains(query)))
          colle,
    ];
  }

  Widget _filters(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Rechercher une khôlle',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      setState(() {});
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<_CollePeriod>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: _CollePeriod.upcoming, label: Text('À venir')),
            ButtonSegment(value: _CollePeriod.all, label: Text('Toutes')),
            ButtonSegment(value: _CollePeriod.past, label: Text('Passées')),
          ],
          selected: {_period},
          onSelectionChanged: (selection) =>
              setState(() => _period = selection.first),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('Toutes les matières'),
                  visualDensity: VisualDensity.compact,
                  selected: _filterMatiere == null,
                  onSelected: (_) => setState(() => _filterMatiere = null),
                ),
              ),
              for (final subject in _subjectOptions)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(subject),
                    visualDensity: VisualDensity.compact,
                    selected: _filterMatiere == subject,
                    onSelected: (_) => setState(() => _filterMatiere = subject),
                  ),
                ),
            ],
          ),
        ),
        if (_filterMatiere != null || _search.text.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                _search.clear();
                setState(() => _filterMatiere = null);
              },
              style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              child: const Text('Réinitialiser les filtres'),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colles = _colles;
    final visible = colles == null ? const <Colle>[] : _filtered(colles);
    final content = visible.isEmpty ? const <Widget>[] : _content(visible);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Khôlles'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Plus',
                onSelected: (v) {
                  if (v == 'export') {
                    _export();
                  } else if (v == 'ics') {
                    _exportIcs();
                  } else {
                    _import();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.upload_file_outlined),
                      title: Text('Exporter en JSON'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'ics',
                    child: ListTile(
                      leading: Icon(Icons.event_available_outlined),
                      title: Text('Exporter en calendrier (.ics)'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      leading: Icon(Icons.download_outlined),
                      title: Text('Importer'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (colles == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (colles.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: _Empty())
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(child: _filters(context)),
            ),
            if (content.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Aucune khôlle dans cette vue',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                sliver: SliverList.list(children: content),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _content(List<Colle> colles) {
    final now = DateTime.now();
    final upcomingColles = [
      for (final c in colles)
        if (!c.date.isBefore(now)) c,
    ];
    final pastColles = [
      for (final c in colles)
        if (c.date.isBefore(now)) c,
    ];
    final upcomingWeeks = _weeks(upcomingColles);
    final pastWeeks = _weeks(pastColles).reversed.toList();

    Colle? next;
    for (final c in upcomingColles) {
      if (!c.date.isBefore(now)) {
        next = c;
        break;
      }
    }

    Widget section(SemaineColles w) => _WeekSection(
      week: w,
      now: now,
      next: next,
      onTap: _edit,
      onDelete: _delete,
    );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    switch (_period) {
      case _CollePeriod.past:
        return [for (final w in pastWeeks) section(w)];
      case _CollePeriod.all:
        return [
          for (final w in upcomingWeeks) section(w),
          if (pastWeeks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Text(
                'Khôlles passées',
                style: tt.titleSmall?.copyWith(color: cs.primary),
              ),
            ),
            for (final w in pastWeeks) section(w),
          ],
        ];
      case _CollePeriod.upcoming:
        return [
          for (final w in upcomingWeeks) section(w),
          if (pastWeeks.isNotEmpty)
            ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              title: const Text('Khôlles passées'),
              subtitle: Text(
                '${pastWeeks.fold<int>(0, (n, w) => n + w.colles.length)} '
                'au total',
              ),
              childrenPadding: const EdgeInsets.only(top: 8),
              children: [for (final w in pastWeeks) section(w)],
            ),
        ];
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

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
            Icon(Icons.event_note_rounded, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text('Aucune khôlle', style: tt.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Recopie ton planning de khôlles avec le bouton « Ajouter ».',
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekSection extends StatelessWidget {
  final SemaineColles week;
  final DateTime now;
  final Colle? next;
  final ValueChanged<Colle> onTap;
  final ValueChanged<Colle> onDelete;

  const _WeekSection({
    required this.week,
    required this.now,
    required this.next,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final thisWeek = _monday(week.colles.first.date) == _monday(now);

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
                    'Semaine du ${week.debut} au ${week.fin}',
                    style: tt.titleSmall?.copyWith(color: cs.primary),
                  ),
                ),
                if (thisWeek)
                  Text(
                    'Cette semaine',
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
                for (var i = 0; i < week.colles.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _ColleTile(
                    colle: week.colles[i],
                    isNext: identical(week.colles[i], next),
                    isPast: week.colles[i].date.isBefore(now),
                    onTap: onTap,
                    onDelete: onDelete,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColleTile extends StatelessWidget {
  final Colle colle;
  final bool isNext;
  final bool isPast;
  final ValueChanged<Colle> onTap;
  final ValueChanged<Colle> onDelete;

  const _ColleTile({
    required this.colle,
    required this.isNext,
    required this.isPast,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = colle.date;

    final Color badgeBg;
    final Color badgeFg;
    if (isPast) {
      badgeBg = cs.surfaceContainerHighest;
      badgeFg = cs.onSurfaceVariant;
    } else if (isNext) {
      badgeBg = cs.primaryContainer;
      badgeFg = cs.onPrimaryContainer;
    } else {
      badgeBg = cs.secondaryContainer;
      badgeFg = cs.onSecondaryContainer;
    }

    final details = [
      _hhmm(d),
      if (colle.prof.isNotEmpty) colle.prof,
      if (colle.salle.isNotEmpty) 'salle ${colle.salle}',
    ].join(' · ');

    return Dismissible(
      key: ObjectKey(colle),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) => onDelete(colle),
      child: ListTile(
        onTap: () => onTap(colle),
        leading: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _joursCourts[d.weekday - 1],
                style: tt.labelSmall?.copyWith(color: badgeFg, height: 1.1),
              ),
              Text(
                '${d.day}',
                style: tt.titleMedium?.copyWith(color: badgeFg, height: 1.1),
              ),
            ],
          ),
        ),
        title: Text(
          colle.matiere,
          style: tt.titleMedium?.copyWith(
            color: isPast ? cs.onSurfaceVariant : null,
          ),
        ),
        subtitle: Text(details),
        trailing: isNext
            ? Text(
                'Prochaine',
                style: tt.labelMedium?.copyWith(color: cs.primary),
              )
            : null,
      ),
    );
  }
}

class _ColleForm extends StatefulWidget {
  final Colle? initial;
  final VoidCallback? onDelete;
  const _ColleForm({this.initial, this.onDelete});

  @override
  State<_ColleForm> createState() => _ColleFormState();
}

class _ColleFormState extends State<_ColleForm> {
  late final TextEditingController _matiere;
  late final TextEditingController _prof;
  late final TextEditingController _salle;
  late DateTime _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    final n = DateTime.now();
    _matiere = TextEditingController(text: i?.matiere ?? '');
    _prof = TextEditingController(text: i?.prof ?? '');
    _salle = TextEditingController(text: i?.salle ?? '');
    _date = i?.date ?? DateTime(n.year, n.month, n.day + 1, 17);
  }

  @override
  void dispose() {
    _matiere.dispose();
    _prof.dispose();
    _salle.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Date de la khôlle',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (d == null || !mounted) return;
    setState(
      () => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute),
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Heure de la khôlle',
      cancelText: 'Annuler',
      confirmText: 'OK',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null || !mounted) return;
    setState(
      () => _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        t.hour,
        t.minute,
      ),
    );
  }

  void _submit() {
    final matiere = _matiere.text.trim();
    if (matiere.isEmpty) {
      setState(() => _error = 'Indique la matière');
      return;
    }
    Navigator.pop(
      context,
      Colle(
        matiere: matiere,
        date: _date,
        prof: _prof.text.trim(),
        salle: _salle.text.trim(),
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
            editing ? 'Modifier la khôlle' : 'Nouvelle khôlle',
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
          Row(
            children: [
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(_fullDate(_date)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(_hhmm(_date)),
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

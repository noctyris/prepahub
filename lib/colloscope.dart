import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'api/parse.dart';

const _joursCourts = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _mois = [
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _hhmm(DateTime d) => '${_two(d.hour)}h${_two(d.minute)}';
String _dayMonth(DateTime d) => '${d.day} ${_mois[d.month - 1]}';
String _fullDate(DateTime d) =>
    '${_joursCourts[d.weekday - 1]} ${_dayMonth(d)} ${d.year}';

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

class _Store {
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

  static String encode(List<Colle> colles) => const JsonEncoder.withIndent('  ')
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
  const ColloscopePage({super.key});

  @override
  State<ColloscopePage> createState() => _ColloscopePageState();
}

class _ColloscopePageState extends State<ColloscopePage> {
  List<Colle>? _colles;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Colle> _sorted(List<Colle> l) =>
      [...l]..sort((a, b) => a.date.compareTo(b.date));

  Future<void> _load() async {
    List<Colle> c;
    try {
      c = await _Store.load();
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
      await _Store.save(_colles!);
    } catch (_) {
      if (mounted) _snack("Impossible d'enregistrer le colloscope");
    }
  }

  Future<void> _export() async {
    final colles = _colles ?? [];
    if (colles.isEmpty) {
      _snack('Rien à exporter');
      return;
    }
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Exporter le colloscope',
        fileName: 'colloscope.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(_Store.encode(colles))),
      );
      if (path != null && mounted) _snack('Colloscope exporté');
    } catch (_) {
      if (mounted) _snack("Export impossible");
    }
  }

  Future<void> _import() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      final bytes = res?.files.single.bytes;
      if (bytes == null) return;
      final incoming = _Store.decode(utf8.decode(bytes));

      final current = [..._colles ?? <Colle>[]];
      bool same(Colle a, Colle b) =>
          a.matiere == b.matiere && a.date == b.date;
      var added = 0;
      for (final c in incoming) {
        if (!current.any((x) => same(x, c))) {
          current.add(c);
          added++;
        }
      }
      await _commit(current);
      if (mounted) {
        _snack(added == 0
            ? 'Aucune nouvelle colle'
            : '$added colle${added > 1 ? 's' : ''} importée${added > 1 ? 's' : ''}');
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
      'Colle de ${c.matiere} supprimée',
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

  @override
  Widget build(BuildContext context) {
    final colles = _colles;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Colloscope'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Plus',
                onSelected: (v) => v == 'export' ? _export() : _import(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.upload_file_outlined),
                      title: Text('Exporter'),
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
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              sliver: SliverList.list(children: _content(colles)),
            ),
        ],
      ),
    );
  }

  List<Widget> _content(List<Colle> colles) {
    final now = DateTime.now();
    final weeks = _weeks(colles);
    final upcoming = [
      for (final w in weeks)
        if (w.colles.any((c) => !c.date.isBefore(now))) w,
    ];
    final past = [
      for (final w in weeks)
        if (w.colles.every((c) => c.date.isBefore(now))) w,
    ].reversed.toList();

    Colle? next;
    for (final c in colles) {
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

    return [
      for (final w in upcoming) section(w),
      if (past.isNotEmpty)
        ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: const Text('Colles passées'),
          subtitle: Text(
              '${past.fold<int>(0, (n, w) => n + w.colles.length)} au total'),
          childrenPadding: const EdgeInsets.only(top: 8),
          children: [for (final w in past) section(w)],
        ),
    ];
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
            Text('Aucune colle', style: tt.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Recopie ton colloscope papier avec le bouton « Ajouter ».',
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
                  Text('Cette semaine',
                      style: tt.labelMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
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
              Text(_joursCourts[d.weekday - 1],
                  style: tt.labelSmall?.copyWith(color: badgeFg, height: 1.1)),
              Text('${d.day}',
                  style: tt.titleMedium?.copyWith(color: badgeFg, height: 1.1)),
            ],
          ),
        ),
        title: Text(
          colle.matiere,
          style: tt.titleMedium
              ?.copyWith(color: isPast ? cs.onSurfaceVariant : null),
        ),
        subtitle: Text(details),
        trailing: isNext
            ? Text('Prochaine',
                style: tt.labelMedium?.copyWith(color: cs.primary))
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
      helpText: 'Date de la colle',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (d == null || !mounted) return;
    setState(() => _date = DateTime(d.year, d.month, d.day, _date.hour, _date.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Heure de la colle',
      cancelText: 'Annuler',
      confirmText: 'OK',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null || !mounted) return;
    setState(() => _date = DateTime(_date.year, _date.month, _date.day, t.hour, t.minute));
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
          24, 0, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(editing ? 'Modifier la colle' : 'Nouvelle colle',
              style: tt.headlineSmall),
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

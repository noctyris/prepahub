import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/parse.dart';
import 'app_settings.dart';
import 'colloscope.dart';
import 'devoirs.dart';
import 'edt.dart';
import 'notes_store.dart';

const _jours = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const _mois = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _two(int value) => value.toString().padLeft(2, '0');

String _heure(String raw) {
  final parts = raw.replaceAll('h', ':').split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return '${_two(hour)}h${_two(minute)}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int _minutes(String raw) {
  final parts = raw.replaceAll('h', ':').split(':');
  final hour = int.tryParse(parts.first) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return hour * 60 + minute;
}

class TodayPage extends StatefulWidget {
  final ValueChanged<AppSection> onOpenSection;

  const TodayPage({super.key, required this.onOpenSection});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  bool _loading = true;
  int _semester = defaultEdtSemester(DateTime.now());
  List<Cours> _cours = const [];
  List<Colle> _colles = const [];
  List<Devoir> _devoirs = const [];
  List<Semaine> _weeks = const [];
  List<Note> _localNotes = const [];
  Map<String, int> _colors = const {};

  @override
  void initState() {
    super.initState();
    notesRevision.addListener(_onNotesRevision);
    _load();
  }

  @override
  void dispose() {
    notesRevision.removeListener(_onNotesRevision);
    super.dispose();
  }

  void _onNotesRevision() {
    unawaited(_load());
  }

  Future<void> _load() async {
    final now = DateTime.now();
    var semester = defaultEdtSemester(now);
    try {
      final prefs = await SharedPreferences.getInstance();
      semester = prefs.getInt(edtSemesterPrefKey) ?? semester;
    } catch (_) {}

    List<Cours> cours;
    try {
      cours = await EdtStore.load();
    } catch (_) {
      cours = [];
    }
    List<Colle> colles;
    try {
      colles = await ColloscopeStore.load();
    } catch (_) {
      colles = [];
    }
    List<Devoir> devoirs;
    try {
      devoirs = await DevoirsStore.load();
    } catch (_) {
      devoirs = [];
    }
    final weeks = await NotesStore.loadCache();
    final localNotes = await NotesStore.loadLocalNotes();
    Map<String, int> colors = {};
    try {
      colors = await EdtColorStore.load(cours.map((c) => c.matiere));
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _semester = semester;
      _cours = cours;
      _colles = colles;
      _devoirs = devoirs..sort((a, b) => a.echeance.compareTo(b.echeance));
      _weeks = weeks;
      _localNotes = localNotes;
      _colors = colors;
      _loading = false;
    });
  }

  Color _colorFor(String matiere, ColorScheme cs) {
    final seed = EdtColorStore.seedFor(_colors, matiere);
    return seed == null ? cs.primary : Color(seed);
  }

  List<Cours> get _todayCours {
    final now = DateTime.now();
    return [
      for (final c in _cours)
        if (c.semestre == _semester &&
            c.jour == now.weekday &&
            c.appliesToWeek(now.isoWeekNumber))
          c,
    ]..sort((a, b) => _minutes(a.heureDebut).compareTo(_minutes(b.heureDebut)));
  }

  List<Colle> get _todayColles {
    final now = DateTime.now();
    return [
      for (final c in _colles)
        if (_sameDay(c.date, now)) c,
    ]..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Colle> get _nextColles {
    final now = DateTime.now();
    return [
      for (final c in _colles)
        if (!c.date.isBefore(now)) c,
    ]..sort((a, b) => a.date.compareTo(b.date));
  }

  List<Devoir> get _pending {
    final now = DateTime.now();
    return [
      for (final devoir in _devoirs)
        if (!devoir.fait && devoir.bucket(now) != DevoirBucket.done) devoir,
    ]..sort((a, b) => a.echeance.compareTo(b.echeance));
  }

  List<Note> get _recentNotes {
    final notes = <Note>[
      if (_weeks.isNotEmpty)
        for (final note in _weeks.last.notes)
          if (note.note != null) note,
      for (final note in _localNotes)
        if (note.note != null) note,
    ];
    return notes.reversed.take(4).toList();
  }

  String _dueLabel(Devoir devoir) {
    final now = DateTime.now();
    final days = daysBetween(now, devoir.echeance);
    if (days < 0) return 'En retard';
    if (days == 0) return "Aujourd'hui";
    if (days == 1) return 'Demain';
    return '${devoir.echeance.day} ${_mois[devoir.echeance.month - 1]}';
  }

  String _colleWhen(Colle colle) {
    final now = DateTime.now();
    if (_sameDay(colle.date, now)) return "Aujourd'hui";
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (_sameDay(colle.date, tomorrow)) return 'Demain';
    return '${_jours[colle.date.weekday - 1]} ${colle.date.day} '
        '${_mois[colle.date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final courses = _todayCours;
    final colles = _todayColles;
    final pending = _pending;
    final notes = _recentNotes;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Aujourd'hui"),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_load()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    '${_jours[now.weekday - 1]} ${now.day} '
                    '${_mois[now.month - 1]}',
                    style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Semaine ${now.isoWeekNumber}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatPill(
                        icon: Icons.menu_book_outlined,
                        label: '${courses.length} cours',
                        color: cs.primary,
                      ),
                      _StatPill(
                        icon: Icons.checklist,
                        label:
                            '${pending.length} devoir${pending.length == 1 ? '' : 's'}',
                        color: cs.tertiary,
                      ),
                      _StatPill(
                        icon: Icons.record_voice_over_outlined,
                        label:
                            '${colles.length} khôlle${colles.length == 1 ? '' : 's'}',
                        color: cs.secondary,
                      ),
                    ],
                  ),
                  if (courses.isEmpty &&
                      pending.isEmpty &&
                      colles.isEmpty &&
                      notes.isEmpty)
                    _emptyCard(context),
                  const SizedBox(height: 20),
                  _Section(
                    title: 'Cours',
                    icon: Icons.calendar_today_outlined,
                    action: 'Planning',
                    onAction: () => widget.onOpenSection(AppSection.planning),
                    child: courses.isEmpty
                        ? const _EmptyLine("Pas de cours aujourd'hui")
                        : _coursCard(context, courses),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    title: 'À faire',
                    icon: Icons.checklist,
                    action: 'Devoirs',
                    onAction: () => widget.onOpenSection(AppSection.devoirs),
                    child: pending.isEmpty
                        ? const _EmptyLine('Aucun devoir en attente')
                        : _devoirsCard(context, pending),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    title: 'Khôlles',
                    icon: Icons.record_voice_over_outlined,
                    action: 'Planning',
                    onAction: () => widget.onOpenSection(AppSection.planning),
                    child: _nextColles.isEmpty
                        ? const _EmptyLine('Aucune khôlle à venir')
                        : _collesCard(context, _nextColles),
                  ),
                  const SizedBox(height: 20),
                  _Section(
                    title: 'Dernières notes',
                    icon: Icons.pie_chart_outline,
                    action: 'Notes',
                    onAction: () => widget.onOpenSection(AppSection.notes),
                    child: notes.isEmpty
                        ? const _EmptyLine('Aucune note récente')
                        : _notesCard(context, notes),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _emptyCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      margin: const EdgeInsets.only(top: 16),
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.wb_sunny_outlined, color: cs.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Rien de prévu pour le moment. Bonne journée !',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: cs.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coursCard(BuildContext context, List<Cours> courses) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < courses.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            Builder(
              builder: (context) {
                final cours = courses[i];
                final color = _colorFor(cours.matiere, cs);
                final start = _minutes(cours.heureDebut);
                final end = _minutes(cours.heureFin);
                final inProgress =
                    currentMinutes >= start && currentMinutes < end;
                final details = [
                  if (cours.salle.trim().isNotEmpty) cours.salle,
                  if (cours.prof.trim().isNotEmpty) cours.prof,
                ].join(' · ');
                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.menu_book_outlined, color: color),
                  ),
                  title: Text(
                    cours.matiere,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      '${_heure(cours.heureDebut)} – '
                          '${_heure(cours.heureFin)}',
                      if (details.isNotEmpty) details,
                    ].join(' · '),
                  ),
                  trailing: inProgress
                      ? Text(
                          'En cours',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: color),
                        )
                      : null,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _devoirsCard(BuildContext context, List<Devoir> pending) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < pending.length && i < 4; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            Builder(
              builder: (context) {
                final devoir = pending[i];
                final overdue = devoir.echeance.isBefore(
                  DateTime.now().subtract(const Duration(days: 1)),
                );
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.assignment_outlined,
                    color: overdue ? cs.error : cs.tertiary,
                  ),
                  title: Text(
                    devoir.titre.isEmpty ? 'Sans titre' : devoir.titre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (devoir.matiere.trim().isNotEmpty) devoir.matiere,
                      _dueLabel(devoir),
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpenSection(AppSection.devoirs),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _collesCard(BuildContext context, List<Colle> colles) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < colles.length && i < 4; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            Builder(
              builder: (context) {
                final colle = colles[i];
                final color = _colorFor(colle.matiere, cs);
                final details = [
                  _heure('${_two(colle.date.hour)}:${_two(colle.date.minute)}'),
                  if (colle.salle.trim().isNotEmpty) 'salle ${colle.salle}',
                  if (colle.prof.trim().isNotEmpty) colle.prof,
                ].join(' · ');
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.record_voice_over_outlined, color: color),
                  title: Text(
                    colle.matiere,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('${_colleWhen(colle)} · $details'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpenSection(AppSection.planning),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _notesCard(BuildContext context, List<Note> notes) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < notes.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            Builder(
              builder: (context) {
                final note = notes[i];
                final good =
                    note.note != null &&
                    note.moyenne != null &&
                    note.note! >= note.moyenne!;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.grade_outlined,
                    color: good ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(note.matiere),
                  subtitle: note.moyenne == null
                      ? null
                      : Text('Moyenne ${_fmtNote(note.moyenne)}'),
                  trailing: Text(
                    _fmtNote(note.note),
                    style: tt.titleMedium?.copyWith(
                      color: good ? cs.primary : cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => widget.onOpenSection(AppSection.notes),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _fmtNote(double? value) {
    if (value == null) return '—';
    return value
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'\.?0+$'), '')
        .replaceAll('.', ',');
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final String action;
  final VoidCallback onAction;
  final Widget child;

  const _Section({
    required this.title,
    required this.icon,
    required this.action,
    required this.onAction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

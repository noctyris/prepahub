import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/parse.dart';
import 'colloscope.dart';
import 'subject_colors.dart';

const _jours = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

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

const edtSemesterPrefKey = 'edt_semestre';
const edtWeekendPrefKey = 'edt_weekend_visible';
const _edtSubjectColorsPrefKey = 'edt_subject_colors';

const _subjectColorSeeds = <int>[
  0xFF1565C0,
  0xFF00897B,
  0xFF6A1B9A,
  0xFFEF6C00,
  0xFF2E7D32,
  0xFFAD1457,
  0xFF4527A0,
  0xFF00838F,
  0xFF8E24AA,
  0xFF5D4037,
  0xFF3949AB,
  0xFFC62828,
];

final _whitespace = RegExp(r'\s+');

String _subjectKey(String matiere) =>
    matiere.trim().toLowerCase().replaceAll(_whitespace, ' ');

int defaultEdtSemester(DateTime d) => d.month >= 8 || d.month == 1 ? 1 : 2;

String _two(int n) => n.toString().padLeft(2, '0');

String _formatTime(TimeOfDay t) => '${_two(t.hour)}h${_two(t.minute)}';

String _displayTime(String raw) {
  final parts = raw.replaceAll('h', ':').split(':');
  final h = int.tryParse(parts.first) ?? 0;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return '${_two(h)}h${_two(m)}';
}

String _displayMinutes(int minutes) =>
    '${_two(minutes ~/ 60)}h${_two(minutes % 60)}';

String _gridTime(int minutes) {
  final hour = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hour}h' : '${hour}h${_two(rest)}';
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

DateTime _nextSchoolDay(DateTime date) {
  var result = DateTime(date.year, date.month, date.day);
  while (result.weekday > DateTime.friday) {
    result = result.add(const Duration(days: 1));
  }
  return result;
}

enum _EdtView { day, week }

enum _CoursRecurrence { everyWeek, oddWeeks, evenWeeks, custom }

final int _oddWeeksMask = _weeksMask(odd: true);
final int _evenWeeksMask = _weeksMask(odd: false);

// `restrictions` stocke les semaines ISO sous forme de masque de bits
// (bit 0 = semaine 1).
int _weeksMask({required bool odd}) {
  var mask = 0;
  for (var week = 1; week <= 53; week++) {
    if (week.isOdd == odd) mask |= 1 << (week - 1);
  }
  return mask;
}

_CoursRecurrence _recurrenceOf(Cours c) {
  if (c.restrictions == 0) return _CoursRecurrence.everyWeek;
  if (c.restrictions == _oddWeeksMask) return _CoursRecurrence.oddWeeks;
  if (c.restrictions == _evenWeeksMask) return _CoursRecurrence.evenWeeks;
  return _CoursRecurrence.custom;
}

bool _isBiweekly(Cours c) =>
    _recurrenceOf(c) == _CoursRecurrence.oddWeeks ||
    _recurrenceOf(c) == _CoursRecurrence.evenWeeks;

String? _recurrenceLabel(Cours c) => switch (_recurrenceOf(c)) {
  _CoursRecurrence.everyWeek => null,
  _CoursRecurrence.oddWeeks => 'Une semaine sur deux (impaires)',
  _CoursRecurrence.evenWeeks => 'Une semaine sur deux (paires)',
  _CoursRecurrence.custom => 'Semaines spécifiques',
};

String? _recurrenceBadge(Cours c) => switch (_recurrenceOf(c)) {
  _CoursRecurrence.everyWeek => null,
  _CoursRecurrence.oddWeeks || _CoursRecurrence.evenWeeks => '1 sem. / 2',
  _CoursRecurrence.custom => 'Certaines sem.',
};

class EDTPage extends StatefulWidget {
  final VoidCallback? onTimetableChanged;

  const EDTPage({super.key, this.onTimetableChanged});

  @override
  State<EDTPage> createState() => _EDTPageState();
}

class _EDTPageState extends State<EDTPage> {
  List<Cours>? _cours;
  List<Colle>? _colles;
  late DateTime _selectedDay;
  int _semestre = _defaultSemestre(DateTime.now());
  bool _showWeekend = false;
  _EdtView _view = _EdtView.day;
  double _slideDirection = 0;
  double _dragDx = 0;
  Map<String, int> _subjectSeeds = const {};

  Timer? _clock;

  static int _defaultSemestre(DateTime d) =>
      d.month >= 8 || d.month == 1 ? 1 : 2;

  DateTime get _monday => _mondayOf(_selectedDay);

  String get _semestreLabel => _semestre == 1 ? '1er semestre' : '2e semestre';

  DateTime get _visibleToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _showWeekend ? today : _nextSchoolDay(today);
  }

  bool get _isToday => _sameDay(_selectedDay, _visibleToday);

  bool get _isCurrentWeek => _monday == _mondayOf(DateTime.now());

  int get _visibleDayCount => _showWeekend ? 7 : 5;

  bool get _showTodayAction =>
      _view == _EdtView.day ? !_isToday : !_isCurrentWeek;

  @override
  void initState() {
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    var semestre = _defaultSemestre(DateTime.now());
    var showWeekend = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      semestre = prefs.getInt(edtSemesterPrefKey) ?? semestre;
      showWeekend = prefs.getBool(edtWeekendPrefKey) ?? false;
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
    var subjectSeeds = <String, int>{};
    try {
      subjectSeeds = await EdtColorStore.load(cours.map((c) => c.matiere));
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _semestre = semestre;
      _showWeekend = showWeekend;
      if (!showWeekend) _selectedDay = _nextSchoolDay(_selectedDay);
      _cours = cours;
      _colles = colles;
      _subjectSeeds = subjectSeeds;
    });
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
      await prefs.setInt(edtSemesterPrefKey, semestre);
    } catch (_) {}
    if (!mounted) return;
    widget.onTimetableChanged?.call();
  }

  Future<void> _openEditor() async {
    final cours = _cours;
    if (cours == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _EdtEditPage(initialCours: cours, initialSemestre: _semestre),
      ),
    );
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    widget.onTimetableChanged?.call();
  }

  void _setView(_EdtView view) {
    if (view == _view) return;
    setState(() {
      _view = view;
      _slideDirection = 0;
    });
  }

  void _move(int delta) {
    setState(() {
      _slideDirection = delta > 0 ? 1 : -1;
      if (_view == _EdtView.week) {
        _selectedDay = DateTime(
          _selectedDay.year,
          _selectedDay.month,
          _selectedDay.day + 7 * delta,
        );
        return;
      }
      var next = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day + delta,
      );
      if (!_showWeekend) {
        while (next.weekday > DateTime.friday) {
          next = next.add(Duration(days: delta.sign));
        }
      }
      _selectedDay = next;
    });
  }

  void _goToToday() {
    setState(() {
      _slideDirection = 0;
      _selectedDay = _visibleToday;
    });
  }

  Future<void> _toggleWeekend() async {
    final show = !_showWeekend;
    setState(() {
      _showWeekend = show;
      if (!show) _selectedDay = _nextSchoolDay(_selectedDay);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(edtWeekendPrefKey, show);
    } catch (_) {}
  }

  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDx.abs() < 40 && velocity.abs() < 120) return;
    final next = _dragDx < 0 || velocity < 0;
    _move(next ? 1 : -1);
  }

  Future<void> _openColles() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ColloscopePage(onChanged: widget.onTimetableChanged),
      ),
    );
    if (!mounted) return;
    List<Colle> colles;
    try {
      colles = await ColloscopeStore.load();
    } catch (_) {
      colles = [];
    }
    if (!mounted) return;
    setState(() => _colles = colles);
    widget.onTimetableChanged?.call();
  }

  int? _seedFor(String matiere) => _subjectSeeds[_subjectKey(matiere)];

  Future<void> _chooseSubjectColor(String matiere) async {
    final key = _subjectKey(matiere);
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _SubjectColorDialog(
        matiere: matiere,
        selectedSeed: _subjectSeeds[key],
      ),
    );
    if (picked == null || !mounted) return;
    final next = {..._subjectSeeds, key: picked};
    setState(() => _subjectSeeds = next);
    try {
      await EdtColorStore.save(next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer la couleur")),
      );
    }
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
    final isWeek = _view == _EdtView.week;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emploi du temps'),
        actions: [
          if (_showTodayAction)
            IconButton(
              tooltip: isWeek
                  ? 'Revenir à cette semaine'
                  : "Revenir à aujourd'hui",
              icon: const Icon(Icons.today),
              onPressed: _goToToday,
            ),
          IconButton(
            tooltip: "Modifier l'emploi du temps",
            icon: const Icon(Icons.edit_calendar_outlined),
            onPressed: _cours == null ? null : _openEditor,
          ),
          IconButton(
            tooltip: 'Planning des khôlles',
            icon: const Icon(Icons.record_voice_over_outlined),
            onPressed: _openColles,
          ),
          PopupMenuButton<int>(
            tooltip: 'Semestre et affichage',
            onSelected: (value) {
              if (value == 0) {
                unawaited(_toggleWeekend());
              } else {
                unawaited(_chooseSemestre(value));
              }
            },
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
              const PopupMenuDivider(),
              CheckedPopupMenuItem(
                value: 0,
                checked: _showWeekend,
                child: const Text('Afficher le week-end'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _header(),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _dragDx = 0,
              onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
              onHorizontalDragEnd: _onSwipe,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(_slideDirection * 0.15, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: SizedBox.expand(
                  key: ValueKey(
                    '${_view.name}-${_selectedDay.toIso8601String()}',
                  ),
                  child: isWeek ? _weekView() : _dayView(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isWeek = _view == _EdtView.week;
    final monday = _monday;
    final lastDay = DateTime(
      monday.year,
      monday.month,
      monday.day + (_showWeekend ? 6 : 4),
    );
    final title = isWeek
        ? 'Semaine ${monday.isoWeekNumber}'
        : '${_jours[_selectedDay.weekday - 1]} ${_selectedDay.day} '
              '${_mois[_selectedDay.month - 1]}';
    final subtitle = isWeek
        ? '${monday.day} ${_mois[monday.month - 1]} – '
              '${lastDay.day} ${_mois[lastDay.month - 1]}'
        : 'Semaine ${_selectedDay.isoWeekNumber}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          SegmentedButton<_EdtView>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: _EdtView.day, label: Text('Jour')),
              ButtonSegment(value: _EdtView.week, label: Text('Semaine')),
            ],
            selected: {_view},
            onSelectionChanged: (s) => _setView(s.first),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              IconButton(
                tooltip: isWeek ? 'Semaine précédente' : 'Jour précédent',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _move(-1),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(title, style: tt.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      '$subtitle · $_semestreLabel',
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: isWeek ? 'Semaine suivante' : 'Jour suivant',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _move(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_EdtEvent> _weekEvents() {
    final cours = _weekCours();
    final colles = _weekColles();
    return [
      for (final c in cours)
        if (c.jour >= 1 && c.jour <= _visibleDayCount)
          _EdtEvent.cours(
            c,
            DateTime(_monday.year, _monday.month, _monday.day + c.jour - 1),
          ),
      for (final c in colles)
        if (_showWeekend || c.date.weekday <= DateTime.friday)
          _EdtEvent.colle(c),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  Widget _weekView() {
    if (_cours == null || _colles == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final events = _weekEvents();
    if (events.isEmpty) return _emptyAgenda(week: true);
    return _WeekGrid(
      monday: _monday,
      dayCount: _visibleDayCount,
      events: events,
      subjectSeeds: _subjectSeeds,
      onTap: _showEvent,
    );
  }

  Widget _dayView() {
    if (_cours == null || _colles == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final events = [
      for (final e in _weekEvents())
        if (e.day == _selectedDay.weekday) e,
    ];
    if (events.isEmpty) return _emptyAgenda(week: false);
    return _DayTimeline(
      date: _selectedDay,
      events: events,
      subjectSeeds: _subjectSeeds,
      onTap: _showEvent,
    );
  }

  void _showEvent(_EdtEvent event) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => _EventSheet(
        event: event,
        colorSeed: event.isKholle ? null : _seedFor(event.matiere),
        onEditColor: event.isKholle
            ? null
            : () {
                Navigator.pop(ctx);
                unawaited(_chooseSubjectColor(event.matiere));
              },
        onEdit: event.isKholle
            ? null
            : () {
                Navigator.pop(ctx);
                _openEditor();
              },
        onManageColles: event.isKholle
            ? () {
                Navigator.pop(ctx);
                _openColles();
              }
            : null,
      ),
    );
  }

  Widget _emptyAgenda({required bool week}) {
    final hasCours = (_cours ?? const <Cours>[]).any(
      (c) => c.semestre == _semestre,
    );
    return _EmptyAgenda(
      icon: hasCours ? Icons.event_busy_rounded : Icons.calendar_month_rounded,
      title: hasCours
          ? (week ? 'Rien cette semaine' : 'Rien ce jour')
          : 'Aucun cours ce semestre',
      message: hasCours
          ? (week
                ? 'Aucun cours ni khôlle pour cette semaine.'
                : 'Aucun cours ni khôlle pour ce jour.')
          : 'Ajoute tes cours depuis la page de modification '
                '(icône en haut).',
      onEdit: () => _openEditor(),
    );
  }
}

class _EdtEvent {
  final Cours? cours;
  final Colle? colle;
  final DateTime date;
  final int day;
  final int start;
  final int end;

  const _EdtEvent._({
    required this.cours,
    required this.colle,
    required this.date,
    required this.day,
    required this.start,
    required this.end,
  });

  factory _EdtEvent.cours(Cours c, DateTime date) {
    var start = _minutes(c.heureDebut);
    if (start < 0) start = 0;
    if (start > 24 * 60 - 15) start = 24 * 60 - 15;
    var end = _minutes(c.heureFin);
    if (end <= start) end = start + 60;
    if (end > 24 * 60) end = 24 * 60;
    return _EdtEvent._(
      cours: c,
      colle: null,
      date: date,
      day: date.weekday,
      start: start,
      end: end,
    );
  }

  factory _EdtEvent.colle(Colle c) {
    var start = c.date.hour * 60 + c.date.minute;
    if (start < 0) start = 0;
    if (start > 24 * 60 - 15) start = 24 * 60 - 15;
    var end = start + 60;
    if (end > 24 * 60) end = 24 * 60;
    return _EdtEvent._(
      cours: null,
      colle: c,
      date: c.date,
      day: c.date.weekday,
      start: start,
      end: end,
    );
  }

  bool get isKholle => colle != null;
  bool get isBiweekly => cours != null && _isBiweekly(cours!);
  String? get recurrenceLabel =>
      cours == null ? null : _recurrenceLabel(cours!);

  String get matiere => cours?.matiere ?? colle!.matiere;
  String get prof => cours?.prof ?? colle!.prof;
  String get salle => cours?.salle ?? colle!.salle;
  String get startLabel => _displayMinutes(start);
  String get endLabel => _displayMinutes(end);
}

Map<_EdtEvent, ({int lane, int count})> _layoutLanes(List<_EdtEvent> sorted) {
  final result = <_EdtEvent, ({int lane, int count})>{};
  var cluster = <_EdtEvent>[];
  var clusterEnd = 0;

  void closeCluster() {
    if (cluster.isEmpty) return;
    final laneEnds = <int>[];
    final lanes = <_EdtEvent, int>{};
    for (final event in cluster) {
      var lane = laneEnds.indexWhere((end) => end <= event.start);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(event.end);
      } else {
        laneEnds[lane] = event.end;
      }
      lanes[event] = lane;
    }
    final count = laneEnds.isEmpty ? 1 : laneEnds.length;
    for (final event in cluster) {
      result[event] = (lane: lanes[event] ?? 0, count: count);
    }
    cluster = <_EdtEvent>[];
    clusterEnd = 0;
  }

  for (final event in sorted) {
    if (cluster.isNotEmpty && event.start >= clusterEnd) closeCluster();
    cluster.add(event);
    if (event.end > clusterEnd) clusterEnd = event.end;
  }
  closeCluster();
  return result;
}

class _WeekGrid extends StatelessWidget {
  final DateTime monday;
  final int dayCount;
  final List<_EdtEvent> events;
  final Map<String, int> subjectSeeds;
  final ValueChanged<_EdtEvent> onTap;

  const _WeekGrid({
    required this.monday,
    required this.dayCount,
    required this.events,
    required this.subjectSeeds,
    required this.onTap,
  });

  static const double _hourHeight = 56;
  static const double _gutterWidth = 38;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    var startMinute = 8 * 60;
    var endMinute = 18 * 60;
    for (final e in events) {
      if (e.start < startMinute) startMinute = e.start;
      if (e.end > endMinute) endMinute = e.end;
    }
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    var startHour = startMinute ~/ 60;
    var endHour = (endMinute + 59) ~/ 60;
    var todayColumn = -1;
    for (var jour = 1; jour <= dayCount; jour++) {
      if (_sameDay(
        DateTime(monday.year, monday.month, monday.day + jour - 1),
        now,
      )) {
        todayColumn = jour - 1;
        break;
      }
    }
    if (todayColumn >= 0) {
      if (nowMinutes < startHour * 60) startHour = nowMinutes ~/ 60;
      if (nowMinutes > endHour * 60) endHour = (nowMinutes + 59) ~/ 60;
    }
    if (endHour <= startHour) endHour = startHour + 1;
    if (endHour > 24) endHour = 24;
    final totalHeight = (endHour - startHour) * _hourHeight;
    final gridHeight = totalHeight + 8;
    final nowTop =
        todayColumn >= 0 &&
            nowMinutes >= startHour * 60 &&
            nowMinutes <= endHour * 60
        ? ((nowMinutes - startHour * 60) / 60 * _hourHeight - 7)
              .clamp(0.0, gridHeight - 14)
              .toDouble()
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dayWidth = (constraints.maxWidth - _gutterWidth) / dayCount;
          return Column(
            children: [
              SizedBox(
                height: 46,
                child: Row(
                  children: [
                    const SizedBox(width: _gutterWidth),
                    for (var jour = 1; jour <= dayCount; jour++)
                      SizedBox(
                        width: dayWidth,
                        child: _DayHeader(
                          date: DateTime(
                            monday.year,
                            monday.month,
                            monday.day + jour - 1,
                          ),
                          isToday: _sameDay(
                            DateTime(
                              monday.year,
                              monday.month,
                              monday.day + jour - 1,
                            ),
                            now,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    height: gridHeight,
                    child: Stack(
                      children: [
                        for (var h = startHour; h <= endHour; h++)
                          Positioned(
                            top: (h - startHour) * _hourHeight,
                            left: _gutterWidth,
                            right: 0,
                            child: Container(
                              height: 1,
                              color: cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TimeGutter(
                              width: _gutterWidth,
                              height: gridHeight,
                              startHour: startHour,
                              endHour: endHour,
                              hourHeight: _hourHeight,
                            ),
                            for (var jour = 1; jour <= dayCount; jour++)
                              SizedBox(
                                width: dayWidth,
                                height: gridHeight,
                                child: _DayColumn(
                                  width: dayWidth,
                                  events: [
                                    for (final e in events)
                                      if (e.day == jour) e,
                                  ],
                                  subjectSeeds: subjectSeeds,
                                  startHour: startHour,
                                  hourHeight: _hourHeight,
                                  isToday: _sameDay(
                                    DateTime(
                                      monday.year,
                                      monday.month,
                                      monday.day + jour - 1,
                                    ),
                                    now,
                                  ),
                                  onTap: onTap,
                                ),
                              ),
                          ],
                        ),
                        if (nowTop != null)
                          Positioned(
                            top: nowTop,
                            left: _gutterWidth + todayColumn * dayWidth,
                            width: dayWidth,
                            height: 14,
                            child: _NowLine(color: cs.error),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime date;
  final bool isToday;

  const _DayHeader({required this.date, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: isToday
          ? BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _joursCourts[date.weekday - 1],
            style: tt.labelSmall?.copyWith(
              color: isToday ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '${date.day}',
            style: tt.titleSmall?.copyWith(
              color: isToday ? cs.onPrimaryContainer : cs.onSurface,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeGutter extends StatelessWidget {
  final double width;
  final double height;
  final int startHour;
  final int endHour;
  final double hourHeight;

  const _TimeGutter({
    required this.width,
    required this.height,
    required this.startHour,
    required this.endHour,
    required this.hourHeight,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var h = startHour; h <= endHour; h++)
            Positioned(
              top: (h - startHour) * hourHeight + 1,
              right: 4,
              child: Text(
                '${h}h',
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 9,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  final double width;
  final List<_EdtEvent> events;
  final Map<String, int> subjectSeeds;
  final int startHour;
  final double hourHeight;
  final bool isToday;
  final ValueChanged<_EdtEvent> onTap;

  const _DayColumn({
    required this.width,
    required this.events,
    required this.subjectSeeds,
    required this.startHour,
    required this.hourHeight,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
    final layout = _layoutLanes(sorted);

    return Container(
      decoration: BoxDecoration(
        color: isToday ? cs.primary.withValues(alpha: 0.05) : null,
        border: Border(
          left: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Stack(
        children: [
          for (final e in sorted)
            _buildBlock(
              context,
              e,
              layout[e]?.lane ?? 0,
              layout[e]?.count ?? 1,
            ),
        ],
      ),
    );
  }

  Widget _buildBlock(
    BuildContext context,
    _EdtEvent event,
    int lane,
    int laneCount,
  ) {
    final laneWidth = (width - 2) / laneCount;
    final top = (event.start - startHour * 60) / 60 * hourHeight;
    final blockHeight = math.max(
      26.0,
      (event.end - event.start) / 60 * hourHeight - 2,
    );
    return Positioned(
      top: top,
      left: 1 + lane * laneWidth,
      width: math.max(1.0, laneWidth - 1),
      height: blockHeight,
      child: _WeekEventBlock(
        event: event,
        colorSeed: event.isKholle
            ? null
            : subjectSeeds[_subjectKey(event.matiere)],
        onTap: () => onTap(event),
      ),
    );
  }
}

class _WeekEventBlock extends StatelessWidget {
  final _EdtEvent event;
  final int? colorSeed;
  final VoidCallback onTap;

  const _WeekEventBlock({
    required this.event,
    required this.colorSeed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isKholle = event.isKholle;
    final palette = !isKholle && colorSeed != null
        ? subjectPalette(colorSeed!, Theme.of(context).brightness)
        : null;
    final bg = isKholle
        ? cs.tertiaryContainer
        : (palette?.container ?? cs.secondaryContainer);
    final fg = isKholle
        ? cs.onTertiaryContainer
        : (palette?.onContainer ?? cs.onSecondaryContainer);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(3, 2, 2, 2),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tall = constraints.maxHeight >= 78;
              final subjectLines = constraints.maxHeight >= 48 ? 2 : 1;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isKholle
                        ? 'Khôlle'
                        : '${_gridTime(event.start)}${event.isBiweekly ? ' · 1/2' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: tt.labelSmall?.copyWith(
                      fontSize: 8.5,
                      height: 1,
                      fontWeight: FontWeight.w500,
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    event.matiere,
                    maxLines: tall ? 4 : subjectLines,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      fontSize: 10,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                  if (tall && event.salle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      event.salle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(
                        fontSize: 8.5,
                        height: 1,
                        color: fg.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DayTimeline extends StatelessWidget {
  final DateTime date;
  final List<_EdtEvent> events;
  final Map<String, int> subjectSeeds;
  final ValueChanged<_EdtEvent> onTap;

  const _DayTimeline({
    required this.date,
    required this.events,
    required this.subjectSeeds,
    required this.onTap,
  });

  static const double _hourHeight = 68;
  static const double _gutterWidth = 44;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isToday = _sameDay(date, now);
    final nowMinutes = now.hour * 60 + now.minute;
    var startMinute = 8 * 60;
    var endMinute = 18 * 60;
    for (final event in events) {
      if (event.start < startMinute) startMinute = event.start;
      if (event.end > endMinute) endMinute = event.end;
    }
    if (isToday) {
      if (nowMinutes < startMinute) startMinute = nowMinutes ~/ 60 * 60;
      if (nowMinutes > endMinute) endMinute = (nowMinutes + 59) ~/ 60 * 60;
    }
    var startHour = startMinute ~/ 60;
    if (startHour < 0) startHour = 0;
    var endHour = (endMinute + 59) ~/ 60;
    if (endHour <= startHour) endHour = startHour + 1;
    if (endHour > 24) endHour = 24;
    final gridHeight = (endHour - startHour) * _hourHeight + 8;
    final scale = _hourHeight / 60;
    final sorted = [...events]..sort((a, b) => a.start.compareTo(b.start));
    final layout = _layoutLanes(sorted);
    final nowTop =
        isToday && nowMinutes >= startHour * 60 && nowMinutes <= endHour * 60
        ? ((nowMinutes - startHour * 60) * scale - 7)
              .clamp(0.0, gridHeight - 14)
              .toDouble()
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      child: SizedBox(
        height: gridHeight,
        child: Stack(
          children: [
            for (var h = startHour; h <= endHour; h++)
              Positioned(
                top: (h - startHour) * _hourHeight,
                left: _gutterWidth,
                right: 0,
                child: Container(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            _TimeGutter(
              width: _gutterWidth,
              height: gridHeight,
              startHour: startHour,
              endHour: endHour,
              hourHeight: _hourHeight,
            ),
            for (final event in sorted)
              Positioned(
                top: (event.start - startHour * 60) * scale,
                left: _gutterWidth + 1,
                right: 1,
                height: math.max(34.0, (event.end - event.start) * scale - 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var lane = 0;
                      lane < (layout[event]?.count ?? 1);
                      lane++
                    )
                      Expanded(
                        child: lane == (layout[event]?.lane ?? 0)
                            ? Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: _DayEventBlock(
                                  event: event,
                                  colorSeed: event.isKholle
                                      ? null
                                      : subjectSeeds[_subjectKey(
                                          event.matiere,
                                        )],
                                  onTap: () => onTap(event),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            if (nowTop != null)
              Positioned(
                top: nowTop,
                left: 0,
                right: 0,
                height: 14,
                child: _NowLine(
                  color: cs.error,
                  gutterWidth: _gutterWidth,
                  label: _displayMinutes(nowMinutes),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayEventBlock extends StatelessWidget {
  final _EdtEvent event;
  final int? colorSeed;
  final VoidCallback onTap;

  const _DayEventBlock({
    required this.event,
    required this.colorSeed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isKholle = event.isKholle;
    final palette = !isKholle && colorSeed != null
        ? subjectPalette(colorSeed!, Theme.of(context).brightness)
        : null;
    final background = isKholle
        ? cs.tertiaryContainer
        : (palette?.container ?? cs.secondaryContainer);
    final foreground = isKholle
        ? cs.onTertiaryContainer
        : (palette?.onContainer ?? cs.onSecondaryContainer);
    final badge = isKholle
        ? 'Khôlle'
        : (event.cours == null ? null : _recurrenceBadge(event.cours!));
    final details = [
      if (event.salle.isNotEmpty) 'Salle ${event.salle}',
      if (event.prof.isNotEmpty) event.prof,
    ].join(' · ');

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showEnd = constraints.maxHeight >= 56;
              final showDetails = constraints.maxHeight >= 100;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        event.startLabel,
                        style: tt.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      if (showEnd)
                        Text(
                          event.endLabel,
                          style: tt.labelSmall?.copyWith(
                            color: foreground.withValues(alpha: 0.75),
                            height: 1.1,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          event.matiere,
                          maxLines: showDetails ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.titleSmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        if (showDetails && badge != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: foreground.withValues(alpha: 0.8),
                              height: 1.1,
                            ),
                          ),
                        ],
                        if (showDetails && details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: foreground.withValues(alpha: 0.8),
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (constraints.maxHeight >= 44)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: foreground.withValues(alpha: 0.65),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  final Color color;
  final double gutterWidth;
  final String? label;

  const _NowLine({required this.color, this.gutterWidth = 0, this.label});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return IgnorePointer(
      child: Row(
        children: [
          SizedBox(
            width: gutterWidth,
            child: label == null
                ? null
                : Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        label!,
                        style: tt.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(child: Container(height: 2, color: color)),
        ],
      ),
    );
  }
}

class _SubjectColorDialog extends StatelessWidget {
  final String matiere;
  final int? selectedSeed;

  const _SubjectColorDialog({required this.matiere, this.selectedSeed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Couleur de ${matiere.trim()}'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Cette couleur s'applique à tous les cours de cette matière.",
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _subjectColorSeeds.length; i++)
                  _SubjectColorChoice(
                    seed: _subjectColorSeeds[i],
                    selected: _subjectColorSeeds[i] == selectedSeed,
                    label: 'Couleur ${i + 1}',
                    onTap: () => Navigator.pop(context, _subjectColorSeeds[i]),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}

class _SubjectColorChoice extends StatelessWidget {
  final int seed;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _SubjectColorChoice({
    required this.seed,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(seed);
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.onSurface : cs.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, size: 22, color: checkColor)
              : null,
        ),
      ),
    );
  }
}

class _EventSheet extends StatelessWidget {
  final _EdtEvent event;
  final int? colorSeed;
  final VoidCallback? onEditColor;
  final VoidCallback? onEdit;
  final VoidCallback? onManageColles;

  const _EventSheet({
    required this.event,
    this.colorSeed,
    this.onEditColor,
    this.onEdit,
    this.onManageColles,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isKholle = event.isKholle;
    final date = event.date;
    final recurrence = event.recurrenceLabel;
    final palette = !isKholle && colorSeed != null
        ? subjectPalette(colorSeed!, Theme.of(context).brightness)
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(event.matiere, style: tt.headlineSmall)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isKholle
                      ? cs.tertiaryContainer
                      : (palette?.container ?? cs.secondaryContainer),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isKholle ? 'Khôlle' : 'Cours',
                  style: tt.labelMedium?.copyWith(
                    color: isKholle
                        ? cs.onTertiaryContainer
                        : (palette?.onContainer ?? cs.onSecondaryContainer),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_jours[event.day - 1]} ${date.day} ${_mois[date.month - 1]}',
            style: tt.titleMedium,
          ),
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.schedule,
            text: isKholle
                ? event.startLabel
                : '${event.startLabel} – ${event.endLabel}',
          ),
          if (event.prof.isNotEmpty)
            _DetailRow(icon: Icons.person_outline, text: event.prof),
          if (event.salle.isNotEmpty)
            _DetailRow(
              icon: Icons.meeting_room_outlined,
              text: 'Salle ${event.salle}',
            ),
          if (recurrence != null)
            _DetailRow(icon: Icons.repeat, text: recurrence),
          if (event.cours != null)
            _DetailRow(
              icon: Icons.school_outlined,
              text: event.cours!.semestre == 1 ? '1er semestre' : '2e semestre',
            ),
          const SizedBox(height: 20),
          if (onEditColor != null) ...[
            OutlinedButton.icon(
              onPressed: onEditColor,
              icon: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colorSeed == null ? cs.primary : Color(colorSeed!),
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outlineVariant),
                ),
              ),
              label: const Text('Couleur de la matière'),
            ),
            const SizedBox(height: 8),
          ],
          if (onEdit != null)
            FilledButton.tonalIcon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text("Modifier l'emploi du temps"),
            ),
          if (onManageColles != null)
            FilledButton.tonalIcon(
              onPressed: onManageColles,
              icon: const Icon(Icons.record_voice_over_outlined),
              label: const Text('Gérer les khôlles'),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
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
    final recurrence = _recurrenceLabel(cours);
    final subtitle = [?recurrence, if (details.isNotEmpty) details].join(' · ');
    final jour = cours.jour >= 1 && cours.jour <= 7
        ? _jours[cours.jour - 1]
        : 'Jour inconnu';

    return ListTile(
      onTap: () => onEdit(cours),
      leading: _TimeBadge(
        start: _displayTime(cours.heureDebut),
        end: _displayTime(cours.heureFin),
        background: cs.secondaryContainer,
        foreground: cs.onSecondaryContainer,
      ),
      title: Text(jour, style: tt.titleMedium),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
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

class _EmptyAgenda extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onEdit;

  const _EmptyAgenda({
    required this.icon,
    required this.title,
    required this.message,
    this.onEdit,
  });

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
            Icon(icon, size: 64, color: cs.primary),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: tt.headlineSmall),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (onEdit != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text("Modifier l'emploi du temps"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EdtEditPage extends StatefulWidget {
  final List<Cours> initialCours;
  final int initialSemestre;

  const _EdtEditPage({
    required this.initialCours,
    required this.initialSemestre,
  });

  @override
  State<_EdtEditPage> createState() => _EdtEditPageState();
}

class _EdtEditPageState extends State<_EdtEditPage> {
  late List<Cours> _cours;
  late int _semestre;

  @override
  void initState() {
    super.initState();
    _cours = [...widget.initialCours];
    _semestre = widget.initialSemestre;
  }

  Future<void> _setSemestre(int semestre) async {
    if (semestre == _semestre) return;
    setState(() => _semestre = semestre);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(edtSemesterPrefKey, semestre);
    } catch (_) {}
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
    final list = [..._cours];
    if (old != null) list.remove(old);
    list.add(res);
    await _saveCours(list);
  }

  Future<void> _deleteCours(Cours c) async {
    await _saveCours([..._cours]..remove(c));
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(
      SnackBar(
        content: Text('Cours de ${c.matiere} supprimé'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => _saveCours([..._cours, c]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cours =
        [
          for (final c in _cours)
            if (c.semestre == _semestre) c,
        ]..sort((a, b) {
          final jour = a.jour.compareTo(b.jour);
          if (jour != 0) return jour;
          return _minutes(a.heureDebut).compareTo(_minutes(b.heureDebut));
        });

    return Scaffold(
      appBar: AppBar(title: const Text("Modifier l'emploi du temps")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCours(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un cours'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1er semestre')),
                ButtonSegment(value: 2, label: Text('2e semestre')),
              ],
              selected: {_semestre},
              onSelectionChanged: (s) => _setSemestre(s.first),
            ),
          ),
          Expanded(
            child: cours.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 64,
                            color: cs.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun cours ce semestre',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ajoute un cours avec le bouton « Ajouter un cours ».',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: _sections(cours),
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(List<Cours> cours) {
    final byMatiere = <String, List<Cours>>{};
    for (final c in cours) {
      final matiere = c.matiere.trim();
      final key = matiere.isEmpty ? 'sans matière' : matiere.toLowerCase();
      byMatiere.putIfAbsent(key, () => []).add(c);
    }
    final matieres = byMatiere.keys.toList()..sort();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return [
      for (final key in matieres) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  byMatiere[key]!.first.matiere.trim().isEmpty
                      ? 'Sans matière'
                      : byMatiere[key]!.first.matiere.trim(),
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(color: cs.primary),
                ),
              ),
              Text(
                byMatiere[key]!.length == 1
                    ? '1 créneau'
                    : '${byMatiere[key]!.length} créneaux',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Card.filled(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < byMatiere[key]!.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _CoursTile(
                  cours: byMatiere[key]![i],
                  onEdit: (_) => _editCours(byMatiere[key]![i]),
                ),
              ],
            ],
          ),
        ),
      ],
    ];
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
  late _CoursRecurrence _recurrence;
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
    _recurrence = i == null ? _CoursRecurrence.everyWeek : _recurrenceOf(i);
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
        restrictions: switch (_recurrence) {
          _CoursRecurrence.everyWeek => 0,
          _CoursRecurrence.oddWeeks => _oddWeeksMask,
          _CoursRecurrence.evenWeeks => _evenWeeksMask,
          _CoursRecurrence.custom => widget.initial?.restrictions ?? 0,
        },
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
          DropdownButtonFormField<_CoursRecurrence>(
            initialValue: _recurrence,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Fréquence',
              prefixIcon: Icon(Icons.repeat),
              border: OutlineInputBorder(),
              helperText:
                  "La parité suit le numéro de semaine de l'emploi du temps.",
            ),
            items: [
              const DropdownMenuItem(
                value: _CoursRecurrence.everyWeek,
                child: Text('Toutes les semaines'),
              ),
              const DropdownMenuItem(
                value: _CoursRecurrence.oddWeeks,
                child: Text('Une semaine sur deux (impaires)'),
              ),
              const DropdownMenuItem(
                value: _CoursRecurrence.evenWeeks,
                child: Text('Une semaine sur deux (paires)'),
              ),
              if (_recurrence == _CoursRecurrence.custom)
                const DropdownMenuItem(
                  value: _CoursRecurrence.custom,
                  child: Text('Semaines spécifiques'),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _recurrence = v);
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

class EdtColorStore {
  static int? seedFor(Map<String, int> colors, String matiere) =>
      colors[_subjectKey(matiere)];

  static Future<Map<String, int>> load(Iterable<String> matieres) async {
    final prefs = await SharedPreferences.getInstance();
    final colors = <String, int>{};
    final raw = prefs.getString(_edtSubjectColorsPrefKey);
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        if (data is Map) {
          for (final entry in data.entries) {
            final value = entry.value;
            if (value is num) colors[entry.key.toString()] = value.toInt();
          }
        }
      } catch (_) {}
    }

    final keys = <String>{};
    for (final matiere in matieres) {
      final key = _subjectKey(matiere);
      if (key.isNotEmpty) keys.add(key);
    }
    final sortedKeys = keys.toList()..sort();
    final used = <int>{
      for (final key in sortedKeys)
        if (colors[key] != null) colors[key]!,
    };
    final random = math.Random();
    var changed = false;
    for (final key in sortedKeys) {
      if (colors.containsKey(key)) continue;
      final available = [
        for (final seed in _subjectColorSeeds)
          if (!used.contains(seed)) seed,
      ];
      final pool = available.isEmpty ? _subjectColorSeeds : available;
      final seed = pool[random.nextInt(pool.length)];
      colors[key] = seed;
      used.add(seed);
      changed = true;
    }
    if (changed) {
      try {
        await _save(colors, prefs);
      } catch (_) {}
    }
    return colors;
  }

  static Future<void> save(Map<String, int> colors) async {
    final prefs = await SharedPreferences.getInstance();
    await _save(colors, prefs);
  }

  static Future<void> _save(
    Map<String, int> colors,
    SharedPreferences prefs,
  ) async {
    await prefs.setString(_edtSubjectColorsPrefKey, jsonEncode(colors));
  }
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devoirs.dart';
import 'devoirs_notifications.dart';
import 'edt.dart';
import 'subject_colors.dart';
import 'subjects.dart';

const _moisCourts = [
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

String _formatDate(DateTime date) =>
    '${date.day} ${_moisCourts[date.month - 1]} ${date.year}';

extension _DevoirTypeUi on DevoirType {
  String get label => switch (this) {
    DevoirType.evaluation => 'Éval',
    DevoirType.devoirMaison => 'DM',
    DevoirType.exercices => 'Exercices',
    DevoirType.revision => 'Révision',
    DevoirType.autre => 'Autre',
  };

  IconData get icon => switch (this) {
    DevoirType.evaluation => Icons.quiz_outlined,
    DevoirType.devoirMaison => Icons.home_work_outlined,
    DevoirType.exercices => Icons.edit_note,
    DevoirType.revision => Icons.menu_book_outlined,
    DevoirType.autre => Icons.task_outlined,
  };
}

class _DevoirPalette {
  final Color container;
  final Color onContainer;

  const _DevoirPalette(this.container, this.onContainer);
}

_DevoirPalette _paletteFor(ColorScheme cs, DevoirType type) => switch (type) {
  DevoirType.evaluation => _DevoirPalette(
    cs.errorContainer,
    cs.onErrorContainer,
  ),
  DevoirType.devoirMaison => _DevoirPalette(
    cs.tertiaryContainer,
    cs.onTertiaryContainer,
  ),
  DevoirType.exercices => _DevoirPalette(
    cs.primaryContainer,
    cs.onPrimaryContainer,
  ),
  DevoirType.revision => _DevoirPalette(
    cs.secondaryContainer,
    cs.onSecondaryContainer,
  ),
  DevoirType.autre => _DevoirPalette(
    cs.surfaceContainerHighest,
    cs.onSurfaceVariant,
  ),
};

class DevoirsPage extends StatefulWidget {
  final ValueNotifier<DevoirDraft?>? draftRequest;

  const DevoirsPage({super.key, this.draftRequest});

  @override
  State<DevoirsPage> createState() => _DevoirsPageState();
}

class _DevoirsPageState extends State<DevoirsPage> {
  List<Devoir> _devoirs = [];
  Set<String> _matieres = {};
  Map<String, int> _subjectColors = {};
  DevoirSettings _settings = DevoirSettings.defaults;
  bool _loading = true;
  bool _notificationsAllowed = true;
  bool _formOpen = false;
  final TextEditingController _search = TextEditingController();
  String? _filterMatiere;
  DevoirType? _filterType;

  @override
  void initState() {
    super.initState();
    widget.draftRequest?.addListener(_onDraftRequest);
    final pending = widget.draftRequest?.value;
    if (pending != null) {
      widget.draftRequest!.value = null;
      _scheduleDraft(pending);
    }
    _load();
  }

  @override
  void dispose() {
    widget.draftRequest?.removeListener(_onDraftRequest);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<Devoir> devoirs;
    try {
      devoirs = await DevoirsStore.load();
    } catch (_) {
      devoirs = [];
    }
    DevoirSettings settings;
    try {
      settings = await DevoirSettingsStore.load();
    } catch (_) {
      settings = DevoirSettings.defaults;
    }
    final matieres = await _loadMatieres();
    Map<String, int> subjectColors = {};
    try {
      subjectColors = await EdtColorStore.load(matieres);
    } catch (_) {}
    var allowed = true;
    try {
      allowed = await DevoirNotifications.instance.areNotificationsAllowed();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _devoirs = devoirs..sort(_compareDevoirs);
      _settings = settings;
      _matieres = matieres;
      _subjectColors = subjectColors;
      _notificationsAllowed = allowed;
      _loading = false;
    });
  }

  Future<Set<String>> _loadMatieres() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final semestre =
          prefs.getInt(edtSemesterPrefKey) ??
          defaultEdtSemester(DateTime.now());
      final cours = await EdtStore.load();
      return {
        for (final c in cours)
          if (c.semestre == semestre && c.matiere.trim().isNotEmpty)
            c.matiere.trim(),
      };
    } catch (_) {
      return {};
    }
  }

  Color? _subjectColorFor(String matiere, Brightness brightness) {
    final seed = EdtColorStore.seedFor(_subjectColors, matiere);
    return seed == null ? null : subjectPalette(seed, brightness).accent;
  }

  Future<void> _refreshSubjectColors() async {
    try {
      final colors = await EdtColorStore.load(_matieres);
      if (!mounted) return;
      setState(() => _subjectColors = colors);
    } catch (_) {}
  }

  void _onDraftRequest() {
    final draft = widget.draftRequest?.value;
    if (draft == null) return;
    widget.draftRequest!.value = null;
    _scheduleDraft(draft);
  }

  void _scheduleDraft(DevoirDraft draft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openForm(draft: draft));
    });
  }

  int _compareDevoirs(Devoir a, Devoir b) {
    if (a.fait != b.fait) return a.fait ? 1 : -1;
    final due = a.echeance.compareTo(b.echeance);
    if (due != 0) return due;
    return a.titre.toLowerCase().compareTo(b.titre.toLowerCase());
  }

  bool _matchesFilters(Devoir devoir) {
    final subject = _filterMatiere;
    if (subject != null && canonicalSubject(devoir.matiere) != subject) {
      return false;
    }
    if (_filterType != null && devoir.type != _filterType) return false;
    final query = foldText(_search.text);
    if (query.isEmpty) return true;
    final haystack = foldText(
      [
        devoir.titre,
        devoir.matiere,
        devoir.description,
        for (final task in devoir.sousTaches) task.texte,
      ].join(' '),
    );
    return haystack.contains(query);
  }

  List<Devoir> get _filteredDevoirs => [
    for (final devoir in _devoirs)
      if (_matchesFilters(devoir)) devoir,
  ];

  List<String> get _subjectOptions {
    final values = <String>{
      for (final devoir in _devoirs)
        if (canonicalSubject(devoir.matiere).isNotEmpty)
          canonicalSubject(devoir.matiere),
      for (final matiere in _matieres)
        if (canonicalSubject(matiere).isNotEmpty) canonicalSubject(matiere),
    }.toList();
    values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  void _resetFilters() {
    _search.clear();
    setState(() {
      _filterMatiere = null;
      _filterType = null;
    });
  }

  Future<void> _saveDevoir(Devoir devoir) async {
    final next = [
      for (final item in _devoirs)
        if (item.id != devoir.id) item,
      devoir,
    ];
    await _commit(next);
  }

  Future<void> _commit(List<Devoir> next) async {
    final sorted = [...next]..sort(_compareDevoirs);
    final matieres = {
      ..._matieres,
      for (final devoir in sorted)
        if (devoir.matiere.isNotEmpty) devoir.matiere,
    };
    setState(() {
      _devoirs = sorted;
      _matieres = matieres;
    });
    try {
      await DevoirsStore.save(sorted);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer les devoirs")),
      );
    }
    unawaited(DevoirNotifications.instance.sync());
    unawaited(_refreshSubjectColors());
  }

  Future<void> _toggle(Devoir devoir) async {
    await _commit([
      for (final item in _devoirs)
        if (item.id == devoir.id) item.copyWith(fait: !item.fait) else item,
    ]);
  }

  Future<void> _toggleSousTache(
    Devoir devoir,
    DevoirSousTache sousTache,
  ) async {
    await _saveDevoir(
      devoir.copyWith(
        sousTaches: [
          for (final item in devoir.sousTaches)
            if (item.id == sousTache.id)
              item.copyWith(fait: !item.fait)
            else
              item,
        ],
      ),
    );
  }

  Future<void> _delete(Devoir devoir) async {
    await _commit([
      for (final item in _devoirs)
        if (item.id != devoir.id) item,
    ]);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('« ${devoir.titre} » supprimé'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => unawaited(_commit([..._devoirs, devoir])),
        ),
      ),
    );
  }

  Future<void> _openForm({Devoir? initial, DevoirDraft? draft}) async {
    if (_formOpen) return;
    _formOpen = true;
    Devoir? result;
    try {
      result = await showModalBottomSheet<Devoir>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (ctx) => _DevoirForm(
          initial: initial,
          draft: draft,
          matieres: _matieres.toList()..sort(),
          onDelete: initial == null
              ? null
              : () {
                  Navigator.pop(ctx);
                  unawaited(_delete(initial));
                },
        ),
      );
    } finally {
      _formOpen = false;
    }
    if (result == null || !mounted) return;
    await _saveDevoir(result);
  }

  Future<void> _openSettings() async {
    final result = await showModalBottomSheet<DevoirSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DevoirSettingsSheet(
        settings: _settings,
        allowed: _notificationsAllowed,
        supported: DevoirNotifications.instance.isSupported,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _settings = result);
    try {
      await DevoirSettingsStore.save(result);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer les réglages")),
      );
    }
    final allowed = await DevoirNotifications.instance
        .areNotificationsAllowed();
    if (!mounted) return;
    setState(() => _notificationsAllowed = allowed);
    unawaited(DevoirNotifications.instance.sync());
  }

  Future<void> _requestPermission() async {
    final granted = await DevoirNotifications.instance.requestPermission();
    if (!mounted) return;
    setState(() => _notificationsAllowed = granted);
    if (granted) {
      unawaited(DevoirNotifications.instance.sync());
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Notifications refusées. Tu peux les autoriser dans les réglages du téléphone.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devoirs'),
        actions: [
          IconButton(
            tooltip: 'Rappels et réglages',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_openForm()),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (DevoirNotifications.instance.isSupported &&
                      !_notificationsAllowed) ...[
                    _permissionBanner(context),
                    const SizedBox(height: 12),
                  ],
                  _summary(context),
                  const SizedBox(height: 8),
                  _filters(context),
                  const SizedBox(height: 8),
                  if (_devoirs.isEmpty)
                    _emptyState(context)
                  else if (_filteredDevoirs.isEmpty)
                    _noMatch(context)
                  else
                    ..._groupedList(context),
                ],
              ),
            ),
    );
  }

  Widget _summary(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pending = _devoirs.where((d) => !d.fait).toList();
    final now = DateTime.now();
    final overdue = pending
        .where((d) => d.bucket(now) == DevoirBucket.overdue)
        .length;
    final today = pending
        .where((d) => d.bucket(now) == DevoirBucket.today)
        .length;
    final tomorrow = pending
        .where((d) => d.bucket(now) == DevoirBucket.tomorrow)
        .length;
    final headline = overdue > 0
        ? '$overdue en retard'
        : today > 0
        ? "$today pour aujourd'hui"
        : tomorrow > 0
        ? '$tomorrow pour demain'
        : pending.isEmpty
        ? 'Tout est fait'
        : '${pending.length} à venir';
    final reminder = _settings.eveningEnabled
        ? 'Rappel du soir à ${_two(_settings.eveningHour)}h${_two(_settings.eveningMinute)}'
        : 'Rappels du soir désactivés';

    return Card.filled(
      margin: EdgeInsets.zero,
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.fact_check_outlined, color: cs.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reminder,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.onPrimaryContainer.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${pending.length}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: cs.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Active les notifications pour recevoir les rappels du soir et de fin de cours.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: cs.onSecondaryContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Autoriser'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final hasFilters =
        _filterMatiere != null ||
        _filterType != null ||
        _search.text.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Rechercher un devoir',
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
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('Toutes'),
                  visualDensity: VisualDensity.compact,
                  selected: _filterMatiere == null,
                  onSelected: (_) => setState(() => _filterMatiere = null),
                ),
              ),
              for (final matiere in _subjectOptions)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(matiere),
                    visualDensity: VisualDensity.compact,
                    selected: _filterMatiere == matiere,
                    onSelected: (_) => setState(() => _filterMatiere = matiere),
                  ),
                ),
              PopupMenuButton<String>(
                tooltip: 'Filtrer par type',
                onSelected: (value) {
                  DevoirType? type;
                  for (final candidate in DevoirType.values) {
                    if (candidate.name == value) type = candidate;
                  }
                  setState(() => _filterType = type);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'all',
                    child: Text('Tous les types'),
                  ),
                  for (final type in DevoirType.values)
                    PopupMenuItem(value: type.name, child: Text(type.label)),
                ],
                child: Chip(
                  avatar: const Icon(Icons.filter_list, size: 18),
                  label: Text(_filterType?.label ?? 'Type'),
                  backgroundColor: _filterType == null
                      ? null
                      : Theme.of(context).colorScheme.secondaryContainer,
                ),
              ),
            ],
          ),
        ),
        if (hasFilters)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resetFilters,
              child: const Text('Réinitialiser les filtres'),
            ),
          ),
      ],
    );
  }

  Widget _noMatch(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Aucun devoir ne correspond aux filtres',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Tout afficher'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 340,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rounded, size: 72, color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Aucun devoir',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              "Ajoute ce qu'il y a à faire. Les idées rapides sont là pour t'aider.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => unawaited(_openForm()),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un devoir'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _groupedList(BuildContext context) {
    final now = DateTime.now();
    final widgets = <Widget>[];
    const order = [
      DevoirBucket.overdue,
      DevoirBucket.today,
      DevoirBucket.tomorrow,
      DevoirBucket.thisWeek,
      DevoirBucket.later,
      DevoirBucket.done,
    ];
    for (final bucket in order) {
      final items = [
        for (final devoir in _filteredDevoirs)
          if (devoir.bucket(now) == bucket) devoir,
      ]..sort(_compareDevoirs);
      if (items.isEmpty) continue;
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Text(
            _bucketLabel(bucket),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
      for (final devoir in items) {
        widgets.add(_buildTile(context, devoir, now));
      }
    }
    return widgets;
  }

  Widget _buildTile(BuildContext context, Devoir devoir, DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final palette = _paletteFor(cs, devoir.type);
    final subjectColor = _subjectColorFor(
      devoir.matiere,
      Theme.of(context).brightness,
    );
    final accent = subjectColor ?? palette.container;
    final details = [
      if (devoir.matiere.isNotEmpty) devoir.matiere,
      _dueLabel(devoir, now),
    ].join(' · ');
    final doneSubtasks = devoir.sousTaches.where((item) => item.fait).length;
    final cardColor = Color.alphaBlend(
      accent.withValues(alpha: subjectColor == null ? 0.45 : 0.14),
      cs.surface,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(devoir.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
        ),
        onDismissed: (_) => unawaited(_delete(devoir)),
        child: Card(
          margin: EdgeInsets.zero,
          color: cardColor,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: Checkbox(
                  value: devoir.fait,
                  onChanged: (_) => unawaited(_toggle(devoir)),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        devoir.titre.isEmpty ? 'Sans titre' : devoir.titre,
                        style: devoir.fait
                            ? const TextStyle(
                                decoration: TextDecoration.lineThrough,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DevoirTypeBadge(type: devoir.type, palette: palette),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(details),
                    if (devoir.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        devoir.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (devoir.sousTaches.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: doneSubtasks / devoir.sousTaches.length,
                                minHeight: 5,
                                color: palette.onContainer,
                                backgroundColor: palette.container,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$doneSubtasks/${devoir.sousTaches.length}',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                isThreeLine:
                    devoir.description.isNotEmpty ||
                    devoir.sousTaches.isNotEmpty,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(_openDetail(devoir)),
              ),
              if (devoir.sousTaches.isNotEmpty) ...[
                Divider(
                  height: 1,
                  color: palette.onContainer.withValues(alpha: 0.12),
                ),
                for (final sousTache in devoir.sousTaches)
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.only(left: 48, right: 8),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: sousTache.fait,
                    onChanged: (_) =>
                        unawaited(_toggleSousTache(devoir, sousTache)),
                    title: Text(
                      sousTache.texte,
                      style: tt.bodyMedium?.copyWith(
                        color: sousTache.fait
                            ? cs.onSurfaceVariant
                            : cs.onSurface,
                        decoration: sousTache.fait
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(Devoir devoir) async {
    final subjectColor = _subjectColorFor(
      devoir.matiere,
      Theme.of(context).brightness,
    );
    final edit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => _DevoirDetailSheet(
        devoir: devoir,
        subjectColor: subjectColor,
        onEdit: () => Navigator.pop(ctx, true),
      ),
    );
    if (edit != true || !mounted) return;
    await _openForm(initial: devoir);
  }

  String _bucketLabel(DevoirBucket bucket) => switch (bucket) {
    DevoirBucket.overdue => 'En retard',
    DevoirBucket.today => "Aujourd'hui",
    DevoirBucket.tomorrow => 'Demain',
    DevoirBucket.thisWeek => 'Cette semaine',
    DevoirBucket.later => 'Plus tard',
    DevoirBucket.done => 'Terminés',
  };

  String _dueLabel(Devoir devoir, DateTime now) {
    final bucket = devoir.bucket(now);
    final date =
        '${devoir.echeance.day} '
        '${_moisCourts[devoir.echeance.month - 1]}';
    return switch (bucket) {
      DevoirBucket.overdue => 'En retard depuis le $date',
      DevoirBucket.today => "Aujourd'hui",
      DevoirBucket.tomorrow => 'Demain',
      DevoirBucket.thisWeek => 'Cette semaine · $date',
      DevoirBucket.later => date,
      DevoirBucket.done => 'Terminé · $date',
    };
  }
}

class _DevoirTypeBadge extends StatelessWidget {
  final DevoirType type;
  final _DevoirPalette palette;

  const _DevoirTypeBadge({required this.type, required this.palette});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: palette.container,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 12, color: palette.onContainer),
          const SizedBox(width: 3),
          Text(
            type.label,
            style: tt.labelSmall?.copyWith(color: palette.onContainer),
          ),
        ],
      ),
    );
  }
}

class _DevoirDetailSheet extends StatelessWidget {
  final Devoir devoir;
  final Color? subjectColor;
  final VoidCallback onEdit;

  const _DevoirDetailSheet({
    required this.devoir,
    this.subjectColor,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final palette = _paletteFor(cs, devoir.type);
    final accent = subjectColor ?? palette.container;
    final done = devoir.sousTaches.where((item) => item.fait).length;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.menu_book_outlined, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      devoir.matiere.isEmpty ? 'Sans matière' : devoir.matiere,
                      style: tt.labelLarge?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      devoir.titre.isEmpty ? 'Sans titre' : devoir.titre,
                      style: tt.headlineSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _DevoirTypeBadge(type: devoir.type, palette: palette),
            ],
          ),
          const SizedBox(height: 20),
          _DevoirDetailRow(
            icon: Icons.event_outlined,
            label: 'Échéance',
            value: _formatDate(devoir.echeance),
          ),
          _DevoirDetailRow(
            icon: devoir.fait
                ? Icons.check_circle_outline
                : Icons.pending_outlined,
            label: 'Statut',
            value: devoir.fait ? 'Terminé' : 'À faire',
          ),
          if (devoir.description.isNotEmpty) ...[
            const Divider(height: 24),
            Text('Description', style: tt.titleSmall),
            const SizedBox(height: 6),
            Text(devoir.description, style: tt.bodyMedium),
          ],
          if (devoir.sousTaches.isNotEmpty) ...[
            const Divider(height: 24),
            Row(
              children: [
                Text('Sous-tâches', style: tt.titleSmall),
                const Spacer(),
                Text(
                  '$done/${devoir.sousTaches.length}',
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final item in devoir.sousTaches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  item.fait ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: item.fait ? cs.primary : cs.onSurfaceVariant,
                ),
                title: Text(
                  item.texte,
                  style: tt.bodyMedium?.copyWith(
                    color: item.fait ? cs.onSurfaceVariant : cs.onSurface,
                    decoration: item.fait ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Modifier le devoir'),
          ),
        ],
      ),
    );
  }
}

class _DevoirDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DevoirDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            label,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          Text(value, style: tt.bodyMedium),
        ],
      ),
    );
  }
}

class _SousTacheDraft {
  final String id;
  final TextEditingController texte;
  bool fait;

  _SousTacheDraft({required this.id, String texte = '', this.fait = false})
    : texte = TextEditingController(text: texte);

  void dispose() => texte.dispose();
}

class _DevoirForm extends StatefulWidget {
  final Devoir? initial;
  final DevoirDraft? draft;
  final List<String> matieres;
  final VoidCallback? onDelete;

  const _DevoirForm({
    this.initial,
    this.draft,
    required this.matieres,
    this.onDelete,
  });

  @override
  State<_DevoirForm> createState() => _DevoirFormState();
}

class _DevoirFormState extends State<_DevoirForm> {
  late final TextEditingController _titre;
  late final TextEditingController _matiere;
  late final TextEditingController _description;
  late final List<_SousTacheDraft> _sousTaches;
  DevoirType? _typeOverride;
  late DateTime _echeance;
  late bool _fait;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final draft = widget.draft;
    _titre = TextEditingController(text: initial?.titre ?? draft?.titre ?? '');
    _matiere = TextEditingController(
      text: initial?.matiere ?? draft?.matiere ?? '',
    );
    _description = TextEditingController(text: initial?.description ?? '');
    _sousTaches = [
      for (final item in initial?.sousTaches ?? const <DevoirSousTache>[])
        _SousTacheDraft(id: item.id, texte: item.texte, fait: item.fait),
    ];
    _typeOverride = initial?.type;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _echeance =
        initial?.echeance ??
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    _fait = initial?.fait ?? false;
  }

  @override
  void dispose() {
    _titre.dispose();
    _matiere.dispose();
    _description.dispose();
    for (final item in _sousTaches) {
      item.dispose();
    }
    super.dispose();
  }

  DevoirType get _detectedType => detectDevoirType(
    [
      _titre.text,
      _description.text,
      for (final item in _sousTaches) item.texte.text,
    ].join(' '),
  );

  DevoirType get _type => _typeOverride ?? _detectedType;

  void _onTextChanged() {
    setState(() {
      _error = null;
      _typeOverride = null;
    });
  }

  void _addSousTache() {
    setState(() {
      _sousTaches.add(
        _SousTacheDraft(
          id: '${DateTime.now().microsecondsSinceEpoch}-${_sousTaches.length}',
        ),
      );
    });
  }

  void _removeSousTache(int index) {
    final removed = _sousTaches.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Widget _typeChip(DevoirType type) {
    final cs = Theme.of(context).colorScheme;
    final palette = _paletteFor(cs, type);
    final selected = _type == type;
    return ChoiceChip(
      selected: selected,
      selectedColor: palette.container,
      avatar: Icon(
        type.icon,
        size: 16,
        color: selected ? palette.onContainer : cs.onSurfaceVariant,
      ),
      label: Text(type.label),
      labelStyle: TextStyle(
        color: selected ? palette.onContainer : cs.onSurface,
      ),
      onSelected: (_) => setState(() => _typeOverride = type),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _echeance,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3, 12, 31),
      helpText: 'Pour quand ?',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked == null || !mounted) return;
    setState(() => _echeance = picked);
  }

  void _submit() {
    final titre = _titre.text.trim();
    if (titre.isEmpty) {
      setState(() => _error = 'Indique ce qu’il y a à faire');
      return;
    }
    final initial = widget.initial;
    final sousTaches = [
      for (final item in _sousTaches)
        if (item.texte.text.trim().isNotEmpty)
          DevoirSousTache(
            id: item.id,
            texte: item.texte.text.trim(),
            fait: item.fait,
          ),
    ];
    Navigator.pop(
      context,
      Devoir(
        id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        titre: titre,
        matiere: _matiere.text.trim(),
        description: _description.text.trim(),
        type: _type,
        sousTaches: sousTaches,
        echeance: _echeance,
        fait: _fait,
        creeLe: initial?.creeLe ?? DateTime.now(),
      ),
    );
  }

  List<String> _ideas() {
    final matiere = _matiere.text.toLowerCase();
    if (matiere.contains('math')) {
      return [
        'Faire les exercices du chapitre',
        'Refaire un DS',
        'Faire une fiche de formules',
        'Relire une démonstration',
      ];
    }
    if (matiere.contains('phys') || matiere.contains('chim')) {
      return [
        'Faire les exercices',
        'Relire le compte rendu de TP',
        'Faire une fiche de formules',
        'Refaire un DS',
      ];
    }
    if (matiere.contains('angl') ||
        matiere.contains('espagn') ||
        matiere.contains('allem')) {
      return [
        'Apprendre le vocabulaire',
        'Faire une traduction',
        'Réviser la grammaire',
        'Relire un texte',
      ];
    }
    if (matiere.contains('info')) {
      return [
        "Coder l'exercice",
        'Relire le TD',
        'Préparer des questions',
        'Faire une fiche mémo',
      ];
    }
    return [
      'Relire le cours',
      'Faire les exercices',
      'Finir le DM',
      'Préparer des questions',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final editing = widget.initial != null;
    final doneSubtasks = _sousTaches.where((item) => item.fait).length;

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
            editing ? 'Modifier le devoir' : 'Nouveau devoir',
            style: tt.headlineSmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titre,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _onTextChanged(),
            decoration: InputDecoration(
              labelText: 'À faire',
              hintText: 'DM n°4, exercices 12 à 15…',
              prefixIcon: const Icon(Icons.task_alt),
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _matiere,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Matière (facultatif)',
              prefixIcon: Icon(Icons.menu_book_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.matieres.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final matiere in widget.matieres.take(8))
                  ActionChip(
                    label: Text(matiere),
                    onPressed: () {
                      _matiere.text = matiere;
                      setState(() {});
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text('Idées rapides', style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final idea in _ideas())
                ActionChip(
                  label: Text(idea),
                  onPressed: () {
                    _titre.text = idea;
                    setState(() {
                      _error = null;
                      _typeOverride = null;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Description (facultatif)',
              hintText: 'Notions à revoir, pages, consignes…',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _onTextChanged(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Type', style: tt.titleSmall),
              const Spacer(),
              Text(
                _typeOverride == null ? 'Détection automatique' : 'Type actuel',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [for (final type in DevoirType.values) _typeChip(type)],
          ),
          if (_typeOverride != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _typeOverride = null),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Détection auto'),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Sous-tâches', style: tt.titleSmall),
              const Spacer(),
              if (_sousTaches.isNotEmpty)
                Text(
                  '$doneSubtasks/${_sousTaches.length}',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _sousTaches.length; i++) ...[
            Row(
              children: [
                Checkbox(
                  value: _sousTaches[i].fait,
                  onChanged: (value) =>
                      setState(() => _sousTaches[i].fait = value ?? false),
                ),
                Expanded(
                  child: TextField(
                    controller: _sousTaches[i].texte,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Notion, exercice, page…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _onTextChanged(),
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer',
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeSousTache(i),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addSousTache,
              icon: const Icon(Icons.add_task),
              label: const Text('Ajouter une sous-tâche'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined),
            label: Text('Pour le ${_formatDate(_echeance)}'),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: _fait,
            onChanged: (value) => setState(() => _fait = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Déjà fait'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (widget.onDelete != null)
                TextButton.icon(
                  onPressed: widget.onDelete,
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

class DevoirSettingsSheet extends StatefulWidget {
  final DevoirSettings settings;
  final bool allowed;
  final bool supported;

  const DevoirSettingsSheet({
    super.key,
    required this.settings,
    required this.allowed,
    required this.supported,
  });

  @override
  State<DevoirSettingsSheet> createState() => DevoirSettingsSheetState();
}

class DevoirSettingsSheetState extends State<DevoirSettingsSheet> {
  late DevoirSettings _settings;
  late bool _allowed;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _allowed = widget.allowed;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.eveningHour,
        minute: _settings.eveningMinute,
      ),
      helpText: 'Heure du rappel du soir',
      cancelText: 'Annuler',
      confirmText: 'OK',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _settings = _settings.copyWith(
        eveningHour: picked.hour,
        eveningMinute: picked.minute,
      );
    });
  }

  Future<void> _requestPermission() async {
    final granted = await DevoirNotifications.instance.requestPermission();
    if (!mounted) return;
    setState(() => _allowed = granted);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          Text('Rappels', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'PrépaHub peut te rappeler les devoirs du lendemain et te proposer d’en ajouter à la fin d’un cours.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.bedtime_outlined),
            title: const Text('Rappel du soir'),
            subtitle: Text(
              'La veille à ${_two(_settings.eveningHour)}h${_two(_settings.eveningMinute)}, seulement s’il y a des devoirs.',
            ),
            value: _settings.eveningEnabled,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(eveningEnabled: value);
              });
              if (value && !_allowed) unawaited(_requestPermission());
            },
          ),
          if (_settings.eveningEnabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Heure du rappel'),
              trailing: Text(
                '${_two(_settings.eveningHour)}h${_two(_settings.eveningMinute)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: _pickTime,
            ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.school_outlined),
            title: const Text('Fin de cours'),
            subtitle: const Text(
              'Une suggestion à la fin des cours, sauf sport et DS.',
            ),
            value: _settings.endOfClassEnabled,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(endOfClassEnabled: value);
              });
              if (value && !_allowed) unawaited(_requestPermission());
            },
          ),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Khôlles'),
            subtitle: Text(
              'La veille à ${_two(_settings.eveningHour)}h${_two(_settings.eveningMinute)} '
              'pour les khôlles du lendemain.',
            ),
            value: _settings.colleEnabled,
            onChanged: (value) {
              setState(() {
                _settings = _settings.copyWith(colleEnabled: value);
              });
              if (value && !_allowed) unawaited(_requestPermission());
            },
          ),
          const SizedBox(height: 12),
          if (!widget.supported)
            Text(
              'Les rappels sont disponibles sur Android et iOS.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          else if (_allowed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle, color: cs.primary),
              title: const Text('Notifications autorisées'),
            )
          else
            Card.filled(
              margin: EdgeInsets.zero,
              color: cs.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Les rappels ont besoin de l’autorisation de notifications.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: cs.onSecondaryContainer),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: _requestPermission,
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const Text('Autoriser'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context, _settings),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

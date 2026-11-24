import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'devoirs.dart';
import 'devoirs_notifications.dart';
import 'edt.dart';

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

class DevoirsPage extends StatefulWidget {
  final ValueNotifier<DevoirDraft?>? draftRequest;

  const DevoirsPage({super.key, this.draftRequest});

  @override
  State<DevoirsPage> createState() => _DevoirsPageState();
}

class _DevoirsPageState extends State<DevoirsPage> {
  List<Devoir> _devoirs = [];
  Set<String> _matieres = {};
  DevoirSettings _settings = DevoirSettings.defaults;
  bool _loading = true;
  bool _notificationsAllowed = true;
  bool _formOpen = false;

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
    super.dispose();
  }

  Future<void> _load() async {
    List<Devoir> devoirs;
    try {
      devoirs = await DevoirsStore.load();
    } catch (_) {
      devoirs = [];
    }
    final settings = await DevoirSettingsStore.load();
    final matieres = await _loadMatieres();
    final allowed = await DevoirNotifications.instance
        .areNotificationsAllowed();
    if (!mounted) return;
    setState(() {
      _devoirs = devoirs..sort(_compareDevoirs);
      _settings = settings;
      _matieres = matieres;
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
  }

  Future<void> _toggle(Devoir devoir) async {
    await _commit([
      for (final item in _devoirs)
        if (item.id == devoir.id) item.copyWith(fait: !item.fait) else item,
    ]);
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
      builder: (_) => _DevoirSettingsSheet(
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
                  if (_devoirs.isEmpty)
                    _emptyState(context)
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
        for (final devoir in _devoirs)
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
    final details = [
      if (devoir.matiere.isNotEmpty) devoir.matiere,
      _dueLabel(devoir, now),
    ].join(' · ');
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
        child: Card.filled(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Checkbox(
              value: devoir.fait,
              onChanged: (_) => unawaited(_toggle(devoir)),
            ),
            title: Text(
              devoir.titre.isEmpty ? 'Sans titre' : devoir.titre,
              style: devoir.fait
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            subtitle: Text(details),
            trailing: IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => unawaited(_openForm(initial: devoir)),
            ),
            onTap: () => unawaited(_openForm(initial: devoir)),
          ),
        ),
      ),
    );
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
    super.dispose();
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
    Navigator.pop(
      context,
      Devoir(
        id: initial?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        titre: titre,
        matiere: _matiere.text.trim(),
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
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
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
                    if (_error != null) setState(() => _error = null);
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
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

class _DevoirSettingsSheet extends StatefulWidget {
  final DevoirSettings settings;
  final bool allowed;
  final bool supported;

  const _DevoirSettingsSheet({
    required this.settings,
    required this.allowed,
    required this.supported,
  });

  @override
  State<_DevoirSettingsSheet> createState() => _DevoirSettingsSheetState();
}

class _DevoirSettingsSheetState extends State<_DevoirSettingsSheet> {
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

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app_settings.dart';
import 'api/client.dart';
import 'api/parse.dart';
import 'devoirs_notifications.dart';
import 'edt.dart';
import 'login.dart';
import 'notes_overview.dart';
import 'notes_store.dart';
import 'subjects.dart';

String _fmt(double? v) {
  if (v == null) return '—';
  return v
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'\.?0+$'), '')
      .replaceAll('.', ',');
}

String _weekTitle(Semaine semaine) => 'Semaine ${semaine.numero ?? '?'}';

String _weekDates(Semaine semaine) =>
    semaine.fin.isEmpty ? semaine.debut : '${semaine.debut} → ${semaine.fin}';

double? _weekAverage(Semaine semaine) {
  final values = [
    for (final note in semaine.notes)
      if (note.note != null) note.note!,
  ];
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

Color _noteColor(Note note, ColorScheme cs) {
  if (note.note == null || note.moyenne == null) return cs.onSurface;
  return note.note! >= note.moyenne! ? cs.primary : cs.error;
}

class NotesPage extends StatefulWidget {
  final NotesLayout layout;
  final bool notifyNewGrades;

  const NotesPage({
    super.key,
    this.layout = NotesLayout.cards,
    this.notifyNewGrades = true,
  });

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  bool loading = true;
  bool _offline = false;
  bool _duplicateDialogOpen = false;
  DateTime? _cacheDate;
  List<Semaine>? semaines;
  List<Note> _localNotes = [];
  Map<String, int> _subjectSeeds = const {};
  final Set<String> _ignoredDuplicates = {};
  String? error;
  String? loginNotice;

  @override
  void initState() {
    super.initState();
    notesRevision.addListener(_onExternalRefresh);
    _autoLogin();
  }

  @override
  void dispose() {
    notesRevision.removeListener(_onExternalRefresh);
    super.dispose();
  }

  void _onExternalRefresh() {
    unawaited(_reloadFromCache());
  }

  Future<void> _reloadFromCache() async {
    if (!mounted || semaines == null) return;
    final cached = await NotesStore.loadCache();
    final local = await NotesStore.loadLocalNotes();
    if (!mounted || cached.isEmpty) return;
    setState(() {
      semaines = cached;
      _localNotes = local;
      _offline = false;
      error = null;
    });
    await _loadSubjectSeeds(cached, local);
  }

  Future<void> _autoLogin() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final creds = await loadCreds();
      if (!mounted) return;
      if (creds == null) {
        setState(() => loading = false);
        return;
      }

      await NotesStore.setUser(creds.username);
      final cached = await NotesStore.loadCache();
      final cacheDate = await NotesStore.loadCacheDate();
      final local = await NotesStore.loadLocalNotes();
      unawaited(_loadSubjectSeeds(cached, local));
      if (!mounted) return;
      if (cached.isNotEmpty || local.isNotEmpty) {
        setState(() {
          semaines = cached;
          _localNotes = local;
          _cacheDate = cacheDate;
          _offline = cached.isNotEmpty;
          loading = false;
        });
      }

      try {
        final s = await getNotes(
          creds.username,
          creds.password,
          portal: creds.portal,
        );
        if (!mounted) return;
        setState(() {
          semaines = s;
          loginNotice = null;
          loading = false;
          _offline = false;
        });
        unawaited(_afterFetch(s));
      } on AuthException catch (e) {
        await _forgetCreds();
        if (!mounted) return;
        setState(() {
          loginNotice = e.message;
          semaines = null;
          loading = false;
          _offline = false;
        });
      } on NetworkException catch (e) {
        if (!mounted) return;
        if (cached.isNotEmpty || local.isNotEmpty) {
          setState(() {
            loading = false;
            _offline = true;
            error = null;
          });
        } else {
          setState(() {
            error = e.message;
            loading = false;
          });
        }
      } catch (_) {
        if (!mounted) return;
        if (cached.isNotEmpty || local.isNotEmpty) {
          setState(() {
            loading = false;
            _offline = true;
            error = null;
          });
        } else {
          setState(() {
            error = 'Une erreur inattendue est survenue';
            loading = false;
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Une erreur inattendue est survenue';
        loading = false;
      });
    }
  }

  Future<void> _onLoginSuccess(List<Semaine> s) async {
    final creds = await loadCreds();
    if (creds != null) await NotesStore.setUser(creds.username);
    final local = await NotesStore.loadLocalNotes();
    if (!mounted) return;
    setState(() {
      semaines = s;
      _localNotes = local;
      loginNotice = null;
      _offline = false;
    });
    unawaited(_afterFetch(s));
  }

  Future<void> _afterFetch(List<Semaine> s) async {
    await NotesStore.saveCache(s);
    final date = await NotesStore.loadCacheDate();
    if (mounted) setState(() => _cacheDate = date);
    await _loadSubjectSeeds(s, _localNotes);
    await _notifyNewGrades(s);
    if (!mounted) return;
    await _resolveLocalDuplicates(s);
  }

  Future<void> _notifyNewGrades(List<Semaine> s) async {
    final current = NotesStore.signatures(s);
    final previous = await NotesStore.loadSeenSignatures();
    await NotesStore.saveSeenSignatures(current);
    if (!widget.notifyNewGrades || previous == null) return;
    final count = current.difference(previous).length;
    if (count == 0) return;
    await DevoirNotifications.instance.notifyNewGrades(count);
  }

  bool _similar(Note local, Note online) {
    if (online.local || local.note == null || online.note == null) return false;
    final sameSubject =
        local.matiere.trim().toLowerCase() ==
        online.matiere.trim().toLowerCase();
    return sameSubject && (local.note! - online.note!).abs() < 0.01;
  }

  Future<void> _resolveLocalDuplicates(List<Semaine> s) async {
    if (_localNotes.isEmpty || _duplicateDialogOpen || !mounted) return;
    final matches = [
      for (final local in _localNotes)
        if (local.id != null && !_ignoredDuplicates.contains(local.id))
          if (s.any(
            (semaine) => semaine.notes.any((note) => _similar(local, note)),
          ))
            local,
    ];
    if (matches.isEmpty || !mounted) return;
    _duplicateDialogOpen = true;
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes en ligne'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ces notes ajoutées localement ressemblent à des notes '
                'maintenant disponibles sur le portail :',
              ),
              const SizedBox(height: 12),
              for (final note in matches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• ${note.matiere} : ${_fmt(note.note)}'),
                ),
              const SizedBox(height: 4),
              const Text('Les supprimer de la liste locale ?'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    _duplicateDialogOpen = false;
    if (!mounted) return;
    if (remove == true) {
      final ids = {for (final note in matches) note.id};
      final next = [
        for (final note in _localNotes)
          if (!ids.contains(note.id)) note,
      ];
      setState(() => _localNotes = next);
      await NotesStore.saveLocalNotes(next);
    } else {
      _ignoredDuplicates.addAll([
        for (final note in matches)
          if (note.id != null) note.id!,
      ]);
    }
  }

  Future<void> _forgetCreds() async {
    try {
      await clearCreds();
    } catch (_) {}
  }

  Future<void> _refresh() async {
    try {
      final creds = await loadCreds();
      if (creds == null) {
        await _logout();
        return;
      }
      await NotesStore.setUser(creds.username);
      final s = await getNotes(
        creds.username,
        creds.password,
        portal: creds.portal,
      );
      if (!mounted) return;
      setState(() {
        semaines = s;
        _offline = false;
        error = null;
      });
      unawaited(_afterFetch(s));
    } on AuthException catch (e) {
      await _logout(notice: e.message);
    } on NetworkException catch (e) {
      if (!mounted) return;
      if (semaines != null) setState(() => _offline = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Actualisation impossible')));
    }
  }

  Future<void> _addLocalNote() async {
    final note = await showDialog<Note>(
      context: context,
      builder: (_) => const _LocalNoteDialog(),
    );
    if (note == null || !mounted) return;
    final next = [..._localNotes, note];
    setState(() => _localNotes = next);
    await NotesStore.saveLocalNotes(next);
    unawaited(_loadSubjectSeeds(semaines ?? const [], next));
  }

  Future<void> _deleteLocalNote(Note note) async {
    final next = [
      for (final item in _localNotes)
        if (item.id != note.id) item,
    ];
    setState(() => _localNotes = next);
    await NotesStore.saveLocalNotes(next);
    unawaited(_loadSubjectSeeds(semaines ?? const [], next));
  }

  /// Récupère les couleurs définies dans l'emploi du temps pour chaque
  /// matière, en regroupant TD, TP et cours sous la même couleur.
  Future<void> _loadSubjectSeeds(List<Semaine> weeks, List<Note> local) async {
    try {
      final edt = await EdtStore.load();
      final edtNames = <String>{
        for (final cours in edt)
          if (cours.matiere.trim().isNotEmpty) cours.matiere,
      };
      final noteNames = <String>{
        for (final semaine in weeks)
          for (final note in semaine.notes)
            if (note.matiere.trim().isNotEmpty) note.matiere,
        for (final note in local)
          if (note.matiere.trim().isNotEmpty) note.matiere,
      };
      final names = {...edtNames, ...noteNames};
      if (names.isEmpty) return;
      final colors = await EdtColorStore.load(names);
      final seeds = <String, int>{};
      void assign(String name) {
        final seed = EdtColorStore.seedFor(colors, name);
        if (seed != null) {
          seeds.putIfAbsent(canonicalSubject(name), () => seed);
        }
      }

      // Les couleurs de l'emploi du temps priment, en commençant par les
      // matières dont le nom est déjà la forme regroupée.
      for (final name in edtNames) {
        if (canonicalSubject(name) == name.trim()) assign(name);
      }
      for (final name in edtNames) {
        assign(name);
      }
      for (final name in noteNames) {
        assign(name);
      }
      if (!mounted) return;
      setState(() => _subjectSeeds = seeds);
    } catch (_) {}
  }

  Future<void> _logout({String? notice}) async {
    await _forgetCreds();
    if (!mounted) return;
    setState(() {
      semaines = null;
      _localNotes = [];
      _offline = false;
      _cacheDate = null;
      error = null;
      loginNotice = notice;
      loading = false;
    });
  }

  List<Widget> _weekSlivers(List<Semaine> semaines) {
    if (semaines.isEmpty) return const [];
    switch (widget.layout) {
      case NotesLayout.cards:
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList.separated(
              itemCount: semaines.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _SemaineCard(
                key: ValueKey(i),
                semaine: semaines[i],
                expanded: i == semaines.length - 1,
              ),
            ),
          ),
        ];
      case NotesLayout.grid:
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 168,
              ),
              itemCount: semaines.length,
              itemBuilder: (context, i) => _SemaineGridCard(
                semaine: semaines[i],
                onTap: () => _showWeek(semaines[i]),
              ),
            ),
          ),
        ];
      case NotesLayout.list:
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList.builder(
              itemCount: semaines.length,
              itemBuilder: (context, i) => _SemaineSection(
                semaine: semaines[i],
                showDivider: i < semaines.length - 1,
              ),
            ),
          ),
        ];
      case NotesLayout.drawers:
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverToBoxAdapter(
              child: _WeekDrawerLayout(semaines: semaines),
            ),
          ),
        ];
    }
  }

  void _showWeek(Semaine semaine) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final tt = Theme.of(ctx).textTheme;
        final n = semaine.notes.length;
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.7;
        final height = (120 + n * 92.0).clamp(220.0, maxHeight).toDouble();
        return SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_weekTitle(semaine), style: tt.titleLarge),
                const SizedBox(height: 2),
                Text(
                  '${_weekDates(semaine)} · $n note${n > 1 ? 's' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Divider(height: 20),
                Expanded(
                  child: n == 0
                      ? Center(
                          child: Text(
                            'Pas de note cette semaine',
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final note in semaine.notes)
                              _NoteTile(note: note),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const _NotesSkeleton();
    if (semaines != null) {
      final weeks = semaines!;
      return Scaffold(
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar.large(
                title: const Text('Mes notes'),
                actions: [
                  IconButton(
                    tooltip: 'Ajouter une note locale',
                    icon: const Icon(Icons.add_chart_outlined),
                    onPressed: _addLocalNote,
                  ),
                  IconButton(
                    tooltip: 'Se déconnecter',
                    icon: const Icon(Icons.logout),
                    onPressed: _logout,
                  ),
                ],
              ),
              if (_offline)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _OfflineBanner(cacheDate: _cacheDate),
                  ),
                ),
              if (weeks.isNotEmpty || _localNotes.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: NotesOverview(
                      semaines: weeks,
                      extraNotes: _localNotes,
                      subjectSeeds: _subjectSeeds,
                    ),
                  ),
                ),
              if (_localNotes.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _LocalNotesCard(
                      notes: _localNotes,
                      onDelete: (note) => unawaited(_deleteLocalNote(note)),
                    ),
                  ),
                ),
              if (weeks.isEmpty && _localNotes.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Aucune note pour le moment')),
                )
              else if (weeks.isNotEmpty)
                ..._weekSlivers(weeks)
              else
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      );
    }
    if (error != null) {
      return _ErrorView(
        message: error!,
        onRetry: _autoLogin,
        onLogout: _logout,
      );
    }
    return LoginPage(
      notice: loginNotice,
      onSuccess: (s) => unawaited(_onLoginSuccess(s)),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final DateTime? cacheDate;

  const _OfflineBanner({this.cacheDate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final date = cacheDate;
    final stamp = date == null
        ? 'Notes enregistrées sur cet appareil.'
        : 'Notes enregistrées le '
              '${date.day.toString().padLeft(2, '0')}/'
              '${date.month.toString().padLeft(2, '0')} à '
              '${date.hour.toString().padLeft(2, '0')}h'
              '${date.minute.toString().padLeft(2, '0')}.';
    return Card.filled(
      margin: EdgeInsets.zero,
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: cs.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mode hors ligne · $stamp',
                style: tt.bodySmall?.copyWith(color: cs.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalNotesCard extends StatelessWidget {
  final List<Note> notes;
  final void Function(Note) onDelete;

  const _LocalNotesCard({required this.notes, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note, color: cs.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Notes ajoutées localement',
                    style: tt.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'hors ligne',
                    style: tt.labelSmall?.copyWith(
                      color: cs.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                'En attente de publication sur le portail.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            for (final note in notes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(note.matiere),
                subtitle: note.professeur.isEmpty
                    ? null
                    : Text(note.professeur),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fmt(note.note),
                      style: tt.titleMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Supprimer',
                      icon: const Icon(Icons.close),
                      onPressed: () => onDelete(note),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocalNoteDialog extends StatefulWidget {
  const _LocalNoteDialog();

  @override
  State<_LocalNoteDialog> createState() => _LocalNoteDialogState();
}

class _LocalNoteDialogState extends State<_LocalNoteDialog> {
  final _matiere = TextEditingController();
  final _note = TextEditingController();
  final _professeur = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _matiere.dispose();
    _note.dispose();
    _professeur.dispose();
    super.dispose();
  }

  void _submit() {
    final matiere = _matiere.text.trim();
    final value = double.tryParse(_note.text.trim().replaceAll(',', '.'));
    if (matiere.isEmpty) {
      setState(() => _error = 'Indique la matière');
      return;
    }
    if (value == null || value < 0 || value > 20) {
      setState(() => _error = 'Indique une note entre 0 et 20');
      return;
    }
    Navigator.pop(
      context,
      Note(
        id: 'local-${DateTime.now().microsecondsSinceEpoch}',
        matiere: matiere,
        note: value,
        professeur: _professeur.text.trim(),
        rang: Rang(),
        local: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajouter une note'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Elle reste sur cet appareil jusqu’à sa publication sur le portail.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _matiere,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Matière',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Note sur 20',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _professeur,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Professeur (facultatif)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Ajouter')),
      ],
    );
  }
}

class _NotesSkeleton extends StatefulWidget {
  const _NotesSkeleton();

  @override
  State<_NotesSkeleton> createState() => _NotesSkeletonState();
}

class _NotesSkeletonState extends State<_NotesSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final opacity = 0.35 + 0.35 * _controller.value;
          Widget block(double height, {double? width, double radius = 8}) {
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(radius),
              ),
            );
          }

          return CustomScrollView(
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              const SliverAppBar.large(title: Text('Mes notes')),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Card.filled(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              block(18, width: 90),
                              const Spacer(),
                              block(18, width: 110),
                            ],
                          ),
                          const SizedBox(height: 16),
                          block(12, width: 140),
                          const SizedBox(height: 10),
                          block(96, radius: 12),
                          const SizedBox(height: 16),
                          block(12, width: 160),
                          const SizedBox(height: 10),
                          block(116, radius: 12),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                sliver: SliverList.separated(
                  itemCount: 3,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => Card.filled(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              block(16, width: 96),
                              const Spacer(),
                              block(16, width: 40),
                            ],
                          ),
                          const SizedBox(height: 10),
                          block(12, width: 180),
                          if (i == 0) ...[
                            const SizedBox(height: 14),
                            block(1),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(child: block(34, radius: 12)),
                                const SizedBox(width: 12),
                                block(34, width: 52, radius: 12),
                              ],
                            ),
                          ],
                        ],
                      ),
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

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLogout;
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 64, color: cs.primary),
                const SizedBox(height: 16),
                Text(
                  'Connexion impossible',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
                TextButton(
                  onPressed: onLogout,
                  child: const Text('Changer de compte'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SemaineCard extends StatelessWidget {
  final Semaine semaine;
  final bool expanded;
  const _SemaineCard({
    super.key,
    required this.semaine,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final n = semaine.notes.length;
    final dates = _weekDates(semaine);
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: expanded,
        title: Text(_weekTitle(semaine), style: tt.titleMedium),
        subtitle: Text(
          '$dates · $n note${n > 1 ? 's' : ''}',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if (semaine.notes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Pas de note cette semaine',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            for (final note in semaine.notes) _NoteTile(note: note),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  final Note note;
  const _NoteTile({required this.note});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Color bg = cs.secondaryContainer;
    Color fg = cs.onSecondaryContainer;
    if (note.note != null && note.moyenne != null) {
      if (note.note! >= note.moyenne!) {
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
      } else {
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
      }
    }

    final r = note.rang;
    final chips = <String>[
      if (r.rang != null)
        'Rang ${r.rang}${r.total != null ? '/${r.total}' : ''}',
      if (note.moyenne != null) 'Moy. ${_fmt(note.moyenne)}',
      if (note.ecartType != null) 'σ ${_fmt(note.ecartType)}',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.matiere, style: tt.titleSmall),
                if (note.professeur.isNotEmpty)
                  Text(
                    note.professeur,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final c in chips)
                        Chip(
                          label: Text(c),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _fmt(note.note),
              style: tt.titleLarge?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _SemaineGridCard extends StatelessWidget {
  final Semaine semaine;
  final VoidCallback onTap;

  const _SemaineGridCard({required this.semaine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final average = _weekAverage(semaine);
    final graded = [
      for (final note in semaine.notes)
        if (note.note != null) note,
    ];

    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _weekTitle(semaine),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${semaine.notes.length}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _weekDates(semaine),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              if (average == null)
                Text(
                  'Pas de note',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                )
              else
                Row(
                  children: [
                    Icon(Icons.show_chart, size: 14, color: cs.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Moy. ${_fmt(average)}',
                      style: tt.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              const Spacer(),
              for (final note in graded.take(2))
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.matiere,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmt(note.note),
                        style: tt.labelMedium?.copyWith(
                          color: _noteColor(note, cs),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              if (graded.length > 2)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '+${graded.length - 2} autre'
                    '${graded.length - 2 > 1 ? 's' : ''}',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SemaineSection extends StatelessWidget {
  final Semaine semaine;
  final bool showDivider;

  const _SemaineSection({required this.semaine, required this.showDivider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final average = _weekAverage(semaine);
    final n = semaine.notes.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _weekTitle(semaine),
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (average != null)
                Text(
                  'Moy. ${_fmt(average)}',
                  style: tt.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: Text(
            '${_weekDates(semaine)} · $n note${n > 1 ? 's' : ''}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        if (n == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
            child: Text(
              'Pas de note cette semaine',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          )
        else
          for (final note in semaine.notes) _NoteTile(note: note),
        if (showDivider) const Divider(height: 24),
      ],
    );
  }
}

class _WeekDrawerLayout extends StatefulWidget {
  final List<Semaine> semaines;

  const _WeekDrawerLayout({required this.semaines});

  @override
  State<_WeekDrawerLayout> createState() => _WeekDrawerLayoutState();
}

class _WeekDrawerLayoutState extends State<_WeekDrawerLayout> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.semaines.length - 1;
  }

  @override
  void didUpdateWidget(covariant _WeekDrawerLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.semaines, widget.semaines)) {
      _selected = widget.semaines.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final index = _selected.clamp(0, widget.semaines.length - 1).toInt();
    final semaine = widget.semaines[index];
    final average = _weekAverage(semaine);
    final n = semaine.notes.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Column(
            children: [
              for (var i = 0; i < widget.semaines.length; i++)
                _WeekDrawerTab(
                  label: 'S${widget.semaines[i].numero ?? i + 1}',
                  count: widget.semaines[i].notes.length,
                  selected: i == index,
                  onTap: () => setState(() => _selected = i),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _weekTitle(semaine),
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _weekDates(semaine),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  if (average != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Moyenne ${_fmt(average)}',
                      style: tt.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (n == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Pas de note cette semaine',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final note in semaine.notes) _NoteTile(note: note),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekDrawerTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _WeekDrawerTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: Column(
              children: [
                Text(
                  label,
                  style: tt.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$count',
                  style: tt.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

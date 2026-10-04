import 'package:flutter/material.dart';

import 'api/client.dart';
import 'api/parse.dart';
import 'login.dart';

String _fmt(double? v) {
  if (v == null) return '—';
  return v
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'\.?0+$'), '')
      .replaceAll('.', ',');
}

class NotesPage extends StatefulWidget {
    const NotesPage({super.key});

    @override
    State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  bool loading = true;
  List<Semaine>? semaines;
  String? error;

  @override
  void initState() {
    super.initState();
    _autoLogin();
  }

  Future<void> _autoLogin() async {
    setState(() {
      loading = true;
      error = null;
    });
    final creds = await loadCreds();
    if (!mounted) return;
    if (creds == null) {
      setState(() => loading = false);
      return;
    }
    try {
      final s = await getNotes(creds.username, creds.password);
      if (!mounted) return;
      setState(() {
        semaines = s;
        loading = false;
      });
    } on AuthException {
      await clearCreds();
      if (!mounted) return;
      setState(() => loading = false);
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    final creds = await loadCreds();
    if (creds == null) {
      await _logout();
      return;
    }
    try {
      final s = await getNotes(creds.username, creds.password);
      if (mounted) setState(() => semaines = s);
    } on AuthException {
      await _logout();
    } on NetworkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _logout() async {
    await clearCreds();
    if (!mounted) return;
    setState(() {
      semaines = null;
      error = null;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (semaines != null) {
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
                      tooltip: 'Se déconnecter',
                      icon: const Icon(Icons.logout),
                      onPressed: _logout,
                    ),
                  ],
                ),
                if (semaines == null || semaines?.isEmpty == true)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('Aucune note pour le moment')),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    sliver: SliverList.separated(
                      itemCount: semaines?.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _SemaineCard(
                        key: ValueKey(i),
                        semaine: semaines![i],
                        expanded: i == (semaines?.length ?? 0) - 1,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
    }
    if (error != null) {
        return _ErrorView(message: error!, onRetry: _autoLogin, onLogout: _logout);
    }
    return LoginPage(onSuccess: (s) => setState(() => semaines = s));
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLogout;
  const _ErrorView(
      {required this.message, required this.onRetry, required this.onLogout});

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
                Text('Connexion impossible',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
                TextButton(
                    onPressed: onLogout, child: const Text('Changer de compte')),
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
    final dates = semaine.fin.isEmpty
        ? semaine.debut
        : '${semaine.debut} → ${semaine.fin}';
    return Card.filled(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: expanded,
        title: Text('Semaine ${semaine.numero ?? '?'}', style: tt.titleMedium),
        subtitle: Text(
          '$dates · $n colle${n > 1 ? 's' : ''}',
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

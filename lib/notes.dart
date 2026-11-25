import 'package:material_ui/material_ui.dart';

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
  String? loginNotice;

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
    try {
      final creds = await loadCreds();
      if (!mounted) return;
      if (creds == null) {
        setState(() => loading = false);
        return;
      }
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
      });
    } on AuthException catch (e) {
      await _forgetCreds();
      if (!mounted) return;
      setState(() {
        loginNotice = e.message;
        loading = false;
      });
    } on NetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Une erreur inattendue est survenue';
        loading = false;
      });
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
      final s = await getNotes(
        creds.username,
        creds.password,
        portal: creds.portal,
      );
      if (mounted) setState(() => semaines = s);
    } on AuthException catch (e) {
      await _logout(notice: e.message);
    } on NetworkException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Actualisation impossible')),
      );
    }
  }

  Future<void> _logout({String? notice}) async {
    await _forgetCreds();
    if (!mounted) return;
    setState(() {
      semaines = null;
      error = null;
      loginNotice = notice;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
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
                if (semaines != null && semaines!.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _NotesOverview(semaines: semaines!),
                    ),
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
    return LoginPage(
      notice: loginNotice,
      onSuccess: (s) => setState(() {
        semaines = s;
        loginNotice = null;
      }),
    );
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

class _NotesOverview extends StatelessWidget {
  final List<Semaine> semaines;

  const _NotesOverview({required this.semaines});

  List<double> get _allNotes => [
    for (final s in semaines)
      for (final n in s.notes)
        if (n.note != null) n.note!,
  ];

  List<({String label, double moyenne})> get _weeklyAverages {
    final result = <({String label, double moyenne})>[];
    for (var i = 0; i < semaines.length; i++) {
      final s = semaines[i];
      final values = [
        for (final n in s.notes)
          if (n.note != null) n.note!,
      ];
      if (values.isEmpty) continue;
      final sum = values.fold<double>(0, (a, b) => a + b);
      result.add((
        label: s.numero != null ? 'S${s.numero}' : 'S${i + 1}',
        moyenne: sum / values.length,
      ));
    }
    return result;
  }

  /// Cinq tranches de 4 points : 0–4, 4–8, 8–12, 12–16, 16–20.
  List<int> get _distribution {
    final counts = List<int>.filled(5, 0);
    for (final value in _allNotes) {
      var bucket = (value / 4).floor();
      if (bucket < 0) bucket = 0;
      if (bucket > 4) bucket = 4;
      counts[bucket]++;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final notes = _allNotes;
    if (notes.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final overall = notes.reduce((a, b) => a + b) / notes.length;
    final averages = _weeklyAverages;

    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Aperçu', style: tt.titleMedium)),
                Text(
                  'Moyenne ${_fmt(overall)}',
                  style: tt.titleSmall?.copyWith(color: cs.primary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Répartition des notes',
              style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _DistributionChart(counts: _distribution),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Évolution de la moyenne',
              style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _EvolutionChart(points: averages),
          ],
        ),
      ),
    );
  }
}

class _DistributionChart extends StatelessWidget {
  final List<int> counts;

  const _DistributionChart({required this.counts});

  static const _labels = ['0–4', '4–8', '8–12', '12–16', '16–20'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    var maxCount = 0;
    for (final count in counts) {
      if (count > maxCount) maxCount = count;
    }
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < counts.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${counts[i]}',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: maxCount == 0
                          ? 0.0
                          : 4 + 60 * counts[i] / maxCount,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _labels[i],
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EvolutionChart extends StatelessWidget {
  final List<({String label, double moyenne})> points;

  const _EvolutionChart({required this.points});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (points.length < 2) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          points.isEmpty
              ? 'Pas encore de note à suivre.'
              : 'Une seule semaine notée pour le moment.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Semantics(
      label:
          'Évolution de la moyenne, de ${points.first.label} '
          'à ${points.last.label}',
      child: SizedBox(
        height: 116,
        child: CustomPaint(
          painter: _EvolutionPainter(
            values: [for (final p in points) p.moyenne],
            labels: [for (final p in points) p.label],
            line: cs.primary,
            fill: cs.primary.withValues(alpha: 0.12),
            grid: cs.outlineVariant.withValues(alpha: 0.5),
            labelStyle:
                tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 9,
                ) ??
                const TextStyle(fontSize: 9),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _EvolutionPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color line;
  final Color fill;
  final Color grid;
  final TextStyle labelStyle;

  const _EvolutionPainter({
    required this.values,
    required this.labels,
    required this.line,
    required this.fill,
    required this.grid,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftGutter = 24.0;
    const bottomGutter = 16.0;
    const topPadding = 6.0;
    final chartWidth = size.width - leftGutter;
    final chartHeight = size.height - bottomGutter - topPadding;
    if (chartWidth <= 0 || chartHeight <= 0 || values.isEmpty) return;

    double yFor(double value) {
      final clamped = value.clamp(0.0, 20.0).toDouble();
      return topPadding + chartHeight * (1 - clamped / 20);
    }

    double xFor(int index) => leftGutter +
        (values.length == 1
            ? chartWidth / 2
            : chartWidth * index / (values.length - 1));

    void drawText(String text, Offset center) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final x = (center.dx - tp.width / 2)
          .clamp(0.0, size.width - tp.width)
          .toDouble();
      tp.paint(canvas, Offset(x, center.dy - tp.height / 2));
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final value in const [0.0, 10.0, 20.0]) {
      final y = yFor(value);
      canvas.drawLine(Offset(leftGutter, y), Offset(size.width, y), gridPaint);
      drawText('${value.toInt()}', Offset(leftGutter / 2, y));
    }

    final dots = [
      for (var i = 0; i < values.length; i++)
        Offset(xFor(i), yFor(values[i])),
    ];

    if (dots.length > 1) {
      final path = Path()..moveTo(dots.first.dx, dots.first.dy);
      for (final dot in dots.skip(1)) {
        path.lineTo(dot.dx, dot.dy);
      }
      final area = Path.from(path)
        ..lineTo(dots.last.dx, yFor(0))
        ..lineTo(dots.first.dx, yFor(0))
        ..close();
      canvas.drawPath(area, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    final dotPaint = Paint()..color = line;
    for (final dot in dots) {
      canvas.drawCircle(dot, 3, dotPaint);
    }

    final labelY = size.height - bottomGutter / 2;
    drawText(labels.first, Offset(xFor(0), labelY));
    if (values.length > 1) {
      drawText(
        labels.last,
        Offset(xFor(values.length - 1), labelY),
      );
    }
  }

  @override
  bool shouldRepaint(_EvolutionPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.labels != labels ||
      oldDelegate.line != line ||
      oldDelegate.fill != fill ||
      oldDelegate.grid != grid ||
      oldDelegate.labelStyle != labelStyle;
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

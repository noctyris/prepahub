import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'api/parse.dart';
import 'notes_stats.dart';
import 'subject_colors.dart';

String _fmt(double? value) {
  if (value == null) return '—';
  return value
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'\.?0+$'), '')
      .replaceAll('.', ',');
}

class NotesOverview extends StatefulWidget {
  final List<Semaine> semaines;
  final List<Note> extraNotes;
  final Map<String, int> subjectSeeds;
  final bool showNormalDistribution;

  const NotesOverview({
    super.key,
    required this.semaines,
    this.extraNotes = const [],
    this.subjectSeeds = const {},
    this.showNormalDistribution = true,
  });

  @override
  State<NotesOverview> createState() => _NotesOverviewState();
}

class _NotesOverviewState extends State<NotesOverview> {
  Map<String, double> _coefficients = const {};
  String? _subjectFilter;

  @override
  void initState() {
    super.initState();
    _loadCoefficients();
  }

  Future<void> _loadCoefficients() async {
    final coefficients = await SubjectCoefficientsStore.load();
    if (!mounted) return;
    setState(() => _coefficients = coefficients);
  }

  NotesAnalytics get _analytics =>
      NotesAnalytics(widget.semaines, widget.extraNotes);

  Color _subjectColor(String subject, ColorScheme cs) {
    final seed = widget.subjectSeeds[subject];
    return seed == null
        ? cs.primary
        : subjectPalette(seed, cs.brightness).accent;
  }

  Future<void> _editCoefficients() async {
    final analytics = _analytics;
    final result = await showDialog<Map<String, double>>(
      context: context,
      builder: (_) => _CoefficientDialog(
        subjects: analytics.subjects,
        coefficients: _coefficients,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _coefficients = result);
    await SubjectCoefficientsStore.save(result);
  }

  Future<void> _simulate() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SimulatorDialog(
        analytics: _analytics,
        coefficients: _coefficients,
        initialSubject: _subjectFilter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analytics = _analytics;
    if (analytics.allNotes.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final simple = analytics.simpleAverage();
    final weighted = analytics.weightedAverage(_coefficients) ?? simple;
    final filtered = _subjectFilter;
    final subjectColor = filtered == null
        ? cs.primary
        : _subjectColor(filtered, cs);
    final normal = widget.showNormalDistribution
        ? analytics.normalDistribution(subject: filtered)
        : null;
    final myAverage = widget.showNormalDistribution
        ? (filtered == null
              ? weighted
              : analytics.simpleAverage(subject: filtered))
        : null;
    final myBucket = gradeBucket(myAverage);

    final series = <_ChartSeries>[
      if (filtered == null)
        _ChartSeries(
          label: 'Toutes les matières',
          values: analytics.weeklySeries(),
          color: cs.primary,
          strong: true,
        ),
      if (filtered == null)
        for (final subject in analytics.subjects)
          _ChartSeries(
            label: subject,
            values: analytics.weeklySeries(subject: subject),
            color: _subjectColor(subject, cs),
          )
      else
        _ChartSeries(
          label: filtered,
          values: analytics.weeklySeries(subject: filtered),
          color: subjectColor,
          strong: true,
        ),
    ];

    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Aperçu', style: tt.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Moyenne brute ${_fmt(simple)}',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Coefficients des matières',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: _editCoefficients,
                ),
                IconButton(
                  tooltip: 'Simuler une note',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.calculate_outlined, size: 20),
                  onPressed: _simulate,
                ),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Pondérée',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _fmt(weighted),
                      style: tt.titleMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: const Text('Toutes'),
                      visualDensity: VisualDensity.compact,
                      selected: filtered == null,
                      onSelected: (_) => setState(() => _subjectFilter = null),
                    ),
                  ),
                  for (final subject in analytics.subjects)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(subject),
                        visualDensity: VisualDensity.compact,
                        selected: filtered == subject,
                        onSelected: (_) =>
                            setState(() => _subjectFilter = subject),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              filtered == null
                  ? 'Répartition des notes'
                  : 'Répartition · $filtered',
              style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _DistributionChart(
              counts: analytics.distribution(subject: filtered),
              color: subjectColor,
              normal: normal,
              highlightBucket: myBucket,
              myAverage: myAverage,
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Évolution de la moyenne',
              style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            _EvolutionChart(series: series, labels: analytics.weekLabels),
            if (series.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final item in series)
                    _LegendDot(color: item.color, label: item.label),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _CoefficientDialog extends StatefulWidget {
  final List<String> subjects;
  final Map<String, double> coefficients;

  const _CoefficientDialog({
    required this.subjects,
    required this.coefficients,
  });

  @override
  State<_CoefficientDialog> createState() => _CoefficientDialogState();
}

class _CoefficientDialogState extends State<_CoefficientDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final subject in widget.subjects)
        subject: TextEditingController(
          text: _fmt(widget.coefficients[subject] ?? 1),
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final result = <String, double>{};
    for (final entry in _controllers.entries) {
      final raw = entry.value.text.trim().replaceAll(',', '.');
      final value = double.tryParse(raw);
      result[entry.key] = value == null || value < 0
          ? 1
          : value.clamp(0.0, 20.0).toDouble();
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Coefficients'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pondère chaque matière. Une valeur plus élevée lui donne plus '
              'de poids dans la moyenne.',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.subjects.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final subject = widget.subjects[index];
                  return Row(
                    children: [
                      Expanded(child: Text(subject, style: tt.bodyMedium)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 84,
                        child: TextField(
                          controller: _controllers[subject],
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            suffixText: '×',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _SimulatorDialog extends StatefulWidget {
  final NotesAnalytics analytics;
  final Map<String, double> coefficients;
  final String? initialSubject;

  const _SimulatorDialog({
    required this.analytics,
    required this.coefficients,
    this.initialSubject,
  });

  @override
  State<_SimulatorDialog> createState() => _SimulatorDialogState();
}

class _SimulatorDialogState extends State<_SimulatorDialog> {
  late String? _subject;
  late final TextEditingController _target;

  @override
  void initState() {
    super.initState();
    final subjects = widget.analytics.subjects;
    _subject =
        widget.initialSubject != null &&
            subjects.contains(widget.initialSubject)
        ? widget.initialSubject
        : (subjects.isEmpty ? null : subjects.first);
    final current =
        widget.analytics.weightedAverage(widget.coefficients) ??
        widget.analytics.simpleAverage() ??
        10;
    _target = TextEditingController(
      text: (current + 0.5).clamp(0.0, 20.0).toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  double? get _targetValue {
    final raw = _target.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null) return null;
    return value.clamp(0.0, 20.0).toDouble();
  }

  double? get _required {
    final subject = _subject;
    final target = _targetValue;
    if (subject == null || target == null) return null;
    return widget.analytics.requiredGrade(
      subject: subject,
      target: target,
      coefficients: widget.coefficients,
    );
  }

  String get _resultText {
    final subject = _subject;
    final target = _targetValue;
    final required = _required;
    if (subject == null) return 'Ajoute d’abord une note.';
    if (target == null) return 'Indique une moyenne cible entre 0 et 20.';
    if (required == null) return 'Calcul indisponible pour cette matière.';
    if (required <= 0) {
      return 'Objectif déjà atteint : même un 0 ne ferait pas passer sous '
          '${_fmt(target)}.';
    }
    if (required > 20) {
      return 'Impossible avec une seule note : il faudrait '
          '${_fmt(required)}/20, au-delà de 20.';
    }
    return 'Il te faudrait environ ${_fmt(required)}/20 à la prochaine note '
        'de $subject.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final subjects = widget.analytics.subjects;
    final current = widget.analytics.weightedAverage(widget.coefficients);
    return AlertDialog(
      title: const Text('Simuler une note'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Moyenne pondérée actuelle : ${_fmt(current)}',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Matière',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _subject,
                  isExpanded: true,
                  isDense: true,
                  items: [
                    for (final subject in subjects)
                      DropdownMenuItem(value: subject, child: Text(subject)),
                  ],
                  onChanged: (value) => setState(() => _subject = value),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Moyenne visée',
                suffixText: '/20',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Card.filled(
              margin: EdgeInsets.zero,
              color: cs.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _resultText,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _DistributionChart extends StatelessWidget {
  final List<int> counts;
  final Color color;
  final ({double moyenne, double ecartType})? normal;
  final int? highlightBucket;
  final double? myAverage;

  const _DistributionChart({
    required this.counts,
    required this.color,
    this.normal,
    this.highlightBucket,
    this.myAverage,
  });

  static const _labels = ['0–4', '4–8', '8–12', '12–16', '16–20'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    var maxCount = 0;
    for (final count in counts) {
      if (count > maxCount) maxCount = count;
    }
    final normalValue = normal;
    final highlight = highlightBucket;
    final average = myAverage;

    return Column(
      children: [
        SizedBox(
          height: 96,
          child: Stack(
            children: [
              Row(
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
                                color: highlight == i
                                    ? cs.tertiary
                                    : cs.onSurfaceVariant,
                                fontWeight: highlight == i
                                    ? FontWeight.w700
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: maxCount == 0
                                  ? 0.0
                                  : 4 + 60 * counts[i] / maxCount,
                              decoration: BoxDecoration(
                                color: color,
                                border: highlight == i
                                    ? Border.all(color: cs.tertiary, width: 1.5)
                                    : null,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _labels[i],
                              style: tt.labelSmall?.copyWith(
                                color: highlight == i
                                    ? cs.tertiary
                                    : cs.onSurfaceVariant,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (normalValue != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _NormalCurvePainter(
                        mean: normalValue.moyenne,
                        standardDeviation: normalValue.ecartType,
                        color: cs.tertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (normalValue != null || average != null) ...[
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 2,
            children: [
              if (normalValue != null)
                Text(
                  'Normale : moyenne ${_fmt(normalValue.moyenne)} · '
                  'σ ${_fmt(normalValue.ecartType)}',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              if (average != null)
                Text(
                  'Ta moyenne : ${_fmt(average)}',
                  style: tt.labelSmall?.copyWith(
                    color: cs.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NormalCurvePainter extends CustomPainter {
  final double mean;
  final double standardDeviation;
  final Color color;

  const _NormalCurvePainter({
    required this.mean,
    required this.standardDeviation,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!standardDeviation.isFinite || standardDeviation <= 0) return;
    const left = 4.0;
    final right = size.width - 4;
    const top = 16.0;
    final bottom = size.height - 18;
    final height = bottom - top;
    if (right <= left || height <= 0) return;

    double xFor(double value) {
      final clamped = value.clamp(0.0, 20.0).toDouble();
      return left + (right - left) * clamped / 20;
    }

    double yFor(double value) {
      final z = (value - mean) / standardDeviation;
      return bottom - height * math.exp(-0.5 * z * z);
    }

    final line = Path();
    final fill = Path()..moveTo(xFor(0), bottom);
    for (var i = 0; i <= 80; i++) {
      final value = 20 * i / 80;
      final x = xFor(value);
      final y = yFor(value);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
      fill.lineTo(x, y);
    }
    fill
      ..lineTo(xFor(20), bottom)
      ..close();

    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.08));
    canvas.drawPath(
      line,
      Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _NormalCurvePainter oldDelegate) =>
      oldDelegate.mean != mean ||
      oldDelegate.standardDeviation != standardDeviation ||
      oldDelegate.color != color;
}

class _ChartSeries {
  final String label;
  final List<double?> values;
  final Color color;
  final bool strong;

  const _ChartSeries({
    required this.label,
    required this.values,
    required this.color,
    this.strong = false,
  });
}

class _EvolutionChart extends StatelessWidget {
  final List<_ChartSeries> series;
  final List<String> labels;

  const _EvolutionChart({required this.series, required this.labels});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (labels.length < 2) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          labels.isEmpty
              ? 'Pas encore de note à suivre.'
              : 'Une seule semaine notée pour le moment.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Semantics(
      label: 'Évolution des moyennes par semaine',
      child: SizedBox(
        height: 132,
        child: CustomPaint(
          painter: _EvolutionPainter(
            series: series,
            labels: labels,
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
  final List<_ChartSeries> series;
  final List<String> labels;
  final Color grid;
  final TextStyle labelStyle;

  const _EvolutionPainter({
    required this.series,
    required this.labels,
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
    if (chartWidth <= 0 || chartHeight <= 0 || labels.isEmpty) return;

    double yFor(double value) {
      final clamped = value.clamp(0.0, 20.0).toDouble();
      return topPadding + chartHeight * (1 - clamped / 20);
    }

    double xFor(int index) =>
        leftGutter +
        (labels.length == 1
            ? chartWidth / 2
            : chartWidth * index / (labels.length - 1));

    void drawText(String text, Offset center) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final x = (center.dx - painter.width / 2)
          .clamp(0.0, size.width - painter.width)
          .toDouble();
      painter.paint(canvas, Offset(x, center.dy - painter.height / 2));
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final value in const [0.0, 10.0, 20.0]) {
      final y = yFor(value);
      canvas.drawLine(Offset(leftGutter, y), Offset(size.width, y), gridPaint);
      drawText('${value.toInt()}', Offset(leftGutter / 2, y));
    }

    for (final item in series) {
      final linePaint = Paint()
        ..color = item.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = item.strong ? 2.4 : 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final dotPaint = Paint()..color = item.color;
      Offset? previous;
      for (var i = 0; i < item.values.length && i < labels.length; i++) {
        final value = item.values[i];
        if (value == null) continue;
        final point = Offset(xFor(i), yFor(value));
        if (previous != null) {
          canvas.drawLine(previous, point, linePaint);
        }
        canvas.drawCircle(point, item.strong ? 3.2 : 2.3, dotPaint);
        previous = point;
      }
    }

    final labelY = size.height - bottomGutter / 2;
    drawText(labels.first, Offset(xFor(0), labelY));
    if (labels.length > 1) {
      drawText(labels.last, Offset(xFor(labels.length - 1), labelY));
    }
  }

  @override
  bool shouldRepaint(_EvolutionPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.labels != labels ||
      oldDelegate.grid != grid ||
      oldDelegate.labelStyle != labelStyle;
}

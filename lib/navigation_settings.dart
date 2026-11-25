import 'package:material_ui/material_ui.dart';

import 'app_settings.dart';

class NavigationSettingsPage extends StatefulWidget {
  final AppSettings settings;

  const NavigationSettingsPage({super.key, required this.settings});

  @override
  State<NavigationSettingsPage> createState() => _NavigationSettingsPageState();
}

class _NavigationSettingsPageState extends State<NavigationSettingsPage> {
  late List<AppSection> _order;
  late Map<AppSection, SectionPlacement> _placement;

  @override
  void initState() {
    super.initState();
    _order = [
      ...widget.settings.navBar,
      ...widget.settings.navMenu,
      ...widget.settings.hiddenSections,
    ];
    _placement = {
      for (final section in _order)
        section: widget.settings.navBar.contains(section)
            ? SectionPlacement.bar
            : widget.settings.navMenu.contains(section)
            ? SectionPlacement.menu
            : SectionPlacement.hidden,
    };
  }

  int get _barCount => _placement.values
      .where((placement) => placement == SectionPlacement.bar)
      .length;

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final section = _order.removeAt(oldIndex);
      _order.insert(newIndex, section);
    });
  }

  bool _canUse(AppSection section, SectionPlacement placement) {
    if (section == AppSection.settings && placement == SectionPlacement.hidden) {
      return false;
    }
    if (placement != SectionPlacement.bar &&
        _placement[section] == SectionPlacement.bar &&
        _barCount <= 2) {
      return false;
    }
    return true;
  }

  String _blockedReason(AppSection section) =>
      section == AppSection.settings
      ? 'Les réglages doivent rester accessibles.'
      : 'Garde au moins deux pages dans la barre.';

  Future<void> _choosePlacement(AppSection section) async {
    final current = _placement[section]!;
    final picked = await showDialog<SectionPlacement>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(section.label),
        children: [
          for (final placement in SectionPlacement.values)
            ListTile(
              enabled: _canUse(section, placement),
              leading: Icon(switch (placement) {
                SectionPlacement.bar => Icons.view_agenda_outlined,
                SectionPlacement.menu => Icons.menu,
                SectionPlacement.hidden => Icons.visibility_off_outlined,
              }),
              title: Text(placement.label),
              subtitle: Text(
                _canUse(section, placement)
                    ? placement.description
                    : _blockedReason(section),
              ),
              trailing: current == placement
                  ? const Icon(Icons.check)
                  : null,
              onTap: _canUse(section, placement)
                  ? () => Navigator.pop(ctx, placement)
                  : null,
            ),
        ],
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    setState(() => _placement[section] = picked);
  }

  void _save() {
    final bar = [
      for (final section in _order)
        if (_placement[section] == SectionPlacement.bar) section,
    ];
    if (bar.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Garde au moins deux pages dans la barre du bas'),
        ),
      );
      return;
    }
    final menu = [
      for (final section in _order)
        if (_placement[section] == SectionPlacement.menu) section,
    ];
    final start = widget.settings.startSection;
    Navigator.pop(
      context,
      widget.settings.copyWith(
        navBar: bar,
        navMenu: menu,
        startSection:
            bar.contains(start) || menu.contains(start) ? start : bar.first,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      ),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        header: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Glisse les pages pour changer leur ordre. Touche une page pour '
            'la placer dans la barre du bas, le menu ou la masquer.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        itemCount: _order.length,
        onReorderItem: _reorder,
        itemBuilder: (context, index) {
          final section = _order[index];
          final placement = _placement[section]!;
          return Padding(
            key: ValueKey(section),
            padding: const EdgeInsets.only(bottom: 8),
            child: Card.filled(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                onTap: () => _choosePlacement(section),
                leading: Icon(section.icon),
                title: Text(section.label),
                subtitle: Text(placement.label),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

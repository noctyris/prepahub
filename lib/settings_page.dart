import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_settings.dart';
import 'devoirs.dart';
import 'devoirs_notifications.dart';
import 'devoirs_page.dart';
import 'navigation_settings.dart';

String _two(int n) => n.toString().padLeft(2, '0');

class SettingsPage extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSettingsChanged;
  final bool dynamicColorAvailable;

  const SettingsPage({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required this.dynamicColorAvailable,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DevoirSettings _devoirSettings = DevoirSettings.defaults;
  bool _notificationsAllowed = true;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final devoirSettings = await DevoirSettingsStore.load();
    var notificationsAllowed = true;
    if (DevoirNotifications.instance.isSupported) {
      try {
        notificationsAllowed = await DevoirNotifications.instance
            .areNotificationsAllowed();
      } catch (_) {
        notificationsAllowed = false;
      }
    }

    var version = '';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _devoirSettings = devoirSettings;
      _notificationsAllowed = notificationsAllowed;
      _version = version;
    });
  }

  Future<void> _update(AppSettings next) async {
    try {
      await widget.onSettingsChanged(next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer les réglages")),
      );
    }
  }

  Future<void> _openReminders() async {
    final result = await showModalBottomSheet<DevoirSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DevoirSettingsSheet(
        settings: _devoirSettings,
        allowed: _notificationsAllowed,
        supported: DevoirNotifications.instance.isSupported,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _devoirSettings = result);
    try {
      await DevoirSettingsStore.save(result);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer les rappels")),
      );
    }
    final allowed = await DevoirNotifications.instance
        .areNotificationsAllowed();
    if (!mounted) return;
    setState(() => _notificationsAllowed = allowed);
    unawaited(DevoirNotifications.instance.sync());
  }

  void _openLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'PrépaHub',
      applicationVersion: _version.isEmpty ? null : 'Version $_version',
    );
  }

  Future<void> _chooseStartPage() async {
    final settings = widget.settings;
    final available = [...settings.navBar, ...settings.navMenu];
    final picked = await showDialog<AppSection>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Page d'ouverture"),
        children: [
          for (final section in available)
            ListTile(
              leading: Icon(section.icon),
              title: Text(section.label),
              trailing: settings.startSection == section
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(ctx, section),
            ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == settings.startSection) return;
    await _update(settings.copyWith(startSection: picked));
  }

  Future<void> _chooseNotesLayout() async {
    final settings = widget.settings;
    final picked = await showDialog<NotesLayout>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Disposition des notes'),
        children: [
          for (final layout in NotesLayout.values)
            ListTile(
              leading: Icon(layout.icon),
              title: Text(layout.label),
              subtitle: Text(layout.description),
              trailing: settings.notesLayout == layout
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(ctx, layout),
            ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == settings.notesLayout) return;
    await _update(settings.copyWith(notesLayout: picked));
  }

  Future<void> _openNavigation() async {
    final next = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (_) => NavigationSettingsPage(settings: widget.settings),
      ),
    );
    if (next == null || !mounted) return;
    await _update(next);
  }

  String get _navSummary {
    final settings = widget.settings;
    final bar = settings.navBar.map((section) => section.label).join(' · ');
    final extras = <String>[
      if (settings.navMenu.isNotEmpty)
        '${settings.navMenu.length} dans le menu',
      if (settings.hiddenSections.isNotEmpty)
        '${settings.hiddenSections.length} '
            'masquée${settings.hiddenSections.length > 1 ? 's' : ''}',
    ];
    return extras.isEmpty
        ? 'Barre : $bar'
        : 'Barre : $bar\n${extras.join(' · ')}';
  }

  String get _reminderSummary {
    if (!DevoirNotifications.instance.isSupported) {
      return 'Non disponible sur cet appareil';
    }
    final parts = <String>[
      if (_devoirSettings.eveningEnabled)
        'Rappel du soir à ${_two(_devoirSettings.eveningHour)}h${_two(_devoirSettings.eveningMinute)}',
      if (_devoirSettings.endOfClassEnabled) 'Fin de cours',
    ];
    var summary = parts.isEmpty ? 'Désactivés' : parts.join(' · ');
    if (!_notificationsAllowed) {
      summary = '$summary · notifications non autorisées';
    }
    return summary;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final settings = widget.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionTitle(context, 'Apparence'),
          Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Thème',
                      style: tt.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Système'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Clair'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Sombre'),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (selection) {
                      unawaited(
                        _update(settings.copyWith(themeMode: selection.first)),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.palette_outlined),
                  title: const Text('Couleurs dynamiques'),
                  subtitle: Text(
                    widget.dynamicColorAvailable
                        ? 'Reprend les couleurs du fond d’écran.'
                        : 'Non disponible sur cet appareil.',
                  ),
                  value: widget.dynamicColorAvailable && settings.dynamicColor,
                  onChanged: widget.dynamicColorAvailable
                      ? (value) => unawaited(
                          _update(settings.copyWith(dynamicColor: value)),
                        )
                      : null,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Noir AMOLED'),
                  subtitle: const Text(
                    'Utilise un fond noir pur avec le thème sombre.',
                  ),
                  value: settings.amoledBlack,
                  onChanged: (value) =>
                      unawaited(_update(settings.copyWith(amoledBlack: value))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Notes'),
          Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: Icon(settings.notesLayout.icon),
              title: const Text('Disposition des notes'),
              subtitle: Text(
                '${settings.notesLayout.label} · '
                '${settings.notesLayout.description}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _chooseNotesLayout,
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Navigation'),
          Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text("Page d'ouverture"),
                  subtitle: Text(settings.startSection.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _chooseStartPage,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.view_sidebar_outlined),
                  title: const Text('Barre du bas et menu'),
                  subtitle: Text(_navSummary),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openNavigation,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Rappels'),
          Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Rappels de devoirs'),
              subtitle: Text(_reminderSummary),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openReminders,
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'À propos'),
          Card.filled(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('PrépaHub'),
                  subtitle: Text(
                    _version.isEmpty
                        ? 'Application de suivi de prépa'
                        : 'Version $_version',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Licences open source'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openLicenses,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

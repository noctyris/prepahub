import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/client.dart';
import 'notes.dart';
import 'colloscope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const PrepaHubApp());
}

class PrepaHubApp extends StatelessWidget {
  const PrepaHubApp({super.key});

  static const _seed = Color(0xFF3F51B5);

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final light = lightDynamic?.harmonized() ??
            ColorScheme.fromSeed(seedColor: _seed);
        final dark = darkDynamic?.harmonized() ??
            ColorScheme.fromSeed(
                seedColor: _seed, brightness: Brightness.dark);
        return MaterialApp(
          title: 'PrepaHub',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: light, useMaterial3: true),
          darkTheme: ThemeData(colorScheme: dark, useMaterial3: true),
          themeMode: ThemeMode.system,
          home: const RootPage(),
        );
      },
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        selectedIndex: currentPageIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.pie_chart),
            icon: Icon(Icons.home_outlined),
            label: 'Notes',
          ),
          NavigationDestination(
//            icon: Badge(label: Text('2'), child: Icon(Icons.calendar_month)),
            icon: Icon(Icons.calendar_month),
            label: 'Colloscope',
          ),
          NavigationDestination(
            icon: Icon(Icons.abc),
            label: '',
          ),
        ],
      ),
      body: <Widget>[
        /// Notes page
        NotesPage(),
        
        /// Colloscope
        ColloscopePage(),
        
        /// Idk
        const Center(child: Text('Rien pour le moment')),
        ][currentPageIndex],
    );
  }
}
/*  bool loading = true;
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
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (semaines !=  null) {
        return AppViewPage(
            semaines:   semaines!,
            onRefresh:  _refresh,
            onLogout:   _logout,
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
}*/

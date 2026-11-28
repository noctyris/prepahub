import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:local_auth/local_auth.dart';

/// Accès au déverrouillage biométrique ou au code de l'appareil.
class AppLockService {
  AppLockService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  static Future<bool> canAuthenticate() async {
    if (!isSupported) return false;
    try {
      final deviceSupported = await _auth.isDeviceSupported();
      final biometrics = await _auth.canCheckBiometrics;
      return deviceSupported || biometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({String? reason}) async {
    if (!isSupported) return false;
    try {
      return await _auth.authenticate(
        localizedReason:
            reason ?? 'Déverrouille PrépaHub pour accéder à tes données',
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Empêche l'accès à l'application tant que l'utilisateur ne s'est pas
/// authentifié. Le verrouillage se réactive quand l'application passe en
/// arrière-plan.
class AppLockGate extends StatefulWidget {
  final bool enabled;
  final Future<void> Function()? onDisable;
  final Widget child;

  const AppLockGate({
    super.key,
    required this.enabled,
    required this.child,
    this.onDisable,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locked = widget.enabled;
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void didUpdateWidget(covariant AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _locked = false;
    } else if (!oldWidget.enabled) {
      // Le réglage vient d'être activé depuis les réglages : l'utilisateur
      // vient déjà de s'authentifier, on ne redemande pas tout de suite.
      _locked = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enabled) return;
    if (state == AppLifecycleState.paused) {
      _locked = true;
    } else if (state == AppLifecycleState.resumed && _locked && !_checking) {
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (!mounted || _checking) return;
    _checking = true;
    final success = await AppLockService.authenticate();
    _checking = false;
    if (!mounted) return;
    setState(() {
      _locked = !success;
      _error = success ? null : 'Déverrouillage annulé ou indisponible.';
    });
  }

  Future<void> _disable() async {
    final disable = widget.onDisable;
    if (disable == null) return;
    final success = await AppLockService.authenticate(
      reason: 'Confirme ton identité pour désactiver le verrouillage',
    );
    if (!success || !mounted) return;
    await disable();
    if (!mounted) return;
    setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_locked) return widget.child;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    size: 40,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                Text('PrépaHub est verrouillé', style: tt.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Utilise ton empreinte, ton visage ou le code de '
                  'l’appareil pour accéder à tes données.',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: tt.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _checking ? null : _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: Text(_checking ? 'Vérification…' : 'Déverrouiller'),
                ),
                if (_error != null && widget.onDisable != null)
                  TextButton(
                    onPressed: _disable,
                    child: const Text('Désactiver le verrouillage'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

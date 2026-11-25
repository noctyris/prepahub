import 'package:material_ui/material_ui.dart';

import 'api/client.dart';
import 'api/parse.dart';

class LoginPage extends StatefulWidget {
  final ValueChanged<List<Semaine>> onSuccess;
  const LoginPage({super.key, required this.onSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final username = TextEditingController();
  final password = TextEditingController();
  final portal = TextEditingController(text: defaultPortal);
  bool busy = false;
  bool hidePassword = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadSavedPortal();
  }

  Future<void> _loadSavedPortal() async {
    try {
      final saved = await loadPortal();
      if (!mounted || portal.text != defaultPortal) return;
      portal.text = saved;
    } catch (_) {}
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    portal.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = username.text.trim();
    final pass = password.text;
    if (user.isEmpty || pass.isEmpty) {
      setState(() => error = 'Renseigne ton identifiant et ton mot de passe');
      return;
    }

    late final String base;
    try {
      base = normalizePortal(portal.text);
    } on NetworkException catch (e) {
      setState(() => error = e.message);
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });
    try {
      // On conserve le portail même si les identifiants sont refusés.
      await savePortal(base);
      final s = await getNotes(user, pass, portal: base);
      await saveCreds(
        Creds(username: user, password: pass, portal: base),
      );
      if (mounted) widget.onSuccess(s);
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on NetworkException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Connexion impossible');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.school_rounded,
                            size: 40, color: cs.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('PrépaHub',
                        textAlign: TextAlign.center, style: tt.headlineMedium),
                    const SizedBox(height: 4),
                    Text('Connecte-toi avec le compte de ton lycée',
                        textAlign: TextAlign.center,
                        style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 32),
                    TextField(
                      controller: portal,
                      enabled: !busy,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Portail',
                        hintText: defaultPortal,
                        helperText: "L'adresse du site PRÉPA+ de ton lycée",
                        prefixIcon: Icon(Icons.language),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: username,
                      enabled: !busy,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Identifiant',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: password,
                      enabled: !busy,
                      obscureText: hidePassword,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: hidePassword ? 'Afficher' : 'Masquer',
                          icon: Icon(hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => hidePassword = !hidePassword),
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: cs.onErrorContainer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(error!,
                                  style: tt.bodyMedium
                                      ?.copyWith(color: cs.onErrorContainer)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Se connecter'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

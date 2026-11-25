import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'parse.dart';

const defaultPortal = 'https://cpgedupuydelome.prepas-plus.fr';

/// Nettoie l'adresse saisie par l'utilisateur et vérifie qu'elle est utilisable.
/// Accepte un domaine sans schéma et retire un éventuel chemin de connexion ou
/// de notes collé depuis la barre d'adresse.
String normalizePortal(String input) {
  var value = input.trim();
  if (value.isEmpty) {
    throw const NetworkException('Adresse du portail vide');
  }
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw const NetworkException('Adresse du portail invalide');
  }

  var path = uri.path;
  for (final suffix in const [
    '/account/login/',
    '/account/login',
    '/colles/mes_notes/',
    '/colles/mes_notes',
  ]) {
    if (path.endsWith(suffix)) {
      path = path.substring(0, path.length - suffix.length);
      break;
    }
  }
  path = path.replaceAll(RegExp(r'/+$'), '');
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;
  const NetworkException(this.message);
  @override
  String toString() => message;
}

class Creds {
  final String username;
  final String password;
  final String portal;

  Creds({required this.username, required this.password, String? portal})
    : portal = portal ?? defaultPortal;
}

const _usernameKey = 'username';
const _passwordKey = 'password';
const _portalKey = 'portal';

const _secureStorage = FlutterSecureStorage();

Future<({String? user, String? pass})> _readSecureCreds() async {
  try {
    return (
      user: await _secureStorage.read(key: _usernameKey),
      pass: await _secureStorage.read(key: _passwordKey),
    );
  } catch (_) {
    // Le stockage sécurisé peut être indisponible (Linux sans trousseau,
    // tests, plateforme non prise en charge).
    return (user: null, pass: null);
  }
}

Future<bool> _writeSecureCreds(String user, String pass) async {
  try {
    await _secureStorage.write(key: _usernameKey, value: user);
    await _secureStorage.write(key: _passwordKey, value: pass);
    return true;
  } catch (_) {
    try {
      await _secureStorage.delete(key: _usernameKey);
      await _secureStorage.delete(key: _passwordKey);
    } catch (_) {}
    return false;
  }
}

Future<String> loadPortal() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_portalKey) ?? defaultPortal;
  try {
    return normalizePortal(raw);
  } catch (_) {
    return defaultPortal;
  }
}

Future<void> savePortal(String portal) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_portalKey, normalizePortal(portal));
}

Future<Creds?> loadCreds() async {
  var secure = await _readSecureCreds();
  var user = secure.user;
  var pass = secure.pass;
  final prefs = await SharedPreferences.getInstance();
  if (user == null || pass == null) {
    // Migration depuis l'ancien stockage en clair.
    user = prefs.getString(_usernameKey);
    pass = prefs.getString(_passwordKey);
    if (user != null && pass != null && await _writeSecureCreds(user, pass)) {
      await prefs.remove(_usernameKey);
      await prefs.remove(_passwordKey);
    }
  }
  if (user == null || pass == null) return null;
  return Creds(username: user, password: pass, portal: await loadPortal());
}

Future<void> saveCreds(Creds creds) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_portalKey, normalizePortal(creds.portal));
  final secured = await _writeSecureCreds(creds.username, creds.password);
  if (secured) {
    await prefs.remove(_usernameKey);
    await prefs.remove(_passwordKey);
  } else {
    // Repli si le trousseau de la plateforme est indisponible : l'application
    // reste utilisable, mais les identifiants ne sont pas chiffrés.
    await prefs.setString(_usernameKey, creds.username);
    await prefs.setString(_passwordKey, creds.password);
  }
}

Future<void> clearCreds() async {
  try {
    await _secureStorage.delete(key: _usernameKey);
    await _secureStorage.delete(key: _passwordKey);
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_usernameKey);
  await prefs.remove(_passwordKey);
  // Le portail est conservé pour préremplir la prochaine connexion.
}

class _Session {
  final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};
  static const _timeout = Duration(seconds: 20);

  String? cookie(String name) => _cookies[name];
  void close() => _client.close();

  Future<http.Response> get(Uri url) => _send('GET', url);

  Future<http.Response> postForm(
    Uri url,
    Map<String, String> form, {
    Map<String, String>? headers,
  }) => _send('POST', url, form: form, headers: headers);

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? form,
    Map<String, String>? headers,
  }) async {
    var m = method;
    var u = url;
    var f = form;
    for (var hops = 0; hops < 10; hops++) {
      final req = http.Request(m, u)..followRedirects = false;
      req.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android) PrepaHub';
      if (headers != null) req.headers.addAll(headers);
      if (_cookies.isNotEmpty) {
        req.headers['Cookie'] = _cookies.entries
            .map((e) => '${e.key}=${e.value}')
            .join('; ');
      }
      if (f != null) req.bodyFields = f;

      final stream = await _client.send(req).timeout(_timeout);
      final res = await http.Response.fromStream(stream).timeout(_timeout);
      _storeCookies(res);

      final loc = res.headers['location'];
      if ({301, 302, 303, 307, 308}.contains(res.statusCode) && loc != null) {
        u = u.resolve(loc);
        if (res.statusCode != 307 && res.statusCode != 308) {
          m = 'GET';
          f = null;
        }
        continue;
      }
      return res;
    }
    throw const NetworkException('Trop de redirections');
  }

  void _storeCookies(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return;
    for (final c in raw.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
      final parts = c.split(';');
      final kv = parts.first.trim();
      final i = kv.indexOf('=');
      if (i <= 0) continue;
      final name = kv.substring(0, i);
      final value = kv.substring(i + 1);
      final expired = parts
          .skip(1)
          .any((p) => p.trim().toLowerCase() == 'max-age=0');
      if (value.isEmpty || expired) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }
}

Future<List<Semaine>> getNotes(
  String username,
  String password, {
  String? portal,
}) async {
  final base = normalizePortal(portal ?? defaultPortal);
  final loginUrl = '$base/account/login/';
  final notesUrl = '$base/colles/mes_notes';
  final session = _Session();
  try {
    final page = await session.get(Uri.parse(loginUrl));
    if (page.statusCode != 200) {
      throw NetworkException(
        "Page de connexion inaccessible (${page.statusCode}). "
        "Vérifie l'adresse du portail.",
      );
    }
    final csrf =
        parse(page.body)
            .querySelector('input[name="csrfmiddlewaretoken"]')
            ?.attributes['value'] ??
        session.cookie('csrftoken');
    if (csrf == null) throw const NetworkException('Token CSRF introuvable');

    final login = await session.postForm(
      Uri.parse(loginUrl),
      {
        'csrfmiddlewaretoken': csrf,
        'login_view-current_step': 'auth',
        'auth-username': username,
        'auth-password': password,
      },
      headers: {'Referer': loginUrl},
    );
    if (login.statusCode >= 400) {
      throw NetworkException(
        'Erreur du serveur (${login.statusCode}). Réessaie plus tard.',
      );
    }
    final loginDoc = parse(login.body);
    if (loginDoc.querySelector('input[name="token-otp_token"]') != null) {
      throw const AuthException(
        "L'authentification à deux facteurs n'est pas prise en charge",
      );
    }
    if (loginDoc.querySelector('input[name="auth-password"]') != null) {
      throw const AuthException('Identifiant ou mot de passe incorrect');
    }

    final res = await session.get(Uri.parse(notesUrl));
    if (res.statusCode != 200) {
      throw NetworkException(
        'Erreur du serveur (${res.statusCode}). Réessaie plus tard.',
      );
    }
    if (parse(res.body).querySelector('input[name="auth-password"]') != null) {
      throw const AuthException('Session refusée par le serveur');
    }
    return parseNotes(res.body);
  } on AuthException {
    rethrow;
  } on NetworkException {
    rethrow;
  } on TimeoutException {
    throw const NetworkException(
      'Le serveur ne répond pas. Réessaie dans un instant.',
    );
  } catch (_) {
    throw const NetworkException(
      "Impossible de joindre le portail. Vérifie ta connexion et "
      "l'adresse saisie.",
    );
  } finally {
    session.close();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/client.dart';
import 'api/parse.dart';
import 'devoirs_notifications.dart';

/// Incrémenté après une actualisation automatique pour que les écrans ouverts
/// puissent recharger le cache sans action de l'utilisateur.
final ValueNotifier<int> notesRevision = ValueNotifier<int>(0);

/// Cache local des notes du portail, notes saisies à la main et empreinte des
/// dernières notes vues pour détecter les nouveautés.
class NotesStore {
  static const _userKey = 'notes_user';
  static const _localKey = 'notes_locales';
  static const _seenKey = 'notes_seen';
  static const _cacheDateKey = 'notes_cache_date';

  static Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/notes_cache.json');
  }

  /// Isole les données du compte courant. Un autre compte repart d'un cache
  /// et de notes locales vides.
  static Future<void> setUser(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final key = username.trim().toLowerCase();
    final previous = prefs.getString(_userKey);
    if (previous != null && previous != key) {
      await prefs.remove(_localKey);
      await prefs.remove(_seenKey);
      await prefs.remove(_cacheDateKey);
      try {
        final file = await _cacheFile();
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await prefs.setString(_userKey, key);
  }

  static Future<List<Semaine>> loadCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return [];
      return [
        for (final item in data)
          if (item is Map) Semaine.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveCache(List<Semaine> semaines) async {
    try {
      final file = await _cacheFile();
      await file.writeAsString(
        jsonEncode([for (final semaine in semaines) semaine.toJson()]),
        flush: true,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_cacheDateKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<DateTime?> loadCacheDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt(_cacheDateKey);
      if (millis == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    } catch (_) {
      return null;
    }
  }

  static Future<List<Note>> loadLocalNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localKey);
      if (raw == null) return [];
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return [
        for (final item in data)
          if (item is Map)
            Note.fromJson({...Map<String, dynamic>.from(item), 'local': true}),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveLocalNotes(List<Note> notes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _localKey,
        jsonEncode([for (final note in notes) note.toJson()]),
      );
    } catch (_) {}
  }

  static Future<Set<String>?> loadSeenSignatures() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_seenKey);
      return values?.toSet();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSeenSignatures(Set<String> signatures) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenKey, signatures.toList()..sort());
    } catch (_) {}
  }

  static String signature(Semaine semaine, Note note) {
    final value = note.note == null ? '' : note.note!.toStringAsFixed(2);
    return [
      semaine.numero ?? '',
      semaine.debut,
      note.matiere.trim().toLowerCase(),
      value,
      note.professeur.trim().toLowerCase(),
    ].join('|');
  }

  static Set<String> signatures(List<Semaine> semaines) => {
    for (final semaine in semaines)
      for (final note in semaine.notes)
        if (!note.local) signature(semaine, note),
  };
}

/// Actualise les notes sans passer par l'interface, pour l'actualisation
/// automatique et les rappels. Renvoie `false` si aucun identifiant n'est
/// disponible ou si le portail est injoignable.
Future<bool> refreshNotesInBackground({required bool notify}) async {
  try {
    final creds = await loadCreds();
    if (creds == null) return false;
    final semaines = await getNotes(
      creds.username,
      creds.password,
      portal: creds.portal,
    );
    await NotesStore.setUser(creds.username);
    await NotesStore.saveCache(semaines);
    final current = NotesStore.signatures(semaines);
    final previous = await NotesStore.loadSeenSignatures();
    await NotesStore.saveSeenSignatures(current);
    if (notify && previous != null) {
      final count = current.difference(previous).length;
      if (count > 0) {
        await DevoirNotifications.instance.notifyNewGrades(count);
      }
    }
    notesRevision.value++;
    return true;
  } catch (_) {
    return false;
  }
}

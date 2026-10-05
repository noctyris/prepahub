import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _repo = 'noctyris/prepahub';

class AppUpdate {
  final String version;
  final String url;
  const AppUpdate({required this.version, required this.url});
}

List<int> _parse(String v) {
  final core = v.trim().replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[-+]')).first;
  return [for (final p in core.split('.')) int.tryParse(p) ?? 0];
}

bool isNewerVersion(String a, String b) {
  final x = _parse(a), y = _parse(b);
  for (var i = 0; i < 3; i++) {
    final p = i < x.length ? x[i] : 0;
    final q = i < y.length ? y[i] : 0;
    if (p != q) return p > q;
  }
  return false;
}

Future<AppUpdate?> checkForUpdate() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final res = await http.get(
      Uri.https('api.github.com', '/repos/$_repo/releases/latest'),
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'PrepaHub',
      },
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = json['tag_name'] as String?;
    if (tag == null || !isNewerVersion(tag, info.version)) return null;

    var url = (json['html_url'] as String?) ?? 'https://github.com/$_repo/releases';
    for (final a in (json['assets'] as List? ?? const [])) {
      final name = (a as Map)['name'] as String? ?? '';
      if (name.endsWith('.apk')) {
        url = a['browser_download_url'] as String? ?? url;
        break;
      }
    }
    return AppUpdate(version: tag.replaceFirst(RegExp(r'^v'), ''), url: url);
  } catch (_) {
    return null;
  }
}

void showUpdateSnack(BuildContext context, AppUpdate u) {
  final m = ScaffoldMessenger.of(context);
  m.showSnackBar(SnackBar(
    content: Text('Mise à jour ${u.version} disponible'),
    duration: const Duration(seconds: 12),
    action: SnackBarAction(
      label: 'Télécharger',
      onPressed: () =>
          launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication),
    ),
  ));
}

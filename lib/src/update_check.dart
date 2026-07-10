import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';

const _latestReleaseApi =
    'https://api.github.com/repos/MrVamsiReddy/PG-Management-app/releases/latest';

/// Semantic compare of `x.y.z` strings (build metadata after `+` ignored).
bool isNewerVersion(String current, String latest) {
  List<int> parse(String v) => v
      .split('+')
      .first
      .split('.')
      .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
  final c = parse(current);
  final l = parse(latest);
  for (var i = 0; i < 3; i++) {
    final a = i < c.length ? c[i] : 0;
    final b = i < l.length ? l[i] : 0;
    if (b != a) return b > a;
  }
  return false;
}

/// Extracts an available update from a GitHub release JSON payload: the
/// version and this build surface's APK download URL, or null when the
/// installed app is already current (or the asset is missing).
({String version, String url})? updateFromRelease(
  Map<String, dynamic> release, {
  required String currentVersion,
  required String apkAsset,
}) {
  final tag = (release['tag_name'] as String? ?? '').replaceFirst('v', '');
  if (tag.isEmpty || !isNewerVersion(currentVersion, tag)) return null;
  final assets = (release['assets'] as List? ?? const []).cast<Map>();
  final asset = assets.where((a) => a['name'] == apkAsset).toList();
  if (asset.isEmpty) return null;
  return (version: tag, url: asset.first['browser_download_url'] as String);
}

/// Android-only, best-effort update prompt: compares the installed version
/// against the latest GitHub release and offers to download the new APK.
/// Installing it updates the app in place — data and login are kept.
Future<void> maybePromptUpdate(BuildContext context,
    {required String apkAsset}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  ({String version, String url})? update;
  try {
    final info = await PackageInfo.fromPlatform();
    final res = await http.get(Uri.parse(_latestReleaseApi),
        headers: {'Accept': 'application/vnd.github+json'});
    if (res.statusCode != 200) return;
    update = updateFromRelease(
      jsonDecode(res.body) as Map<String, dynamic>,
      currentVersion: info.version,
      apkAsset: apkAsset,
    );
  } catch (_) {
    return;
  }
  if (update == null || !context.mounted) return;
  final l = AppLocalizations.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update_alt),
      title: Text('${l.t('upd.title')} — v${update!.version}'),
      content: Text(l.t('upd.body')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.t('upd.later'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.t('upd.update'))),
      ],
    ),
  );
  if (go == true) {
    await launchUrl(Uri.parse(update.url),
        mode: LaunchMode.externalApplication);
  }
}

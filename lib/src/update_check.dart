import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_version.dart';
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

/// How often a running app looks for a new release.
const updateCheckInterval = Duration(minutes: 15);

/// After "Later", the same version isn't offered again for this long.
const updateSnooze = Duration(hours: 2);

bool _prompting = false;
String? _snoozedVersion;
DateTime? _snoozedUntil;

/// Android-only, best-effort update prompt: compares the installed version
/// against the latest GitHub release and offers to download the new APK.
/// Installing it updates the app in place — data and login are kept.
/// Never shows two prompts at once, and respects a recent "Later".
Future<void> maybePromptUpdate(BuildContext context,
    {required String apkAsset}) async {
  if (kIsWeb) return _maybePromptWebReload(context);
  if (defaultTargetPlatform != TargetPlatform.android) return;
  if (_prompting) return;
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
  if (update == null || !context.mounted || _prompting) return;
  final snoozedUntil = _snoozedUntil;
  if (update.version == _snoozedVersion &&
      snoozedUntil != null &&
      DateTime.now().isBefore(snoozedUntil)) {
    return;
  }
  final l = AppLocalizations.of(context);
  _prompting = true;
  final bool? go;
  try {
    go = await showDialog<bool>(
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
  } finally {
    _prompting = false;
  }
  if (go == true) {
    await launchUrl(Uri.parse(update.url),
        mode: LaunchMode.externalApplication);
  } else {
    _snoozedVersion = update.version;
    _snoozedUntil = DateTime.now().add(updateSnooze);
  }
}

/// GitHub Pages lets browsers keep files for 10 minutes. A reload sooner
/// than this after a deploy could load the old app again.
const webCacheWindow = Duration(minutes: 11);

/// The deployed web version from version.json, when a newer one than this
/// build has been live long enough for a reload to fetch it.
@visibleForTesting
String? newerWebVersion(
    {required String deployedJson,
    required DateTime? deployedAt,
    required DateTime now,
    String running = appVersion}) {
  final deployed = (jsonDecode(deployedJson) as Map)['version'] as String?;
  if (deployed == null || !isNewerVersion(running, deployed)) return null;
  if (deployedAt != null && now.difference(deployedAt) < webCacheWindow) {
    return null;
  }
  return deployed;
}

/// Web (browsers and iPhone home-screen apps): offers a reload when a newer
/// version has been deployed. The page only runs new code after a reload,
/// and home-screen apps on iPhone rarely reload on their own.
Future<void> _maybePromptWebReload(BuildContext context) async {
  if (_prompting) return;
  String? version;
  try {
    final url = Uri.base.resolve('version.json').replace(
        queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'});
    final res = await http.get(url);
    if (res.statusCode != 200) return;
    version = newerWebVersion(
        deployedJson: res.body,
        deployedAt: _httpDate(res.headers['last-modified']),
        now: DateTime.now());
  } catch (_) {
    return;
  }
  if (version == null || !context.mounted || _prompting) return;
  final snoozedUntil = _snoozedUntil;
  if (version == _snoozedVersion &&
      snoozedUntil != null &&
      DateTime.now().isBefore(snoozedUntil)) {
    return;
  }
  final l = AppLocalizations.of(context);
  _prompting = true;
  final bool? go;
  try {
    go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_alt),
        title: Text('${l.t('upd.title')} — v$version'),
        content: Text(l.t('upd.webBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.t('upd.later'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.t('upd.reload'))),
        ],
      ),
    );
  } finally {
    _prompting = false;
  }
  if (go == true) {
    // Same page, new query: the browser fetches it again.
    await launchUrl(
        Uri.base.replace(queryParameters: {
          ...Uri.base.queryParameters,
          'v': version,
        }),
        webOnlyWindowName: '_self');
  } else {
    _snoozedVersion = version;
    _snoozedUntil = DateTime.now().add(updateSnooze);
  }
}

DateTime? _httpDate(String? value) {
  if (value == null) return null;
  try {
    return parseHttpDate(value);
  } catch (_) {
    return null;
  }
}

/// Keeps a running app looking for updates: once when started, again
/// whenever the app comes back to the foreground, and every
/// [updateCheckInterval] while it stays open. Start it from a screen's
/// initState and stop it in dispose.
class UpdateWatch with WidgetsBindingObserver {
  UpdateWatch(this._state, this.apkAsset);

  final State _state;
  final String apkAsset;
  Timer? _timer;

  bool get isRunning => _timer != null;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
    _timer = Timer.periodic(updateCheckInterval, (_) => check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  void check() {
    if (_state.mounted) {
      unawaited(maybePromptUpdate(_state.context, apkAsset: apkAsset));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }
}

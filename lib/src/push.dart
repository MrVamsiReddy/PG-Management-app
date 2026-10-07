import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'supabase_config.dart';

bool _firebaseReady = false;

/// Whether this device should receive pushes (the Settings switch).
bool pushWanted = true;
StreamSubscription<String>? _tokenRefreshSub;

/// Best-effort Firebase init: if it fails (or on web, where push needs a
/// service worker + VAPID setup we haven't done), the app simply runs
/// without push notifications.
Future<void> initPush() async {
  if (kIsWeb) return;
  try {
    await Firebase.initializeApp();
    _firebaseReady = true;
  } catch (_) {
    _firebaseReady = false;
  }
}

/// Asks notification permission and stores this device's FCM token for the
/// signed-in account, so the push Edge Function can reach it.
Future<void> registerPushToken() async {
  if (!_firebaseReady || !pushWanted) return;
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();
    final token = await messaging.getToken();
    if (token != null) await _saveToken(token);
    _tokenRefreshSub ??= messaging.onTokenRefresh.listen(_saveToken);
  } catch (_) {}
}

Future<void> _saveToken(String token) async {
  if (!pushWanted) return;
  final client = supabaseOrNull;
  final user = client?.auth.currentUser;
  if (client == null || user == null) return;
  try {
    await client.from('push_tokens').upsert({
      'user_id': user.id,
      'email': (user.email ?? '').toLowerCase(),
      'token': token,
    }, onConflict: 'token');
  } catch (_) {}
}

/// Stops this device receiving pushes for the signed-in account: its token
/// is removed from the server. Call before signing out (the delete needs the
/// session).
Future<void> unregisterPushToken() async {
  if (!_firebaseReady) return;
  final client = supabaseOrNull;
  if (client == null || client.auth.currentUser == null) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await client.from('push_tokens').delete().eq('token', token);
    }
  } catch (_) {}
}

/// Runs [handler] whenever a push arrives while the app is open (the system
/// tray only shows pushes for backgrounded apps).
void onPushWhileOpen(void Function() handler) {
  if (!_firebaseReady) return;
  FirebaseMessaging.onMessage.listen((_) => handler());
}

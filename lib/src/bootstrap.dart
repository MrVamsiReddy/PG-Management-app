import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'push.dart';
import 'supabase_config.dart';

Future<AppState> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
        url: supabaseUrl, publishableKey: supabasePublishableKey);
    supabaseReady = true;
  } catch (_) {
    supabaseReady = false;
  }
  await initPush();
  final state = AppState();
  await state.loadLanguage();
  await state.restoreCloudSession();
  if (state.isLoggedIn) unawaited(registerPushToken());
  supabaseOrNull?.auth.onAuthStateChange.listen((change) {
    if (change.event == AuthChangeEvent.signedIn) {
      unawaited(registerPushToken());
    }
    if (change.event == AuthChangeEvent.passwordRecovery) {
      state.markPasswordRecovery();
    }
  });
  onPushWhileOpen(() => unawaited(state.refresh()));
  WidgetsBinding.instance.addObserver(_SystemThemeObserver(state));
  return state;
}

/// Rebuilds the app when the OS light/dark setting flips, so
/// ThemeMode.system (and the theme tokens) follow it live.
class _SystemThemeObserver with WidgetsBindingObserver {
  _SystemThemeObserver(this.state);
  final AppState state;
  @override
  void didChangePlatformBrightness() => state.systemThemeChanged();
}

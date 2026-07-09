import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_state.dart';
import 'push.dart';
import 'supabase_config.dart';

Future<AppState> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
    supabaseReady = true;
  } catch (_) {
    supabaseReady = false;
  }
  await initPush();
  final box = await Hive.openBox<dynamic>('pg_management');
  final state = AppState(box);
  await state.init();
  await state.restoreCloudSession();
  if (state.cloudMode) unawaited(registerPushToken());
  supabaseOrNull?.auth.onAuthStateChange.listen((change) {
    if (change.event == AuthChangeEvent.signedIn) unawaited(registerPushToken());
  });
  onPushWhileOpen(() => unawaited(state.refresh()));
  return state;
}

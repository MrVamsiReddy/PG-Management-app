import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app_state.dart';
import 'src/auth_screen.dart';
import 'src/home_shell.dart';
import 'src/l10n.dart';
import 'src/push.dart';
import 'src/supabase_config.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  try {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
    supabaseReady = true;
  } catch (_) {
    supabaseReady = false; // Offline or misconfigured: demo mode still works.
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
  runApp(PgManagementApp(state: state));
}

class PgManagementApp extends StatelessWidget {
  const PgManagementApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      // Rebuild the whole MaterialApp on state changes so the chosen locale
      // takes effect app-wide.
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PG Management',
          theme: buildAppTheme(),
          locale: state.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: !state.isLoggedIn
              ? const AuthScreen()
              : state.mustChangePassword
                  ? const SetPasswordScreen()
                  : const HomeShell(),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app_state.dart';
import 'src/auth_screen.dart';
import 'src/home_shell.dart';
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
  final box = await Hive.openBox<dynamic>('pg_management');
  final state = AppState(box);
  await state.init();
  await state.restoreCloudSession();
  runApp(PgManagementApp(state: state));
}

class PgManagementApp extends StatelessWidget {
  const PgManagementApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'PG Management',
        theme: buildAppTheme(),
        home: AnimatedBuilder(
          animation: state,
          builder: (context, _) => state.isLoggedIn
              ? const HomeShell()
              : const AuthScreen(),
        ),
      ),
    );
  }
}

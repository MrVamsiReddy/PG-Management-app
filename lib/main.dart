import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/app_state.dart';
import 'src/auth_screen.dart';
import 'src/bootstrap.dart';
import 'src/home_shell.dart';
import 'src/l10n.dart';
import 'src/theme.dart';

Future<void> main() async {
  final state = await bootstrap();
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

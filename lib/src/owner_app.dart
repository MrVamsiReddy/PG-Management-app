import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'admin_customers.dart';
import 'app_state.dart';
import 'auth_screen.dart';
import 'home_shell.dart';
import 'l10n.dart';
import 'theme.dart';

class OwnerAdminApp extends StatelessWidget {
  const OwnerAdminApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
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
          home: _home(),
        ),
      ),
    );
  }

  Widget _home() {
    if (!state.isLoggedIn) {
      return const AuthScreen(portals: [LoginPortal.owner, LoginPortal.admin]);
    }
    if (state.mustChangePassword) return const SetPasswordScreen();
    if (state.role == UserRole.tenant) return const _WrongApp();
    if (state.role == UserRole.admin) return const CustomerManagementScreen();
    return const HomeShell();
  }
}

class _WrongApp extends StatelessWidget {
  const _WrongApp();
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.info_outline, size: 48, color: primary),
              const SizedBox(height: 16),
              const Text(
                  'This is the owner/admin app. Tenant accounts use the tenant app.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: state.logout, child: const Text('Sign out')),
            ]),
          ),
        ),
      ),
    );
  }
}

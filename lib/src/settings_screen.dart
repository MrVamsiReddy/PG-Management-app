import 'package:flutter/material.dart';

import 'app_state.dart';
import 'audit_log_screen.dart';
import 'l10n.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('settings.title'))),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            _sectionLabel(context, l.t('settings.language')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: RadioGroup<AppLanguage>(
                groupValue: state.language,
                onChanged: (value) {
                  if (value == null) return;
                  state.setLanguage(value);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.t('settings.languageChanged'))));
                },
                child: Column(
                    children: AppLanguage.values
                        .map((lang) => RadioListTile<AppLanguage>(
                              value: lang,
                              title: Text(lang.nativeName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: lang == AppLanguage.english
                                  ? Text(l.t('settings.languageSub'))
                                  : null,
                            ))
                        .toList()),
              ),
            ),
            const SizedBox(height: 22),
            _sectionLabel(context, l.t('settings.appearance')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: RadioGroup<ThemeMode>(
                groupValue: state.themeMode,
                onChanged: (value) {
                  if (value != null) state.setThemeMode(value);
                },
                child: Column(children: [
                  for (final (mode, key, icon) in [
                    (
                      ThemeMode.system,
                      'settings.themeSystem',
                      Icons.brightness_auto_outlined
                    ),
                    (
                      ThemeMode.light,
                      'settings.themeLight',
                      Icons.light_mode_outlined
                    ),
                    (
                      ThemeMode.dark,
                      'settings.themeDark',
                      Icons.dark_mode_outlined
                    ),
                  ])
                    RadioListTile<ThemeMode>(
                      value: mode,
                      secondary: Icon(icon, color: primary, size: 21),
                      title: Text(l.t(key),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 22),
            _sectionLabel(context, l.t('settings.notifications')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                value: state.pushEnabled,
                onChanged: state.setPushEnabled,
                secondary: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: softTint,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.notifications_active_outlined,
                        color: primary, size: 21)),
                title: Text(l.t('settings.push'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(l.t('settings.pushSub')),
              ),
            ),
            if (state.isLoggedIn) ...[
              const SizedBox(height: 22),
              _sectionLabel(context, l.t('settings.account')),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  ListTile(
                    leading: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                            color: softTint,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.lock_outline,
                            color: primary, size: 21)),
                    title: Text(l.t('profile.changePassword'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(state.accountEmail ?? ''),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _changePassword(context, state, l),
                  ),
                  if (state.role == UserRole.owner)
                    ListTile(
                      leading: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                              color: softTint,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.history,
                              color: primary, size: 21)),
                      title: const Text('Activity log',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AuditLogScreen())),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 22),
            _sectionLabel(context, l.t('settings.appInfo')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: softTint,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.apartment_rounded,
                        color: primary, size: 21)),
                title: const Text('PG Management',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${l.t('settings.version')} 3.0'),
              ),
            ),
          ]),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: subtle)),
      );

  void _changePassword(
      BuildContext context, AppState state, AppLocalizations l) {
    final password = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.t('profile.changePassword')),
        content: TextField(
          controller: password,
          obscureText: true,
          autofocus: true,
          decoration:
              const InputDecoration(labelText: 'New password (6+ characters)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l.t('common.cancel'))),
          FilledButton(
              onPressed: () async {
                if (password.text.length < 6) return;
                final error = await state.changePassword(password.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                messenger.showSnackBar(
                    SnackBar(content: Text(error ?? 'Password updated.')));
              },
              child: Text(l.t('common.update'))),
        ],
      ),
    );
  }
}

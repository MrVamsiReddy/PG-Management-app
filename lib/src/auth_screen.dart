import 'package:flutter/material.dart';

import 'app_state.dart';
import 'l10n.dart';
import 'theme.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, this.portals});
  final List<LoginPortal>? portals;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final shown = portals ?? LoginPortal.values;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                            color: primary,
                            borderRadius: BorderRadius.circular(15)),
                        child: const Icon(Icons.apartment_rounded,
                            color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Text('PG Management',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(letterSpacing: -1.2)),
                    ]),
                    const SizedBox(height: 40),
                    Text(l.t('auth.choose'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(fontSize: 26)),
                    const SizedBox(height: 8),
                    Text(l.t('auth.chooseSub'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54)),
                    if (state.authNotice != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFBE9E7),
                            borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Icon(Icons.info_outline,
                              color: Color(0xFFC94444)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(state.authNotice!,
                                  style: const TextStyle(
                                      color: Color(0xFFC94444),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 28),
                    for (final p in shown) ...[
                      _portal(context, p, _portalIcon(p), _portalTitle(l, p),
                          _portalSubtitle(l, p)),
                      const SizedBox(height: 12),
                    ],
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  IconData _portalIcon(LoginPortal p) => switch (p) {
        LoginPortal.owner => Icons.business_center_outlined,
        LoginPortal.tenant => Icons.person_outline,
        LoginPortal.admin => Icons.admin_panel_settings_outlined,
      };

  String _portalTitle(AppLocalizations l, LoginPortal p) => switch (p) {
        LoginPortal.owner => l.t('auth.ownerLogin'),
        LoginPortal.tenant => l.t('auth.tenantLogin'),
        LoginPortal.admin => l.t('auth.adminLogin'),
      };

  String _portalSubtitle(AppLocalizations l, LoginPortal p) => switch (p) {
        LoginPortal.owner => l.t('auth.ownerSub'),
        LoginPortal.tenant => l.t('auth.tenantSub'),
        LoginPortal.admin => l.t('auth.adminSub'),
      };

  Widget _portal(BuildContext context, LoginPortal portal, IconData icon,
          String title, String subtitle) =>
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: primary)),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => LoginScreen(portal: portal))),
        ),
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.portal});
  final LoginPortal portal;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool obscure = true;
  bool busy = false;
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> forgotPassword() async {
    final l = AppLocalizations.of(context);
    final address = email.text.trim();
    if (!address.contains('@')) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.t('auth.enterEmailFirst'))));
      return;
    }
    final error = await AppScope.of(context).sendPasswordReset(address);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error ?? '${l.t('auth.resetSentTo')} $address.')));
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    setState(() => busy = true);
    final error = await state.signInCloud(
        email: email.text.trim(),
        password: password.text,
        portal: widget.portal);
    if (!mounted) return;
    setState(() => busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.error(error))));
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final loginTitle = switch (widget.portal) {
      LoginPortal.owner => l.t('auth.ownerLogin'),
      LoginPortal.tenant => l.t('auth.tenantLogin'),
      LoginPortal.admin => l.t('auth.adminLogin'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(loginTitle)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.t('auth.welcome'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontSize: 30)),
                      const SizedBox(height: 8),
                      Text(l.t('auth.welcomeSub'),
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Colors.black54)),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                            labelText: l.t('auth.email'),
                            prefixIcon: const Icon(Icons.mail_outline)),
                        validator: (v) => v == null || !v.contains('@')
                            ? l.t('auth.emailInvalid')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: l.t('auth.password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              icon: Icon(obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => obscure = !obscure)),
                        ),
                        validator: (v) => v == null || v.length < 6
                            ? l.t('auth.passwordShort')
                            : null,
                      ),
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: busy ? null : forgotPassword,
                              child: Text(l.t('auth.forgot')))),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white))
                            : Text(l.t('auth.signIn')),
                      ),
                      if (widget.portal == LoginPortal.admin) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const AdminSetupScreen())),
                          child: Text(l.t('auth.setupAdminLink')),
                        ),
                      ],
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SetPasswordScreen extends StatefulWidget {
  const SetPasswordScreen({super.key});
  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  bool busy = false;
  bool obscure = true;
  final formKey = GlobalKey<FormState>();
  final password = TextEditingController();
  final confirm = TextEditingController();

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    setState(() => busy = true);
    final error = await state.changePassword(password.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.error(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final first = state.displayName.split(' ').first;
    final greeting = state.displayName.isEmpty
        ? l.t('setpw.hello')
        : '${l.t('setpw.hello')}, $first';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_reset, size: 54, color: primary),
                      const SizedBox(height: 16),
                      Text(l.t('setpw.title'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontSize: 28)),
                      const SizedBox(height: 8),
                      Text(
                        '$greeting! ${l.t('setpw.sub')}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: Colors.black54),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: l.t('setpw.newPassword'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              icon: Icon(obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => obscure = !obscure)),
                        ),
                        validator: (v) => v == null || v.length < 6
                            ? l.t('auth.passwordShort')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: confirm,
                        obscureText: obscure,
                        decoration: InputDecoration(
                            labelText: l.t('setpw.confirm'),
                            prefixIcon: const Icon(Icons.lock_outline)),
                        validator: (v) =>
                            v != password.text ? l.t('setpw.mismatch') : null,
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white))
                            : Text(l.t('setpw.save')),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: busy ? null : state.logout,
                          child: Text(l.t('common.signOut'))),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminSetupScreen extends StatefulWidget {
  const AdminSetupScreen({super.key});
  @override
  State<AdminSetupScreen> createState() => _AdminSetupScreenState();
}

class _AdminSetupScreenState extends State<AdminSetupScreen> {
  bool busy = false;
  bool obscure = true;
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final setupKey = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    setupKey.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    final error = await AppScope.of(context).createAdmin(
      fullName: name.text,
      email: email.text,
      password: password.text,
      setupKey: setupKey.text,
    );
    if (!mounted) return;
    setState(() => busy = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).t('adminSetup.created'))));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('adminSetup.title'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.t('adminSetup.intro'),
                          style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                            labelText: l.t('adminSetup.fullName'),
                            prefixIcon: const Icon(Icons.person_outline)),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? l.t('adminSetup.nameReq')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                            labelText: l.t('auth.email'),
                            prefixIcon: const Icon(Icons.mail_outline)),
                        validator: (v) => v == null || !v.contains('@')
                            ? l.t('auth.emailInvalid')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: l.t('adminSetup.pwLabel'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              icon: Icon(obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => obscure = !obscure)),
                        ),
                        validator: (v) => v == null || v.length < 8
                            ? l.t('adminSetup.pwShort')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: setupKey,
                        obscureText: true,
                        decoration: InputDecoration(
                            labelText: l.t('adminSetup.setupKey'),
                            prefixIcon: const Icon(Icons.vpn_key_outlined)),
                        validator: (v) => v == null || v.isEmpty
                            ? l.t('adminSetup.setupKeyReq')
                            : null,
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white))
                            : Text(l.t('adminSetup.create')),
                      ),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

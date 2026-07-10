import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key, this.portals});
  final List<LoginPortal>? portals;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
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
                    Text('Choose how to sign in',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(fontSize: 26)),
                    const SizedBox(height: 8),
                    const Text(
                        'Accounts are created by your administrator. There is no public sign-up.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54)),
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
                      _portal(context, p, _portalIcon(p), '${p.label} login',
                          _portalSubtitle(p)),
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

  String _portalSubtitle(LoginPortal p) => switch (p) {
        LoginPortal.owner => 'Manage your PG business',
        LoginPortal.tenant => 'View your rent, notices and requests',
        LoginPortal.admin => 'Platform administration',
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
    final address = email.text.trim();
    if (!address.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter your email address above first.')));
      return;
    }
    final error = await AppScope.of(context).sendPasswordReset(address);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error ?? 'Reset link sent to $address.')));
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final state = AppScope.of(context);
    setState(() => busy = true);
    final error = await state.signInCloud(
        email: email.text.trim(),
        password: password.text,
        portal: widget.portal);
    if (!mounted) return;
    setState(() => busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.portal.label} login')),
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
                      Text('Welcome back',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontSize: 30)),
                      const SizedBox(height: 8),
                      Text(
                          'Sign in to your ${widget.portal.label.toLowerCase()} account.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Colors.black54)),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline)),
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Enter a valid email'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              icon: Icon(obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => obscure = !obscure)),
                        ),
                        validator: (v) => v == null || v.length < 6
                            ? 'Use at least 6 characters'
                            : null,
                      ),
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: busy ? null : forgotPassword,
                              child: const Text('Forgot password?'))),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white))
                            : const Text('Sign in'),
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
                          child: const Text('Set up a platform admin'),
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
    setState(() => busy = true);
    final error = await state.changePassword(password.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
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
                      Text('Set your password',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontSize: 28)),
                      const SizedBox(height: 8),
                      Text(
                        'Welcome${state.displayName.isEmpty ? '' : ', ${state.displayName.split(' ').first}'}! Your temporary password worked — now choose your own. You will use it for every sign-in from here on.',
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
                          labelText: 'New password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              icon: Icon(obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => obscure = !obscure)),
                        ),
                        validator: (v) => v == null || v.length < 6
                            ? 'Use at least 6 characters'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: confirm,
                        obscureText: obscure,
                        decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline)),
                        validator: (v) => v != password.text
                            ? 'Passwords do not match'
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
                            : const Text('Save & continue'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: busy ? null : state.logout,
                          child: const Text('Sign out')),
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
    messenger.showSnackBar(const SnackBar(
        content: Text('Admin account created. You can now sign in.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up platform admin')),
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
                      const Text(
                          'Create a platform admin using the server setup key. The key is verified on the server and never stored in the app.',
                          style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter a name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.mail_outline)),
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Enter a valid email'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: 'Password (8+ characters)',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                              icon: Icon(obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => obscure = !obscure)),
                        ),
                        validator: (v) => v == null || v.length < 8
                            ? 'Use at least 8 characters'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: setupKey,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Setup key',
                            prefixIcon: Icon(Icons.vpn_key_outlined)),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Enter the setup key'
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
                            : const Text('Create admin'),
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

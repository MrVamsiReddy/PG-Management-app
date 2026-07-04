import 'package:flutter/material.dart';

import 'app_state.dart';
import 'supabase_config.dart';
import 'theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool signup = false;
  bool obscure = true;
  bool busy = false;
  UserRole role = UserRole.owner;
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController(text: 'owner@pgmanagement.app');
  final password = TextEditingController(text: 'password');

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> forgotPassword() async {
    final address = email.text.trim();
    if (!address.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your email address above first.')));
      return;
    }
    final state = AppScope.of(context);
    final error = await state.sendPasswordReset(address);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ?? 'Reset link sent to $address. Open it, sign in, then change your password from Profile.'),
    ));
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final state = AppScope.of(context);
    if (supabaseOrNull == null) {
      // No cloud connection (offline or tests): fall back to local demo mode.
      state.login(signup ? UserRole.owner : role);
      return;
    }
    setState(() => busy = true);
    // Self-signup always creates an Owner account; tenants receive their
    // logins from their owner and are linked by membership at sign-in.
    final error = signup
        ? await state.signUpCloud(name: name.text.trim(), email: email.text.trim(), password: password.text, selectedRole: UserRole.owner)
        : await state.signInCloud(email: email.text.trim(), password: password.text);
    if (!mounted) return;
    setState(() => busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(15)),
                      child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Text('PG Management', style: Theme.of(context).textTheme.headlineMedium?.copyWith(letterSpacing: -1.2)),
                  ]),
                  const SizedBox(height: 44),
                  Text(signup ? 'Create your owner account' : 'Welcome back', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 30)),
                  const SizedBox(height: 8),
                  Text(signup ? 'Owners run the PG. Tenants get their sign-in details from you after onboarding.' : 'Sign in to manage your PG world.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
                  const SizedBox(height: 24),
                  if (signup) ...[
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter your name' : null,
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: password,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => obscure = !obscure)),
                    ),
                    validator: (v) => v == null || v.length < 6 ? 'Use at least 6 characters' : null,
                  ),
                  if (!signup)
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: busy ? null : forgotPassword, child: const Text('Forgot password?'))),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(signup ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 18),
                  if (!signup) ...[
                    const Text('Try demo mode as', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    const SizedBox(height: 8),
                    SegmentedButton<UserRole>(
                      segments: UserRole.values.map((r) => ButtonSegment(value: r, label: Text(r.label), icon: Icon(_roleIcon(r), size: 18))).toList(),
                      selected: {role},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) => setState(() => role = value.first),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => AppScope.of(context).login(role),
                      icon: const Icon(Icons.offline_bolt_outlined),
                      label: const Text('Try demo mode'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(signup ? 'Already have an account?' : 'New here?'),
                    TextButton(onPressed: busy ? null : () => setState(() => signup = !signup), child: Text(signup ? 'Sign in' : 'Create account')),
                  ]),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(14)),
                    child: const Row(children: [
                      Icon(Icons.cloud_done_outlined, color: primary),
                      SizedBox(width: 10),
                      Expanded(child: Text('Accounts sync your data to the cloud. Demo mode stores data on this device only and works offline.', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _roleIcon(UserRole role) => switch (role) {
        UserRole.owner => Icons.business_center_outlined,
        UserRole.tenant => Icons.person_outline,
        UserRole.admin => Icons.admin_panel_settings_outlined,
      };
}

/// Blocks the app after a first sign-in with a temporary password until the
/// user picks their own.
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.lock_reset, size: 54, color: primary),
                  const SizedBox(height: 16),
                  Text('Set your password', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome${state.displayName.isEmpty ? '' : ', ${state.displayName.split(' ').first}'}! Your temporary password worked — now choose your own. You will use it for every sign-in from here on.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: password,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => obscure = !obscure)),
                    ),
                    validator: (v) => v == null || v.length < 6 ? 'Use at least 6 characters' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirm,
                    obscureText: obscure,
                    decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline)),
                    validator: (v) => v != password.text ? 'Passwords do not match' : null,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Save & continue'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: busy ? null : state.logout, child: const Text('Sign out')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

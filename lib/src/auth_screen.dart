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

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    final state = AppScope.of(context);
    if (supabaseOrNull == null) {
      // No cloud connection (offline or tests): fall back to local demo mode.
      state.login(role);
      return;
    }
    setState(() => busy = true);
    final error = signup
        ? await state.signUpCloud(name: name.text.trim(), email: email.text.trim(), password: password.text, selectedRole: role)
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
                  Text(signup ? 'Create your account' : 'Welcome back', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 30)),
                  const SizedBox(height: 8),
                  Text(signup ? 'One app for your entire PG journey.' : 'Sign in to manage your PG world.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
                  const SizedBox(height: 28),
                  const Text('Continue as', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SegmentedButton<UserRole>(
                    segments: UserRole.values.map((r) => ButtonSegment(value: r, label: Text(r.label), icon: Icon(_roleIcon(r), size: 18))).toList(),
                    selected: {role},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) => setState(() => role = value.first),
                  ),
                  if (signup) ...[
                    const SizedBox(height: 18),
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
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () {}, child: const Text('Forgot password?'))),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(signup ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => AppScope.of(context).login(role),
                    icon: const Icon(Icons.offline_bolt_outlined),
                    label: const Text('Try demo mode'),
                  ),
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

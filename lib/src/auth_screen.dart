import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool signup = false;
  bool obscure = true;
  UserRole role = UserRole.owner;
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController(text: 'owner@pgmanagement.app');
  final password = TextEditingController(text: 'password');

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void submit() {
    if (!formKey.currentState!.validate()) return;
    AppScope.of(context).login(role);
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
                  FilledButton(onPressed: submit, child: Text(signup ? 'Create account' : 'Sign in')),
                  const SizedBox(height: 18),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(signup ? 'Already have an account?' : 'New here?'),
                    TextButton(onPressed: () => setState(() => signup = !signup), child: Text(signup ? 'Sign in' : 'Create account')),
                  ]),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(14)),
                    child: const Row(children: [
                      Icon(Icons.offline_bolt_outlined, color: primary),
                      SizedBox(width: 10),
                      Expanded(child: Text('Demo mode · your data is stored locally and works offline.', style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600))),
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

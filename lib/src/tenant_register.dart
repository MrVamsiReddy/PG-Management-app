import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// New-tenant registration, opened from the tenant login screen. It files a
/// request with the PG's owner; the login (and its temporary password, by
/// email) is created only when the owner accepts.
class TenantRegisterScreen extends StatefulWidget {
  const TenantRegisterScreen({super.key, this.initialCode});

  /// Registration code to start with (tests); otherwise read from the
  /// `?join=CODE` link the owner shared.
  final String? initialCode;

  @override
  State<TenantRegisterScreen> createState() => _TenantRegisterScreenState();
}

class _TenantRegisterScreenState extends State<TenantRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _code = TextEditingController(
      text: widget.initialCode ??
          (kIsWeb ? Uri.base.queryParameters['join'] ?? '' : ''));
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  String? _kycDoc;
  String? _pgName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_code.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkCode());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _checkCode() async {
    final name = await AppScope.of(context).pgNameForJoinCode(_code.text);
    if (mounted) setState(() => _pgName = name);
  }

  Future<void> _submit() async {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_kycDoc == null) {
      messenger.showSnackBar(SnackBar(content: Text(l.t('reg.idRequired'))));
      return;
    }
    setState(() => _busy = true);
    final result = await state.registerTenant(
        code: _code.text,
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        kycDoc: _kycDoc);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    // Back on the login screen, tell them what happens next.
    state.showLoginNotice(
        '${l.t('reg.sentTo')} ${result.pgName ?? ''}. ${l.t('reg.next')} ${_email.text.trim().toLowerCase()}. ${l.t('reg.firstLogin')}');
    Navigator.pop(context);
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? AppLocalizations.of(context).t('reg.required')
      : null;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('reg.title'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l.t('reg.intro'), style: TextStyle(color: subtle)),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _code,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                            labelText: l.t('reg.code'),
                            prefixIcon: const Icon(Icons.key_outlined),
                            helperText: _pgName == null
                                ? l.t('reg.codeHelp')
                                : '${l.t('reg.joining')} $_pgName'),
                        validator: _required,
                        onChanged: (_) => setState(() => _pgName = null),
                        onEditingComplete: _checkCode,
                        onTapOutside: (_) => _checkCode(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                            labelText: l.t('form.fullName'),
                            prefixIcon: const Icon(Icons.person_outline)),
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? l.t('reg.required')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                            labelText: l.t('form.phone'),
                            prefixIcon: const Icon(Icons.call_outlined)),
                        validator: (v) =>
                            (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length <
                                    10
                                ? l.t('reg.phoneInvalid')
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                            labelText: l.t('auth.email'),
                            prefixIcon: const Icon(Icons.mail_outline),
                            helperText: l.t('reg.emailHelp')),
                        validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                .hasMatch((v ?? '').trim())
                            ? null
                            : l.t('reg.emailInvalid'),
                      ),
                      const SizedBox(height: 16),
                      if (_kycDoc != null) ...[
                        ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: base64Image(_kycDoc!, height: 140)),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await pickImageBase64(context);
                          if (picked != null) {
                            setState(() => _kycDoc = picked);
                          }
                        },
                        icon: Icon(_kycDoc == null
                            ? Icons.badge_outlined
                            : Icons.check_circle_outline),
                        label: Text(_kycDoc == null
                            ? l.t('reg.addId')
                            : l.t('reg.changeId')),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.4))
                            : Text(l.t('reg.submit')),
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

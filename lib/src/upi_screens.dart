import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

String statusLabel(AppLocalizations l, String key) => switch (key) {
      'paid' => l.t('status.paid'),
      'pending' => l.t('status.pending'),
      'rejected' => l.t('status.rejected'),
      'overdue' => l.t('status.overdue'),
      _ => l.t('status.due'),
    };

Future<void> showUpiPayFlow(
    BuildContext context, AppState state, Payment payment) async {
  final l = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final pgId = state.pgIdForPayment(payment);
  final settings = await state.loadUpiSettings(pgId);
  if (!context.mounted) return;
  if (settings == null || !settings.usable) {
    messenger.showSnackBar(SnackBar(content: Text(l.t('upi.notEnabled'))));
    return;
  }

  final utr = TextEditingController();
  String? screenshot;
  var busy = false;

  await showAppSheet(
    context,
    StatefulBuilder(
      builder: (context, setSheet) => SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Text(l.t('upi.title'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Card(
                color: heroInk,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l.t('upi.payTo')}: ${settings.payeeName}',
                            style: const TextStyle(color: Colors.white)),
                        Text(settings.upiId,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 18)),
                        const SizedBox(height: 6),
                        Text('${l.t('upi.amount')}: ${inr(payment.balance)}',
                            style: const TextStyle(color: Colors.white70)),
                      ]),
                ),
              ),
              const SizedBox(height: 12),
              Text(l.t('upi.chooseApp'),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: subtle)),
              const SizedBox(height: 8),
              Row(children: [
                for (final app in const [
                  ('gpay', 'GPay'),
                  ('phonepe', 'PhonePe'),
                  ('paytm', 'Paytm'),
                ])
                  Expanded(
                      child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                        onPressed: () =>
                            _openUpiApp(messenger, settings, payment, app.$1),
                        child:
                            Text(app.$2, style: const TextStyle(fontSize: 12))),
                  )),
                Expanded(
                    child: OutlinedButton(
                        onPressed: () =>
                            _openUpiApp(messenger, settings, payment, 'other'),
                        child: Text(l.t('upi.otherApp'),
                            style: const TextStyle(fontSize: 12)))),
              ]),
              const SizedBox(height: 14),
              Text(l.t('upi.afterPay'),
                  style: TextStyle(fontSize: 12, color: subtle)),
              const SizedBox(height: 12),
              TextField(
                controller: utr,
                decoration: InputDecoration(
                    labelText: l.t('upi.utr'), hintText: l.t('upi.utrHint')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await pickImageBase64(context);
                  if (picked != null) setSheet(() => screenshot = picked);
                },
                icon: Icon(screenshot == null
                    ? Icons.image_outlined
                    : Icons.check_circle_outline),
                label: Text(l.t('upi.screenshot')),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        setSheet(() => busy = true);
                        final error = await state.submitPayment(
                          payment: payment,
                          utr: utr.text,
                          screenshot: screenshot == null
                              ? null
                              : base64Decode(screenshot!),
                        );
                        if (!context.mounted) return;
                        if (error != null) {
                          setSheet(() => busy = false);
                          messenger
                              .showSnackBar(SnackBar(content: Text(error)));
                          return;
                        }
                        Navigator.pop(context);
                        messenger.showSnackBar(
                            SnackBar(content: Text(l.t('upi.submitted'))));
                      },
                icon: const Icon(Icons.send_outlined),
                label: Text(l.t('upi.submit')),
              ),
            ]),
      ),
    ),
  );
}

/// The deep link for a specific UPI app (or the system chooser for 'other').
/// App-specific schemes work from mobile browsers too, which is what makes
/// the PWA able to open the installed app; on the web the generic chooser
/// uses Android's intent:// syntax (Chrome shows the UPI app picker).
Uri upiPayUri(String app,
    {required String upiId,
    required String payeeName,
    required int amount,
    bool web = false}) {
  final params = 'pa=${Uri.encodeComponent(upiId)}'
      '&pn=${Uri.encodeComponent(payeeName)}'
      '&am=$amount&cu=INR';
  return switch (app) {
    'gpay' => Uri.parse('tez://upi/pay?$params'),
    'phonepe' => Uri.parse('phonepe://pay?$params'),
    'paytm' => Uri.parse('paytmmp://pay?$params'),
    _ => web
        ? Uri.parse('intent://pay?$params#Intent;scheme=upi;end')
        : Uri.parse('upi://pay?$params'),
  };
}

Future<void> _openUpiApp(ScaffoldMessengerState messenger, UpiSettings s,
    Payment payment, String app) async {
  final uri = upiPayUri(app,
      upiId: s.upiId,
      payeeName: s.payeeName,
      amount: payment.balance,
      web: kIsWeb);
  try {
    final ok = await launchUrl(uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication);
    if (!ok) throw Exception();
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text(
            'That UPI app did not open — try another one, or pay using the ID shown above.')));
  }
}

class PaymentReviewScreen extends StatelessWidget {
  const PaymentReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final pending = state.pendingSubmissions;
    return Scaffold(
      appBar: AppBar(title: Text(l.t('upi.reviewTitle'))),
      body: pending.isEmpty
          ? Center(
              child: EmptyState(
                  icon: Icons.inbox_outlined, title: l.t('upi.reviewEmpty')))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children:
                  pending.map((s) => _card(context, state, l, s)).toList(),
            ),
    );
  }

  Widget _card(BuildContext context, AppState state, AppLocalizations l,
      UpiSubmission s) {
    final dup = state.duplicateOf(s);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(state.tenantName(s.tenantId),
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(inr(s.amount),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text('UTR: ${s.utr}', style: const TextStyle(fontSize: 13)),
          Text('${l.t('upi.submittedAt')}: ${formatWhen(s.submittedAt)}',
              style: TextStyle(fontSize: 12, color: subtle)),
          if (dup != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.warning_amber_rounded, color: coral, size: 18),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(l.t('upi.duplicate'),
                      style: const TextStyle(color: coral, fontSize: 12))),
            ]),
          ],
          if (s.screenshotPath != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: () => _viewProof(context, state, s),
                icon: const Icon(Icons.image_outlined),
                label: Text(l.t('upi.viewProof'))),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: () => _reject(context, state, l, s),
                    child: Text(l.t('upi.reject')))),
            const SizedBox(width: 10),
            Expanded(
                child: FilledButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final error = await state.confirmSubmission(s);
                      messenger.showSnackBar(SnackBar(
                          content: Text(error ?? l.t('upi.confirmed'))));
                    },
                    child: Text(l.t('upi.confirm')))),
          ]),
        ]),
      ),
    );
  }

  Future<void> _viewProof(
      BuildContext context, AppState state, UpiSubmission s) async {
    final url = await state.proofUrl(s.screenshotPath!);
    if (!context.mounted || url == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: Image.network(url, fit: BoxFit.contain)),
    );
  }

  void _reject(BuildContext context, AppState state, AppLocalizations l,
      UpiSubmission s) {
    final reason = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.t('upi.reject')),
        content: TextField(
          controller: reason,
          autofocus: true,
          decoration: InputDecoration(labelText: l.t('upi.rejectReason')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l.t('common.cancel'))),
          FilledButton(
              onPressed: () async {
                final error = await state.rejectSubmission(s, reason.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                messenger.showSnackBar(
                    SnackBar(content: Text(error ?? l.t('upi.rejected'))));
              },
              child: Text(l.t('upi.reject'))),
        ],
      ),
    );
  }
}

class UpiSettingsScreen extends StatefulWidget {
  const UpiSettingsScreen({super.key, required this.pgId});
  final String pgId;
  @override
  State<UpiSettingsScreen> createState() => _UpiSettingsScreenState();
}

class _UpiSettingsScreenState extends State<UpiSettingsScreen> {
  final _upiId = TextEditingController();
  final _payee = TextEditingController();
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    final s = await state.loadUpiSettings(widget.pgId);
    if (!mounted) return;
    setState(() {
      _upiId.text = s?.upiId ?? '';
      _payee.text = s?.payeeName ?? '';
      _enabled = s?.enabled ?? false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('upi.settingsTitle'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                  const FormLabel('UPI ID'),
                  TextField(
                      controller: _upiId,
                      decoration: InputDecoration(
                          hintText: 'name@bank', labelText: l.t('upi.upiId'))),
                  const SizedBox(height: 12),
                  const FormLabel('Payee'),
                  TextField(
                      controller: _payee,
                      decoration:
                          InputDecoration(labelText: l.t('upi.payeeName'))),
                  const SizedBox(height: 10),
                  SwitchListTile(
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                      title: Text(l.t('upi.enable'),
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final error = await state.saveUpiSettings(widget.pgId,
                            upiId: _upiId.text,
                            payeeName: _payee.text,
                            enabled: _enabled);
                        messenger.showSnackBar(SnackBar(
                            content: Text(error ?? l.t('upi.settingsSaved'))));
                      },
                      child: Text(l.t('common.update'))),
                ]),
    );
  }
}

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
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
  // Rent is never cached: reload from the database, then pay against the
  // live row (a rent change may have rewritten this due since the caller
  // built it). If the row vanished, fall back to the oldest unsettled due.
  await state.refresh();
  payment = state.payments.firstWhere((p) => p.id == payment.id,
      orElse: () => state.tenantDuePayment ?? payment);
  // The tenant pays everything they owe; the owner's confirmation settles
  // the oldest months first and keeps any extra as advance credit.
  final owed = state.balanceOf(payment.tenantId);
  final pgId = state.pgIdForPayment(payment);
  final settings = await state.loadUpiSettings(pgId);
  if (!context.mounted) return;
  if (settings == null || !settings.usable) {
    messenger.showSnackBar(SnackBar(content: Text(l.t('upi.notEnabled'))));
    return;
  }

  final utr = TextEditingController();
  final paidAmount = TextEditingController(text: '$owed');
  final note = TextEditingController();
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
              const SizedBox(height: 10),
              // 1. How much.
              Card(
                color: heroInk,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.t('upi.amount'),
                                style: const TextStyle(color: Colors.white70)),
                            Text(inr(owed),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 24)),
                            if (settings.payeeName.isNotEmpty)
                              Text('${l.t('upi.payTo')}: ${settings.payeeName}',
                                  style:
                                      const TextStyle(color: Colors.white70)),
                          ]),
                    ),
                    IconButton(
                        tooltip: l.t('upi.copyAmount'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: '$owed'));
                          messenger.showSnackBar(
                              SnackBar(content: Text(l.t('upi.amountCopied'))));
                        },
                        icon: const Icon(Icons.copy, color: Colors.white)),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              // 2. The owner's QR.
              Text(l.t('upi.scanThis'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Center(child: UpiQrView(settings: settings, size: 240)),
              if (settings.upiId.contains('@')) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: settings.upiId));
                    messenger.showSnackBar(
                        SnackBar(content: Text(l.t('upi.idCopied'))));
                  },
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                            child: Text(settings.upiId,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                        const SizedBox(width: 6),
                        Icon(Icons.copy, size: 15, color: subtle),
                      ]),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => shareUpiQr(messenger, l, settings, owed),
                  icon: const Icon(Icons.ios_share),
                  label: Text(l.t('upi.shareQr'))),
              const SizedBox(height: 14),
              // 3. Open a UPI app and scan.
              Text(l.t('upi.openApp'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(l.t('upi.howToScan'),
                  style: TextStyle(fontSize: 12, color: subtle)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final app in upiApps)
                  OutlinedButton(
                      onPressed: () async {
                        if (!await openUpiApp(app, settings)) {
                          messenger.showSnackBar(SnackBar(
                              content: Text(kIsWeb
                                  ? l.t('upi.openAppYourself')
                                  : '${app.name}: ${l.t('upi.appMissing')}')));
                        }
                      },
                      child: Text(app.name)),
              ]),
              const Divider(height: 32),
              // 4. Tell the owner.
              Text(l.t('upi.afterPay'),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                controller: paidAmount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: l.t('upi.paidAmount'), prefixText: '₹ '),
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
              if (screenshot != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(base64Decode(screenshot!),
                        height: 120, fit: BoxFit.cover)),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: utr,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: l.t('upi.utrOptional'),
                    hintText: l.t('upi.utrHint')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: l.t('upi.note')),
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
                          paidAmount: int.tryParse(paidAmount.text
                                  .replaceAll(RegExp(r'[^0-9]'), '')) ??
                              0,
                          note: note.text,
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

/// UPI apps a tenant can open from the pay screen to scan the owner's QR.
/// [link] is the app's payment-link style for [upiPayUri] (used on the web).
const upiApps = [
  (
    name: 'GPay',
    package: 'com.google.android.apps.nbu.paisa.user',
    link: 'gpay'
  ),
  (name: 'PhonePe', package: 'com.phonepe.app', link: 'phonepe'),
  (name: 'Paytm', package: 'net.one97.paytm', link: 'paytm'),
  (name: 'BHIM', package: 'in.org.npci.upiapp', link: 'other'),
];

/// Talks to MainActivity.kt, which starts an installed app by its own
/// launch intent.
const _appsChannel = MethodChannel('pg_management/apps');

/// Opens a UPI app.
/// * Android app: on its home screen (by package), where the tenant taps
///   Scan.
/// * Browser or iPhone home-screen app: through the app's own link — its
///   pay screen with the owner as payee when there is a UPI ID (the tenant
///   types the amount), else the app itself to scan the saved QR.
/// Returns false when it couldn't be opened.
Future<bool> openUpiApp(({String name, String package, String link}) app,
    UpiSettings settings) async {
  try {
    if (kIsWeb) {
      final ios = defaultTargetPlatform == TargetPlatform.iOS;
      final uri = settings.upiId.contains('@')
          ? upiPayUri(app.link,
              upiId: settings.upiId,
              payeeName: settings.payeeName,
              web: true,
              ios: ios)
          : upiAppHomeUri(app.link, ios: ios);
      return await launchUrl(uri, webOnlyWindowName: '_self');
    }
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await _appsChannel
            .invokeMethod<bool>('launch', {'package': app.package}) ??
        false;
  } catch (_) {
    return false;
  }
}

/// The picture of the owner's UPI QR: their uploaded image, else a QR made
/// from their UPI ID (same content as the QR their UPI app shows).
Future<({Uint8List bytes, String mime})?> upiQrPicture(
    UpiSettings settings) async {
  if (settings.hasQrImage) {
    try {
      return (bytes: base64Decode(settings.qrImage), mime: 'image/jpeg');
    } on FormatException {
      return null;
    }
  }
  if (!settings.upiId.contains('@')) return null;
  // A white card with a quiet margin, so the saved picture scans anywhere.
  const side = 900.0, margin = 60.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(const Rect.fromLTWH(0, 0, side + 2 * margin, side + 2 * margin),
        Paint()..color = Colors.white)
    ..translate(margin, margin);
  QrPainter(
    data:
        upiPayUri('other', upiId: settings.upiId, payeeName: settings.payeeName)
            .toString(),
    version: QrVersions.auto,
    gapless: true,
  ).paint(canvas, const Size(side, side));
  final image = await recorder
      .endRecording()
      .toImage((side + 2 * margin).toInt(), (side + 2 * margin).toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) return null;
  return (bytes: data.buffer.asUint8List(), mime: 'image/png');
}

/// Shares the owner's QR picture: the tenant can send it straight to a UPI
/// app or save it, then scan it from the gallery inside their UPI app.
Future<void> shareUpiQr(ScaffoldMessengerState messenger, AppLocalizations l,
    UpiSettings settings, int amount) async {
  final picture = await upiQrPicture(settings);
  if (picture == null) return;
  try {
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(picture.bytes,
            mimeType: picture.mime,
            name: picture.mime == 'image/png' ? 'upi-qr.png' : 'upi-qr.jpg')
      ],
      text: '${l.t('upi.amount')}: ${inr(amount)}',
    ));
  } catch (_) {
    if (!messenger.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l.t('upi.screenshotQr'))));
  }
}

/// The owner's QR on a white card (scannable in dark mode too).
class UpiQrView extends StatelessWidget {
  const UpiQrView({super.key, required this.settings, this.size = 220});
  final UpiSettings settings;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: settings.hasQrImage
            ? SizedBox(
                width: size,
                child: base64Image(settings.qrImage, fit: BoxFit.contain))
            : QrImageView(
                data: upiPayUri('other',
                        upiId: settings.upiId, payeeName: settings.payeeName)
                    .toString(),
                size: size,
                gapless: true),
      );
}

/// The deep link for a specific UPI app (or the system chooser for 'other').
/// App-specific schemes work from mobile browsers too, which is what makes
/// the PWA able to open the installed app; on the web the generic chooser
/// uses Android's intent:// syntax (Chrome shows the UPI app picker).
/// The amount is never prefilled: UPI apps reject prefilled intent payments
/// to personal (unverified) ids above ₹2,000, so the tenant always types
/// the amount — typed payments carry the normal UPI limit.
///
/// [ios]: iPhone (Safari or a home-screen web app), where Google Pay
/// answers to `gpay://` and the generic link is plain `upi://` (iOS has no
/// intent:// links).
Uri upiPayUri(String app,
    {required String upiId,
    required String payeeName,
    bool web = false,
    bool ios = false}) {
  final params = 'pa=${Uri.encodeComponent(upiId)}'
      '&pn=${Uri.encodeComponent(payeeName)}'
      '&tn=${Uri.encodeComponent('PG Rent')}'
      '&cu=INR';
  return switch (app) {
    'gpay' =>
      Uri.parse(ios ? 'gpay://upi/pay?$params' : 'tez://upi/pay?$params'),
    'phonepe' => Uri.parse('phonepe://pay?$params'),
    'paytm' => Uri.parse('paytmmp://pay?$params'),
    _ => web && !ios
        ? Uri.parse('intent://pay?$params#Intent;scheme=upi;end')
        : Uri.parse('upi://pay?$params'),
  };
}

/// Opens a UPI app itself (no payment details), for scanning the owner's QR
/// from a browser or iPhone home-screen app.
Uri upiAppHomeUri(String app, {bool ios = false}) => Uri.parse(switch (app) {
      'gpay' => ios ? 'gpay://' : 'tez://',
      'phonepe' => 'phonepe://',
      'paytm' => 'paytmmp://',
      _ => 'bhim://',
    });

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
    final dueRows = state.payments.where((p) => p.id == s.paymentId).toList();
    final due = dueRows.isEmpty ? null : dueRows.first.balance;
    final mismatch = due != null && due != s.amount;
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
          if (due != null)
            Text('${l.t('upi.dueAmount')}: ${inr(due)}',
                style: TextStyle(
                    fontSize: 12,
                    color: mismatch ? coral : subtle,
                    fontWeight: mismatch ? FontWeight.w700 : null)),
          if ((s.note ?? '').isNotEmpty)
            Text('${l.t('upi.note')}: ${s.note}',
                style: const TextStyle(fontSize: 12)),
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
  String _qrImage = '';

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
      _qrImage = s?.qrImage ?? '';
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
                  // The owner's own QR: the simplest, most reliable way to
                  // get paid on a personal UPI account.
                  FormLabel(l.t('upi.qrLabel')),
                  Text(l.t('upi.qrHelp'),
                      style: TextStyle(fontSize: 12, color: subtle)),
                  const SizedBox(height: 10),
                  if (_qrImage.isNotEmpty)
                    Center(
                        child: UpiQrView(
                            settings: UpiSettings(qrImage: _qrImage),
                            size: 200)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                          onPressed: () async {
                            // Sharper than photos: QR codes must stay
                            // scannable.
                            final picked = await pickImageBase64(context,
                                maxWidth: 1200, quality: 90);
                            if (picked != null) {
                              setState(() => _qrImage = picked);
                            }
                          },
                          icon: const Icon(Icons.qr_code_2),
                          label: Text(_qrImage.isEmpty
                              ? l.t('upi.uploadQr')
                              : l.t('upi.changeQr'))),
                    ),
                    if (_qrImage.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      IconButton(
                          tooltip: l.t('upi.removeQr'),
                          onPressed: () => setState(() => _qrImage = ''),
                          icon: const Icon(Icons.delete_outline, color: coral)),
                    ],
                  ]),
                  const SizedBox(height: 18),
                  const FormLabel('UPI ID'),
                  TextField(
                      controller: _upiId,
                      decoration: InputDecoration(
                          hintText: 'name@bank',
                          labelText: l.t('upi.upiIdOptional'))),
                  const SizedBox(height: 12),
                  FormLabel(AppLocalizations.of(context).t('upi.payee')),
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
                            enabled: _enabled,
                            qrImage: _qrImage);
                        messenger.showSnackBar(SnackBar(
                            content: Text(error ?? l.t('upi.settingsSaved'))));
                      },
                      child: Text(l.t('common.update'))),
                ]),
    );
  }
}

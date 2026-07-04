import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'app_state.dart';
import 'receipt_pdf.dart';
import 'theme.dart';
import 'widgets.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String filter = 'All';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tenant = state.role == UserRole.tenant;
    final due = state.tenantDuePayment;
    var items = tenant ? state.payments.where((e) => e.tenantId == state.currentTenantId).toList() : state.payments;
    if (filter != 'All') items = items.where((e) => e.displayStatus == filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(tenant ? 'My rent' : 'Rent collection'),
        actions: [
          if (!tenant)
            IconButton(tooltip: 'Export CSV', onPressed: () => _exportCsv(state), icon: const Icon(Icons.table_view_outlined)),
        ],
      ),
      floatingActionButton: tenant
          ? (due == null ? null : FloatingActionButton.extended(onPressed: () => _paymentFlow(state, due), icon: const Icon(Icons.lock_outline), label: const Text('Pay rent')))
          : FloatingActionButton.extended(onPressed: () => _recordPayment(state), icon: const Icon(Icons.add), label: const Text('Record payment')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        if (!tenant) ...[
          Row(children: [
            Expanded(child: StatCard(label: 'Collected', value: inr(state.collectedAmount), icon: Icons.check_circle_outline, tint: primary, caption: 'This month')),
            const SizedBox(width: 12),
            Expanded(child: StatCard(label: 'Outstanding', value: inr(state.dueAmount), icon: Icons.schedule, tint: coral, caption: 'Needs follow-up')),
          ]),
          const SizedBox(height: 20),
        ] else ...[
          Card(color: ink, child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(due == null ? 'ALL CAUGHT UP' : 'NEXT PAYMENT', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 10),
            Text(inr(due?.amount ?? 0), style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              due == null
                  ? 'No dues pending · Room ${state.currentTenantRoomLabel}'
                  : '${formatMonth(due.period)} · Due ${formatDay(due.dueDate)} · Room ${state.currentTenantRoomLabel}',
              style: const TextStyle(color: Colors.white60),
            ),
          ]))),
          const SizedBox(height: 20),
        ],
        SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: ['All', 'Paid', 'Due', 'Overdue'].map((e) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e), selected: filter == e, onSelected: (_) => setState(() => filter = e)))).toList())),
        const SizedBox(height: 14),
        ...items.map((payment) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
            leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long_outlined, color: primary)),
            title: Text(tenant ? formatMonth(payment.period) : state.tenantName(payment.tenantId), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${formatMonth(payment.period)} · ${payment.status == PaymentStatus.paid ? 'Paid ${formatDay(payment.paidDate!)}' : 'Due ${formatDay(payment.dueDate)}'}'),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(inr(payment.amount), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), StatusPill(payment.displayStatus)]),
            onTap: () => _receipt(context, state, payment),
          ),
        )),
        if (items.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'No payments found'),
      ]),
    );
  }

  Future<void> _exportCsv(AppState state) async {
    final csv = state.paymentsCsv();
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: 'rent-collection.csv')],
        fileNameOverrides: ['rent-collection.csv'],
        subject: 'Rent collection export',
      ));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied to clipboard — paste it into a spreadsheet.')));
    }
  }

  void _paymentFlow(AppState state, Payment payment) {
    var selected = 'UPI';
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(),
      Row(children: [const Icon(Icons.shield_outlined, color: primary), const SizedBox(width: 8), Text('Secure payment', style: Theme.of(context).textTheme.titleLarge), const Spacer(), const Text('PG PAY', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 22),
      Card(color: ink, child: Padding(padding: const EdgeInsets.all(17), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${formatMonthName(payment.period)} rent', style: const TextStyle(color: Colors.white60)), Text('Room ${state.currentTenantRoomLabel}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]), Text(inr(payment.amount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22))]))),
      const FormLabel('Choose payment method'),
      RadioGroup<String>(
        groupValue: selected,
        onChanged: (value) => setModalState(() => selected = value!),
        child: Column(children: [
          ('UPI', Icons.qr_code_2), ('Credit / Debit card', Icons.credit_card), ('Net banking', Icons.account_balance_outlined), ('Wallet', Icons.account_balance_wallet_outlined),
        ].map((method) => RadioListTile<String>(value: method.$1, title: Text(method.$1, style: const TextStyle(fontWeight: FontWeight.w700)), secondary: Icon(method.$2, color: primary), contentPadding: EdgeInsets.zero)).toList()),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: () {
        state.payRent(payment.id, selected);
        Navigator.pop(context);
        _success(state, payment.id);
      }, icon: const Icon(Icons.lock_outline), label: Text('Pay ${inr(payment.amount)}')),
      const SizedBox(height: 8), const Text('256-bit encrypted · Powered by demo payments', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.black45)),
    ])));
  }

  void _success(AppState state, String paymentId) => showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
    icon: const CircleAvatar(radius: 30, backgroundColor: primarySoft, child: Icon(Icons.check_rounded, color: primary, size: 34)),
    title: const Text('Payment successful!'),
    content: const Text('Your rent payment has been recorded and the receipt is ready.', textAlign: TextAlign.center),
    actionsAlignment: MainAxisAlignment.center,
    actions: [FilledButton(onPressed: () {
      Navigator.pop(dialogContext);
      final paid = state.payments.firstWhere((p) => p.id == paymentId);
      _receipt(context, state, paid);
    }, child: const Text('View receipt'))],
  ));

  void _recordPayment(AppState state) {
    if (state.tenants.isEmpty) return;
    var tenantId = state.tenants.first.id;
    var method = 'UPI';
    final amount = TextEditingController(text: '${state.roomById(state.tenants.first.roomId)?.rent ?? 9000}');
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Record a payment', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Tenant'),
      DropdownButtonFormField<String>(
        initialValue: tenantId,
        items: state.tenants.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(),
        onChanged: (v) => setModalState(() {
          tenantId = v!;
          amount.text = '${state.roomById(state.tenantById(v)!.roomId)?.rent ?? 9000}';
        }),
      ),
      const FormLabel('Amount received'), TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
      const FormLabel('Payment method'), DropdownButtonFormField<String>(initialValue: method, items: ['UPI', 'Cash', 'Bank transfer', 'Card'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setModalState(() => method = v!)),
      const SizedBox(height: 20), FilledButton(onPressed: () {
        final value = int.tryParse(amount.text) ?? 0;
        if (value <= 0) return;
        state.recordPayment(tenantId: tenantId, amount: value, method: method);
        Navigator.pop(context);
      }, child: const Text('Save & generate receipt')),
    ])));
  }

  void _receipt(BuildContext context, AppState state, Payment payment) {
    final digits = payment.id.replaceFirst('pay', '').padLeft(4, '0');
    final ref = digits.substring(digits.length - 4);
    showAppSheet(context, Column(mainAxisSize: MainAxisSize.min, children: [
      const SheetHandle(),
      const Icon(Icons.apartment_rounded, color: primary, size: 38),
      const SizedBox(height: 8), Text('PAYMENT RECEIPT', style: Theme.of(context).textTheme.titleLarge),
      Text('${state.pgNameForTenant(payment.tenantId)} · Receipt #PGM-$ref'),
      const Divider(height: 30),
      _receiptRow('Received from', state.tenantName(payment.tenantId)),
      _receiptRow('For', formatMonth(payment.period)),
      _receiptRow('Payment date', payment.paidDate == null ? '—' : formatDay(payment.paidDate!)),
      if (payment.method != null) _receiptRow('Method', payment.method!),
      _receiptRow('Status', payment.displayStatus),
      const Divider(height: 28),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL PAID', style: TextStyle(fontWeight: FontWeight.w800)), Text(inr(payment.amount), style: Theme.of(context).textTheme.headlineMedium)]),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => _exportReceipt(state, payment, ref, share: true), icon: const Icon(Icons.share_outlined), label: const Text('Share'))),
        const SizedBox(width: 8),
        Expanded(child: FilledButton.icon(onPressed: () => _exportReceipt(state, payment, ref, share: false), icon: const Icon(Icons.download_outlined), label: const Text('Download'))),
      ]),
    ]));
  }

  Future<void> _exportReceipt(AppState state, Payment payment, String ref, {required bool share}) async {
    final bytes = await buildReceiptPdf(
      pgName: state.pgNameForTenant(payment.tenantId),
      ref: 'PGM-$ref',
      amount: payment.amount,
      rows: [
        ('Received from', state.tenantName(payment.tenantId)),
        ('For', formatMonth(payment.period)),
        ('Payment date', payment.paidDate == null ? '-' : formatDay(payment.paidDate!)),
        if (payment.method != null) ('Method', payment.method!),
        ('Status', payment.displayStatus),
      ],
    );
    try {
      if (share) {
        await shareReceiptPdf(bytes, 'PGM-$ref.pdf');
      } else {
        await printReceiptPdf(bytes, 'PGM-$ref');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sharing is not available on this device.')));
    }
  }

  Widget _receiptRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))]));
}

class UtilitiesScreen extends StatelessWidget {
  const UtilitiesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final manager = state.role != UserRole.tenant;
    final myRoomId = state.currentTenant?.roomId;
    final entries = manager ? state.utilities : state.utilities.where((e) => e.roomId == myRoomId).toList();
    final myBill = entries.isEmpty ? null : entries.first;
    final occupants = (state.roomById(myRoomId ?? '')?.occupied ?? 1).clamp(1, 100);
    final myShare = myBill == null ? 0 : (myBill.amount / occupants).round();
    final myUnits = myBill == null ? 0 : (myBill.units / occupants).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Utility billing')),
      floatingActionButton: manager ? FloatingActionButton.extended(onPressed: () => _addReading(context, state), icon: const Icon(Icons.add), label: const Text('Add reading')) : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        PageHeader(title: manager ? '${formatMonthName(DateTime.now())} meter readings' : 'My electricity bill', subtitle: 'Rate: ₹${AppState.utilityRate} per unit · Split by occupied beds'),
        const SizedBox(height: 18),
        if (!manager) Card(color: primary, child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [const Icon(Icons.electric_bolt, color: Colors.white, size: 38), const SizedBox(width: 14), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('YOUR SHARE', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w800)), Text(inr(myShare), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)), Text(myBill == null ? 'No reading yet this month' : '$myUnits units · split across $occupants beds', style: const TextStyle(color: Colors.white70, fontSize: 12))])]))),
        if (!manager) const SizedBox(height: 15),
        ...entries.map((bill) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFFFF1DB), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.electric_meter_outlined, color: Color(0xFFCF7D28))), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Room ${state.roomNumber(bill.roomId)}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${bill.units} units consumed')])), StatusPill(bill.status.label)]),
            const Divider(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_meterValue('Previous', '${bill.previous}'), _meterValue('Current', '${bill.current}'), _meterValue('Bill', inr(bill.amount))]),
          ])),
        )),
      ]),
    );
  }

  Widget _meterValue(String label, String value) => Column(children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.black45)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.w800))]);

  void _addReading(BuildContext context, AppState state) {
    if (state.rooms.isEmpty) return;
    var roomId = state.rooms.first.id;
    final previous = TextEditingController();
    final current = TextEditingController();
    void prefill() {
      final latest = state.utilities.where((u) => u.roomId == roomId).toList();
      previous.text = latest.isEmpty ? '' : '${latest.first.current}';
    }
    prefill();
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Add meter reading', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Room'),
      DropdownButtonFormField<String>(
        initialValue: roomId,
        items: state.rooms.map((r) => DropdownMenuItem(value: r.id, child: Text('Room ${r.number} · Floor ${r.floor}'))).toList(),
        onChanged: (v) => setModalState(() { roomId = v!; prefill(); }),
      ),
      Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FormLabel('Previous'), TextField(controller: previous, keyboardType: TextInputType.number)])), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FormLabel('Current'), TextField(controller: current, keyboardType: TextInputType.number)]))]),
      const SizedBox(height: 20), FilledButton(onPressed: () {
        final old = int.tryParse(previous.text) ?? 0;
        final now = int.tryParse(current.text) ?? old;
        if (now < old) return;
        state.addUtilityBill(roomId: roomId, previous: old, current: now);
        Navigator.pop(context);
      }, child: const Text('Generate split bill')),
    ])));
  }
}

import 'package:flutter/material.dart';

import 'app_state.dart';
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
    var items = tenant ? state.payments.where((e) => e['tenant'] == AppState.currentTenantName).toList() : state.payments;
    if (filter != 'All') items = items.where((e) => e['status'] == filter).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tenant ? 'My rent' : 'Rent collection')),
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
            Text(due == null ? inr(0) : inr(due['amount'] as int), style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(due == null ? 'No dues pending · Room ${AppState.currentTenantBed}' : '${due['month']} · Due ${due['date']} · Room ${AppState.currentTenantBed}', style: const TextStyle(color: Colors.white60)),
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
            title: Text(tenant ? payment['month'] as String : payment['tenant'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${payment['month']} · Due ${payment['date']}'),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(inr(payment['amount'] as int), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), StatusPill(payment['status'] as String)]),
            onTap: () => _receipt(context, payment),
          ),
        )),
        if (items.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, title: 'No payments found'),
      ]),
    );
  }

  void _paymentFlow(AppState state, Map<String, dynamic> payment) {
    var selected = 'UPI';
    final month = payment['month'] as String;
    final amount = payment['amount'] as int;
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(),
      Row(children: [const Icon(Icons.shield_outlined, color: primary), const SizedBox(width: 8), Text('Secure payment', style: Theme.of(context).textTheme.titleLarge), const Spacer(), const Text('NESTORA PAY', style: TextStyle(fontSize: 10, color: primary, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 22),
      Card(color: ink, child: Padding(padding: const EdgeInsets.all(17), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${month.split(' ').first} rent', style: const TextStyle(color: Colors.white60)), const Text('Room ${AppState.currentTenantBed}', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]), Text(inr(amount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22))]))),
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
        state.payRent(payment['id'] as String, selected);
        Navigator.pop(context);
        _success(payment);
      }, icon: const Icon(Icons.lock_outline), label: Text('Pay ${inr(amount)}')),
      const SizedBox(height: 8), const Text('256-bit encrypted · Powered by demo payments', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.black45)),
    ])));
  }

  void _success(Map<String, dynamic> payment) => showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
    icon: const CircleAvatar(radius: 30, backgroundColor: primarySoft, child: Icon(Icons.check_rounded, color: primary, size: 34)),
    title: const Text('Payment successful!'),
    content: const Text('Your rent payment has been recorded and the receipt is ready.', textAlign: TextAlign.center),
    actionsAlignment: MainAxisAlignment.center,
    actions: [FilledButton(onPressed: () {
      Navigator.pop(dialogContext);
      _receipt(context, payment);
    }, child: const Text('View receipt'))],
  ));

  void _recordPayment(AppState state) {
    var tenant = state.tenants.first['name'] as String;
    var method = 'UPI';
    final amount = TextEditingController(text: '9500');
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Record a payment', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Tenant'), DropdownButtonFormField<String>(initialValue: tenant, items: state.tenants.map((e) => DropdownMenuItem(value: e['name'] as String, child: Text(e['name'] as String))).toList(), onChanged: (v) => setModalState(() => tenant = v!)),
      const FormLabel('Amount received'), TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
      const FormLabel('Payment method'), DropdownButtonFormField<String>(initialValue: method, items: ['UPI', 'Cash', 'Bank transfer', 'Card'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setModalState(() => method = v!)),
      const SizedBox(height: 20), FilledButton(onPressed: () {
        final value = int.tryParse(amount.text) ?? 0;
        if (value <= 0) return;
        state.recordPayment(tenant: tenant, amount: value, method: method);
        Navigator.pop(context);
      }, child: const Text('Save & generate receipt')),
    ])));
  }

  void _receipt(BuildContext context, Map<String, dynamic> payment) {
    final digits = (payment['id'] as String).replaceFirst('pay', '').padLeft(4, '0');
    final ref = digits.substring(digits.length - 4);
    showAppSheet(context, Column(mainAxisSize: MainAxisSize.min, children: [
    const SheetHandle(),
    const Icon(Icons.apartment_rounded, color: primary, size: 38),
    const SizedBox(height: 8), Text('PAYMENT RECEIPT', style: Theme.of(context).textTheme.titleLarge),
    Text('Nestora HSR · Receipt #NTR-$ref'),
    const Divider(height: 30),
    _receiptRow('Received from', payment['tenant'] as String),
    _receiptRow('For', payment['month'] as String),
    _receiptRow('Payment date', payment['date'] as String),
    if (payment['method'] != null) _receiptRow('Method', payment['method'] as String),
    _receiptRow('Status', payment['status'] as String),
    const Divider(height: 28),
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL PAID', style: TextStyle(fontWeight: FontWeight.w800)), Text(inr(payment['amount'] as int), style: Theme.of(context).textTheme.headlineMedium)]),
    const SizedBox(height: 20),
    Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.share_outlined), label: const Text('Share'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.download_outlined), label: const Text('Download')))]),
  ]));
  }

  Widget _receiptRow(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))]));
}

class UtilitiesScreen extends StatelessWidget {
  const UtilitiesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final manager = state.role != UserRole.tenant;
    final entries = manager ? state.utilities : state.utilities.where((e) => e['room'] == AppState.currentTenantRoom).toList();
    final myBill = entries.isEmpty ? null : entries.first;
    final room = state.rooms.firstWhere((e) => e['number'] == AppState.currentTenantRoom, orElse: () => <String, dynamic>{});
    final occupants = ((room['occupied'] as int?) ?? 1).clamp(1, 100);
    final myShare = myBill == null ? 0 : ((myBill['amount'] as int) / occupants).round();
    final myUnits = myBill == null ? 0 : ((myBill['units'] as int) / occupants).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Utility billing')),
      floatingActionButton: manager ? FloatingActionButton.extended(onPressed: () => _addReading(context, state), icon: const Icon(Icons.add), label: const Text('Add reading')) : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        PageHeader(title: manager ? 'July meter readings' : 'My electricity bill', subtitle: 'Rate: ₹8 per unit · Split by occupied beds'),
        const SizedBox(height: 18),
        if (!manager) Card(color: primary, child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [const Icon(Icons.electric_bolt, color: Colors.white, size: 38), const SizedBox(width: 14), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('YOUR SHARE', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w800)), Text(inr(myShare), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)), Text(myBill == null ? 'No reading yet this month' : '$myUnits units · split across $occupants beds', style: const TextStyle(color: Colors.white70, fontSize: 12))])]))),
        if (!manager) const SizedBox(height: 15),
        ...entries.map((item) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFFFF1DB), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.electric_meter_outlined, color: Color(0xFFCF7D28))), const SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Room ${item['room']}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${item['units']} units consumed')])), StatusPill(item['status'] as String)]),
            const Divider(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_meterValue('Previous', '${item['previous']}'), _meterValue('Current', '${item['current']}'), _meterValue('Bill', inr(item['amount'] as int))]),
          ])),
        )),
      ]),
    );
  }

  Widget _meterValue(String label, String value) => Column(children: [Text(label, style: const TextStyle(fontSize: 10, color: Colors.black45)), const SizedBox(height: 3), Text(value, style: const TextStyle(fontWeight: FontWeight.w800))]);

  void _addReading(BuildContext context, AppState state) {
    final room = TextEditingController();
    final previous = TextEditingController();
    final current = TextEditingController();
    showAppSheet(context, Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Add meter reading', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Room number'), TextField(controller: room, keyboardType: TextInputType.number),
      Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FormLabel('Previous'), TextField(controller: previous, keyboardType: TextInputType.number)])), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FormLabel('Current'), TextField(controller: current, keyboardType: TextInputType.number)]))]),
      const SizedBox(height: 20), FilledButton(onPressed: () {
        final old = int.tryParse(previous.text) ?? 0; final now = int.tryParse(current.text) ?? old; final units = now - old;
        if (room.text.isEmpty) return;
        state.addItem(state.utilities, {'id': 'u${DateTime.now().millisecondsSinceEpoch}', 'room': room.text.trim(), 'previous': old, 'current': now, 'units': units, 'amount': units * 8, 'status': 'Generated'});
        Navigator.pop(context);
      }, child: const Text('Generate split bill')),
    ]));
  }
}

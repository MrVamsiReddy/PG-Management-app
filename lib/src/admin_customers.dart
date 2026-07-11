import 'package:flutter/material.dart';

import 'app_state.dart';
import 'audit_log_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});
  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  Future<List<Customer>>? _future;

  void _reload(AppState state) =>
      setState(() => _future = state.loadCustomers());

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _future ??= state.loadCustomers();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
              tooltip: 'Audit log',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AuditLogScreen())),
              icon: const Icon(Icons.history)),
          IconButton(
              tooltip: 'Sign out',
              onPressed: state.logout,
              icon: const Icon(Icons.logout))
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _create(context, state),
          icon: const Icon(Icons.add),
          label: const Text('New customer')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(state),
        child: FutureBuilder<List<Customer>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final customers = snap.data ?? [];
            if (customers.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyState(
                    icon: Icons.business_outlined, title: 'No customers yet')
              ]);
            }
            return ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                children: [
                  PageHeader(
                      title: '${customers.length} customers',
                      subtitle:
                          '${customers.where((c) => c.enabled).length} enabled'),
                  const SizedBox(height: 14),
                  ...customers.map((c) => _card(context, state, c)),
                ]);
          },
        ),
      ),
    );
  }

  Widget _card(BuildContext context, AppState state, Customer c) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(c.businessName,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                        '${c.ownerName.isEmpty ? 'Owner' : c.ownerName} · ${c.ownerEmail}',
                        style: const TextStyle(fontSize: 12)),
                  ])),
              StatusPill(
                  c.expired ? 'Expired' : (c.enabled ? 'Enabled' : 'Disabled')),
            ]),
            const Divider(height: 22),
            Row(children: [
              Expanded(
                child: Text(
                    'Plan: ${c.plan}${c.expiresAt == null ? '' : ' · ${c.expired ? 'expired' : 'renews'} ${formatFullDate(c.expiresAt!)}'}',
                    style: TextStyle(fontSize: 12, color: subtle)),
              ),
              TextButton(
                  onPressed: () => _viewPgs(context, state, c),
                  child: const Text('View PGs')),
              Switch(
                  value: c.enabled,
                  onChanged: (v) async {
                    final error = await state.setCustomerStatus(c.id, v);
                    if (!context.mounted) return;
                    if (error != null) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(error)));
                    }
                    _reload(state);
                  }),
              IconButton(
                  tooltip: 'Delete customer',
                  onPressed: () => _deleteCustomer(context, state, c),
                  icon: const Icon(Icons.delete_outline, color: coral)),
            ]),
          ]),
        ),
      );

  Future<void> _deleteCustomer(
      BuildContext context, AppState state, Customer c) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete customer?'),
        content: Text(
            'This permanently deletes ${c.businessName}, its owner and tenant accounts, and all PGs, rooms, tenants, payments and files. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: coral),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete permanently')),
        ],
      ),
    );
    if (confirmed != true) return;
    messenger
        .showSnackBar(SnackBar(content: Text('Deleting ${c.businessName}…')));
    final error = await state.deleteCustomer(c.id);
    messenger.showSnackBar(
        SnackBar(content: Text(error ?? '${c.businessName} deleted.')));
    _reload(state);
  }

  Future<void> _viewPgs(
      BuildContext context, AppState state, Customer c) async {
    var pgs = await state.loadCustomerPgs(c.id);
    if (!context.mounted) return;
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, setSheet) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SheetHandle(),
                      Text('${c.businessName} · PGs',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 12),
                      if (pgs.isEmpty)
                        const EmptyState(
                            icon: Icons.apartment_outlined,
                            title: 'No PGs yet — the owner sets these up')
                      else
                        ...pgs.map((pg) => ListTile(
                            leading: const Icon(Icons.apartment_outlined,
                                color: primary),
                            title: Text(pg.name),
                            trailing: IconButton(
                                tooltip: 'Delete PG',
                                icon: const Icon(Icons.delete_outline,
                                    color: coral),
                                onPressed: () async {
                                  final error = await _deletePg(
                                      context, state, c, pg.id, pg.name);
                                  if (error == null) {
                                    pgs = pgs
                                        .where((e) => e.id != pg.id)
                                        .toList();
                                    setSheet(() {});
                                  }
                                }))),
                    ])));
  }

  Future<String?> _deletePg(BuildContext context, AppState state, Customer c,
      String pgId, String pgName) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $pgName?'),
        content: const Text(
            'This removes the property and its rooms from the customer\'s account. Blocked while tenants live there. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: coral),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return 'cancelled';
    final error = await state.adminRemovePg(customerId: c.id, pgId: pgId);
    messenger
        .showSnackBar(SnackBar(content: Text(error ?? '$pgName deleted.')));
    return error;
  }

  void _create(BuildContext context, AppState state) {
    final formKey = GlobalKey<FormState>();
    final business = TextEditingController();
    final ownerName = TextEditingController();
    final ownerEmail = TextEditingController();
    final phone = TextEditingController();
    var plan = 'free';
    final messenger = ScaffoldMessenger.of(context);
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, setSheet) => SingleChildScrollView(
                child: Form(
                    key: formKey,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SheetHandle(),
                          Text('New customer',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 6),
                          const Text(
                              'Creates the PG business and its owner login. The workspace starts empty. Subscription: 30 days from today.'),
                          const FormLabel('Business name'),
                          TextFormField(
                              controller: business,
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Enter a business name'
                                  : null),
                          const FormLabel('Owner name'),
                          TextFormField(
                              controller: ownerName,
                              textCapitalization: TextCapitalization.words),
                          const FormLabel('Owner email'),
                          TextFormField(
                              controller: ownerEmail,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) => v == null || !v.contains('@')
                                  ? 'Enter a valid email'
                                  : null),
                          const FormLabel('Phone'),
                          TextFormField(
                              controller: phone,
                              keyboardType: TextInputType.phone),
                          const FormLabel('Subscription plan'),
                          DropdownButtonFormField<String>(
                            initialValue: plan,
                            items: const [
                              DropdownMenuItem(
                                  value: 'free', child: Text('Free')),
                              DropdownMenuItem(
                                  value: 'pro', child: Text('Pro')),
                              DropdownMenuItem(
                                  value: 'business', child: Text('Business')),
                            ],
                            onChanged: (v) =>
                                setSheet(() => plan = v ?? 'free'),
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                final result = await state.createCustomer(
                                    businessName: business.text,
                                    ownerName: ownerName.text,
                                    ownerEmail: ownerEmail.text,
                                    phone: phone.text,
                                    plan: plan);
                                if (!context.mounted) return;
                                if (result.error != null) {
                                  messenger.showSnackBar(
                                      SnackBar(content: Text(result.error!)));
                                  return;
                                }
                                Navigator.pop(context);
                                _reload(state);
                                _showCredentials(
                                    context,
                                    ownerEmail.text.trim(),
                                    result.tempPassword);
                              },
                              child: const Text('Create customer')),
                        ])))));
  }

  void _showCredentials(
      BuildContext context, String email, String? tempPassword) {
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Owner account created'),
              content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Share these credentials with the owner. They must change the password at first sign-in.'),
                    const SizedBox(height: 12),
                    Text('Email: $email',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Temporary password: ${tempPassword ?? '—'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Done'))
              ],
            ));
  }
}

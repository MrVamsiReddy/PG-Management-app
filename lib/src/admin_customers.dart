import 'package:flutter/material.dart';

import 'app_state.dart';
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
              StatusPill(c.enabled ? 'Enabled' : 'Disabled'),
            ]),
            const Divider(height: 22),
            Row(children: [
              Text('Plan: ${c.plan}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const Spacer(),
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
            ]),
          ]),
        ),
      );

  Future<void> _viewPgs(
      BuildContext context, AppState state, Customer c) async {
    final names = await state.loadCustomerPgNames(c.id);
    if (!context.mounted) return;
    showAppSheet(
        context,
        Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Text('${c.businessName} · PGs',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              if (names.isEmpty)
                const EmptyState(
                    icon: Icons.apartment_outlined,
                    title: 'No PGs yet — the owner sets these up')
              else
                ...names.map((n) => ListTile(
                    leading:
                        const Icon(Icons.apartment_outlined, color: primary),
                    title: Text(n))),
            ]));
  }

  void _create(BuildContext context, AppState state) {
    final formKey = GlobalKey<FormState>();
    final business = TextEditingController();
    final ownerName = TextEditingController();
    final ownerEmail = TextEditingController();
    final phone = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showAppSheet(
        context,
        SingleChildScrollView(
            child: Form(
                key: formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SheetHandle(),
                      Text('New customer',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 6),
                      const Text(
                          'Creates the PG business and its owner login. The workspace starts empty.'),
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
                          controller: phone, keyboardType: TextInputType.phone),
                      const SizedBox(height: 18),
                      FilledButton(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) return;
                            final result = await state.createCustomer(
                                businessName: business.text,
                                ownerName: ownerName.text,
                                ownerEmail: ownerEmail.text,
                                phone: phone.text);
                            if (!context.mounted) return;
                            if (result.error != null) {
                              messenger.showSnackBar(
                                  SnackBar(content: Text(result.error!)));
                              return;
                            }
                            Navigator.pop(context);
                            _reload(state);
                            _showCredentials(context, ownerEmail.text.trim(),
                                result.tempPassword);
                          },
                          child: const Text('Create customer')),
                    ]))));
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

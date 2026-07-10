import 'package:flutter/material.dart';

import 'app_state.dart';
import 'widgets.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  Future<List<AuditLog>>? _future;

  static const _labels = {
    'customer_created': 'Customer created',
    'customer_enabled': 'Customer enabled',
    'customer_disabled': 'Customer disabled',
    'admin_created': 'Admin created',
    'owner_created': 'Owner created',
    'tenant_invited': 'Tenant invited',
    'tenant_invite_resent': 'Invite resent',
    'tenant_invite_revoked': 'Invite revoked',
    'pg_created': 'PG created',
    'room_created': 'Room added',
    'room_removed': 'Room removed',
    'room_beds_changed': 'Room beds changed',
    'rent_changed': 'Rent changed',
    'tenant_assigned': 'Tenant assigned',
    'payment_recorded': 'Payment recorded',
    'payment_submitted': 'Payment submitted',
    'payment_confirmed': 'Payment confirmed',
    'payment_rejected': 'Payment rejected',
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _future ??= state.loadAuditLogs();
    return Scaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = state.loadAuditLogs()),
        child: FutureBuilder<List<AuditLog>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final logs = snap.data ?? [];
            if (logs.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyState(icon: Icons.history, title: 'No activity yet'),
              ]);
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final log = logs[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(_labels[log.action] ?? log.action,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle:
                        Text('${log.actorRole} · ${formatWhen(log.createdAt)}'),
                    trailing: log.entityType == null
                        ? null
                        : StatusPill(log.entityType!),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

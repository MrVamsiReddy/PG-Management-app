import 'package:flutter/material.dart';

import 'app_state.dart';
import 'l10n.dart';
import 'community_screens.dart';
import 'finance_screens.dart';
import 'operations_screens.dart';
import 'property_screens.dart';
import 'theme.dart';
import 'widgets.dart';

export 'community_screens.dart';
export 'finance_screens.dart';
export 'operations_screens.dart';
export 'property_screens.dart';

class ModulesHubScreen extends StatelessWidget {
  const ModulesHubScreen({super.key, this.embedded = false});

  /// True when rendered as the shell's "Manage" tab (the shell provides the
  /// app bar). False when pushed as its own route — then it needs a Scaffold
  /// with an app bar so the user has a Back button.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final role = AppScope.of(context).role;
    final manager = role != UserRole.tenant;
    final l = AppLocalizations.of(context);
    final modules = <({
      String title,
      String subtitle,
      IconData icon,
      Widget page,
      Color color
    })>[
      if (manager)
        (
          title: l.t('pg.title'),
          subtitle: l.t('mod.pgSub'),
          icon: Icons.apartment_outlined,
          page: const PgListingsScreen(),
          color: primary
        ),
      if (manager)
        (
          title: l.t('room.title'),
          subtitle: l.t('mod.roomSub'),
          icon: Icons.bed_outlined,
          page: const RoomsScreen(),
          color: const Color(0xFF3478C7)
        ),
      if (manager)
        (
          title: l.t('ten.title'),
          subtitle: l.t('mod.tenSub'),
          icon: Icons.groups_outlined,
          page: const TenantsScreen(),
          color: const Color(0xFF7656B1)
        ),
      (
        title: l.t('mod.rent'),
        subtitle: manager ? l.t('mod.rentSubM') : l.t('mod.rentSubT'),
        icon: Icons.account_balance_wallet_outlined,
        page: const PaymentsScreen(),
        color: coral
      ),
      (
        title: l.t('mnt.title'),
        subtitle: l.t('mod.mntSub'),
        icon: Icons.build_outlined,
        page: const MaintenanceScreen(),
        color: warning
      ),
      (
        title: l.t('nav.visitors'),
        subtitle: l.t('mod.visSub'),
        icon: Icons.badge_outlined,
        page: const VisitorsScreen(),
        color: const Color(0xFF2B9A91)
      ),
      (
        title: l.t('ann.title'),
        subtitle: manager ? l.t('mod.annSubM') : l.t('mod.annSubT'),
        icon: Icons.campaign_outlined,
        page: const AnnouncementsScreen(),
        color: const Color(0xFFB65B87)
      ),
      (
        title: l.t('nav.notifications'),
        subtitle: l.t('mod.ntfSub'),
        icon: Icons.notifications_none,
        page: const NotificationsScreen(),
        color: const Color(0xFF536179)
      ),
    ];
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        if (embedded) ...[
          PageHeader(title: l.t('nav.manage'), subtitle: l.t('mod.sub')),
          const SizedBox(height: 22),
        ],
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth > 850
              ? 4
              : constraints.maxWidth > 540
                  ? 3
                  : 2;
          return GridView.builder(
            itemCount: modules.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .94),
            itemBuilder: (context, index) {
              final m = modules[index];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => m.page)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                  color: m.color.withValues(alpha: .12),
                                  borderRadius: BorderRadius.circular(13)),
                              child: Icon(m.icon, color: m.color)),
                          const Spacer(),
                          Text(m.title,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(m.subtitle,
                              style: const TextStyle(fontSize: 11)),
                        ]),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
    if (embedded) return list;
    // Pushed as a route: wrap so there is an app bar with a Back button.
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).t('nav.manage'))),
      body: list,
    );
  }
}

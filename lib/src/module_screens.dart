import 'package:flutter/material.dart';

import 'app_state.dart';
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
  const ModulesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = AppScope.of(context).role;
    final manager = role != UserRole.tenant;
    final modules = <({String title, String subtitle, IconData icon, Widget page, Color color})>[
      if (manager) (title: 'PG properties', subtitle: 'Listings & amenities', icon: Icons.apartment_outlined, page: const PgListingsScreen(), color: primary),
      if (manager) (title: 'Rooms & beds', subtitle: 'Floors & occupancy', icon: Icons.bed_outlined, page: const RoomsScreen(), color: const Color(0xFF3478C7)),
      if (manager) (title: 'Tenants', subtitle: 'KYC & agreements', icon: Icons.groups_outlined, page: const TenantsScreen(), color: const Color(0xFF7656B1)),
      (title: 'Rent & payments', subtitle: manager ? 'Collections & dues' : 'Pay rent & receipts', icon: Icons.account_balance_wallet_outlined, page: const PaymentsScreen(), color: coral),
      (title: 'Maintenance', subtitle: 'Requests & tracking', icon: Icons.build_outlined, page: const MaintenanceScreen(), color: warning),
      (title: 'Visitors', subtitle: 'Logs & approvals', icon: Icons.badge_outlined, page: const VisitorsScreen(), color: const Color(0xFF2B9A91)),
      (title: 'Announcements', subtitle: manager ? 'Broadcast updates' : 'Community updates', icon: Icons.campaign_outlined, page: const AnnouncementsScreen(), color: const Color(0xFFB65B87)),
      (title: 'Attendance', subtitle: 'Daily check-in/out', icon: Icons.how_to_reg_outlined, page: const AttendanceScreen(), color: const Color(0xFF3E7B50)),
      (title: 'Utility billing', subtitle: 'Meters & split bills', icon: Icons.electric_meter_outlined, page: const UtilitiesScreen(), color: const Color(0xFFCF7D28)),
      (title: 'Notifications', subtitle: 'All recent activity', icon: Icons.notifications_none, page: const NotificationsScreen(), color: const Color(0xFF536179)),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        const PageHeader(title: 'Manage', subtitle: 'Everything you need, in one place.'),
        const SizedBox(height: 22),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth > 850 ? 4 : constraints.maxWidth > 540 ? 3 : 2;
          return GridView.builder(
            itemCount: modules.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: .94),
            itemBuilder: (context, index) {
              final m = modules[index];
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => m.page)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: m.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: Icon(m.icon, color: m.color)),
                      const Spacer(),
                      Text(m.title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(m.subtitle, style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

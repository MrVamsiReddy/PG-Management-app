import 'package:flutter/material.dart';

import 'app_state.dart';
import 'module_screens.dart';
import 'theme.dart';
import 'widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return RefreshIndicator(
      onRefresh: () async => state.persistAll(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
        children: [
          Text(_greeting(), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 3),
          Text(state.role == UserRole.tenant ? 'Hello, ${state.displayName.split(' ').first} 👋' : 'Here’s the pulse of your PG', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 22),
          if (state.role == UserRole.tenant) _tenantHero(context, state) else _managerStats(context, state),
          const SizedBox(height: 25),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ModulesHubScreen())), child: const Text('View all')),
          ]),
          const SizedBox(height: 10),
          _quickActions(context, state.role),
          const SizedBox(height: 28),
          if (state.role != UserRole.tenant) ...[
            Text('Revenue overview', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(inr(384000), style: Theme.of(context).textTheme.headlineMedium),
                      const Text('Last 6 months · +12.4%', style: TextStyle(color: primary, fontWeight: FontWeight.w700, fontSize: 12)),
                    ]),
                    const StatusPill('On track'),
                  ]),
                  const SizedBox(height: 20),
                  const SizedBox(height: 150, width: double.infinity, child: RevenueChart()),
                ]),
              ),
            ),
            const SizedBox(height: 28),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Recent activity', style: Theme.of(context).textTheme.titleLarge),
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())), child: const Text('See all')),
          ]),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: state.notifications.take(3).map((n) => ListTile(
                leading: CircleAvatar(backgroundColor: primarySoft, child: Icon(notificationIcon(n['type'] as String), color: primary, size: 20)),
                title: Text(n['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(n['body'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(n['time'] as String, style: const TextStyle(fontSize: 10, color: Colors.black45)),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _managerStats(BuildContext context, AppState state) {
    final occupancy = state.totalBeds == 0 ? 0 : (state.occupiedBeds / state.totalBeds * 100).round();
    return LayoutBuilder(builder: (context, constraints) {
      final count = constraints.maxWidth > 680 ? 4 : 2;
      return GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: constraints.maxWidth > 680 ? 1.25 : .92,
        children: [
          StatCard(label: 'Occupancy', value: '$occupancy%', icon: Icons.bed_rounded, tint: primary, caption: '${state.occupiedBeds}/${state.totalBeds} beds'),
          StatCard(label: 'Collected', value: inr(state.collectedAmount), icon: Icons.savings_outlined, tint: const Color(0xFF3478C7), caption: 'This month'),
          StatCard(label: 'Outstanding', value: inr(state.dueAmount), icon: Icons.pending_actions, tint: coral, caption: '${state.payments.where((e) => e['status'] != 'Paid').length} dues'),
          StatCard(label: 'Open requests', value: '${state.maintenance.where((e) => e['status'] != 'Resolved').length}', icon: Icons.build_circle_outlined, tint: warning, caption: 'Needs attention'),
        ],
      );
    });
  }

  Widget _tenantHero(BuildContext context, AppState state) {
    final due = state.tenantDuePayment;
    final latest = due ??
        state.payments.firstWhere(
          (e) => e['tenant'] == AppState.currentTenantName,
          orElse: () => <String, dynamic>{'month': state.currentMonth, 'amount': 0, 'status': 'Paid', 'date': state.today},
        );
    final paid = due == null;
    return Card(
      color: ink,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${(latest['month'] as String).split(' ').first.toUpperCase()} RENT', style: const TextStyle(color: Colors.white54, letterSpacing: 1.2, fontWeight: FontWeight.w700, fontSize: 11)),
            StatusPill(latest['status'] as String),
          ]),
          const SizedBox(height: 14),
          Text(inr(latest['amount'] as int), style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.white)),
          const SizedBox(height: 4),
          Text('${paid ? 'Paid on' : 'Due by'} ${latest['date']} · Room ${AppState.currentTenantBed}', style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsScreen())),
            icon: Icon(paid ? Icons.receipt_long_outlined : Icons.lock_outline),
            label: Text(paid ? 'View receipt' : 'Pay now'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30)),
          ),
        ]),
      ),
    );
  }

  Widget _quickActions(BuildContext context, UserRole role) {
    final actions = role == UserRole.tenant
        ? [
            ('Pay rent', Icons.account_balance_wallet_outlined, const PaymentsScreen()),
            ('Raise issue', Icons.build_outlined, const MaintenanceScreen()),
            ('Add visitor', Icons.badge_outlined, const VisitorsScreen()),
            ('Check in', Icons.how_to_reg_outlined, const AttendanceScreen()),
          ]
        : [
            ('Add tenant', Icons.person_add_alt_1_outlined, const TenantsScreen()),
            ('Record rent', Icons.payments_outlined, const PaymentsScreen()),
            ('Add reading', Icons.electric_meter_outlined, const UtilitiesScreen()),
            ('Broadcast', Icons.campaign_outlined, const AnnouncementsScreen()),
          ];
    return Row(
      children: actions.map((a) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: a == actions.last ? 0 : 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => a.$3)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(a.$2, color: primary, size: 22)),
                const SizedBox(height: 8),
                Text(a.$1, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
              ]),
            ),
          ),
        ),
      )).toList(),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    return hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
  }

}

class RevenueChart extends StatelessWidget {
  const RevenueChart({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _RevenuePainter());
}

class _RevenuePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = const Color(0xFFE9ECEB)..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    const values = [.38, .55, .49, .72, .68, .9];
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      points.add(Offset(size.width * i / (values.length - 1), size.height * (1 - values[i])));
    }
    final fillPath = Path()..moveTo(0, size.height);
    for (final p in points) { fillPath.lineTo(p.dx, p.dy); }
    fillPath..lineTo(size.width, size.height)..close();
    canvas.drawPath(fillPath, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x4D1A7F72), Color(0x001A7F72)]).createShader(Offset.zero & size));
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final mid = (previous.dx + current.dx) / 2;
      path.cubicTo(mid, previous.dy, mid, current.dy, current.dx, current.dy);
    }
    canvas.drawPath(path, Paint()..color = primary..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    for (final p in points) {
      canvas.drawCircle(p, 4, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3, Paint()..color = primary);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

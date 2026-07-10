import 'package:flutter/material.dart';

import 'app_state.dart';
import 'l10n.dart';
import 'module_screens.dart';
import 'pg_wizard.dart';
import 'theme.dart';
import 'widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    if (state.role != UserRole.tenant && state.pgs.isEmpty) {
      return _ownerEmpty(context, state, l);
    }
    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
        children: [
          Text(_greeting(l), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 3),
          Text(
              state.role == UserRole.tenant
                  ? '${l.t('dash.hello')}, ${state.displayName.split(' ').first} 👋'
                  : l.t('dash.pulse'),
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 22),
          if (state.role == UserRole.tenant)
            _tenantHero(context, state, l)
          else
            _managerStats(context, state, l),
          const SizedBox(height: 25),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l.t('dash.quickActions'),
                style: Theme.of(context).textTheme.titleLarge),
            TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ModulesHubScreen())),
                child: Text(l.t('dash.viewAll'))),
          ]),
          const SizedBox(height: 10),
          _quickActions(context, state, state.role, l),
          const SizedBox(height: 28),
          if (state.role != UserRole.tenant) ...[
            Text(l.t('dash.revenue'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _revenueCard(context, state, l),
            const SizedBox(height: 28),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(l.t('dash.recent'),
                style: Theme.of(context).textTheme.titleLarge),
            TextButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen())),
                child: Text(l.t('dash.seeAll'))),
          ]),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final recent = state.visibleNotifications.take(3).toList();
            if (recent.isEmpty) {
              return Card(
                clipBehavior: Clip.antiAlias,
                child: EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: l.t('empty.nothingNew')),
              );
            }
            return Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: recent
                    .map((n) => ListTile(
                          onTap: () =>
                              _open(context, const NotificationsScreen()),
                          leading: CircleAvatar(
                              backgroundColor: primarySoft,
                              child: Icon(notificationIcon(n.type),
                                  color: primary, size: 20)),
                          title: Text(n.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(n.body,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(relativeTime(n.createdAt),
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.black45)),
                        ))
                    .toList(),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _revenueCard(
      BuildContext context, AppState state, AppLocalizations l) {
    final revenue = state.monthlyRevenue(source: state.pgPayments);
    final total = revenue.fold(0, (sum, e) => sum + e.total);
    final previous = revenue[revenue.length - 3].total;
    final last = revenue[revenue.length - 2].total;
    final growth = previous == 0 ? null : (last - previous) / previous * 100;
    final max = revenue.fold(0, (m, e) => e.total > m ? e.total : m);
    final values = revenue.map((e) => max == 0 ? 0.0 : e.total / max).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(inr(total),
                  style: Theme.of(context).textTheme.headlineMedium),
              Text(
                growth == null
                    ? l.t('dash.last6')
                    : '${l.t('dash.last6')} · ${growth >= 0 ? '+' : ''}${growth.toStringAsFixed(1)}%',
                style: const TextStyle(
                    color: primary, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ]),
            StatusPill(
                (growth ?? 0) >= 0 ? l.t('dash.onTrack') : l.t('dash.dipping')),
          ]),
          const SizedBox(height: 20),
          SizedBox(
              height: 150,
              width: double.infinity,
              child: RevenueChart(values: values)),
        ]),
      ),
    );
  }

  Widget _managerStats(
      BuildContext context, AppState state, AppLocalizations l) {
    final pg = state.activePg;
    final beds = pg?.beds ?? 0;
    final occupied = pg?.occupied ?? 0;
    final occupancy = beds == 0 ? 0 : (occupied / beds * 100).round();
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
          StatCard(
            label: l.t('dash.occupancy'),
            value: '$occupancy%',
            icon: Icons.bed_rounded,
            tint: primary,
            caption: '$occupied/$beds ${l.t('dash.beds')}',
            onTap: () => _open(context, const RoomsScreen()),
          ),
          StatCard(
            label: l.t('dash.collected'),
            value: inr(state.pgCollectedAmount),
            icon: Icons.savings_outlined,
            tint: const Color(0xFF3478C7),
            caption: l.t('dash.thisMonth'),
            onTap: () =>
                _open(context, const PaymentsScreen(initialFilter: 'Paid')),
          ),
          StatCard(
            label: l.t('dash.outstanding'),
            value: inr(state.pgDueAmount),
            icon: Icons.pending_actions,
            tint: coral,
            caption:
                '${state.pgPayments.where((e) => e.status != PaymentStatus.paid).length} ${l.t('dash.dues')}',
            onTap: () =>
                _open(context, const PaymentsScreen(initialFilter: 'Due')),
          ),
          StatCard(
            label: l.t('dash.openRequests'),
            value:
                '${state.pgMaintenance.where((e) => e.status != MaintenanceStatus.resolved).length}',
            icon: Icons.build_circle_outlined,
            tint: warning,
            caption: l.t('dash.needsAttention'),
            onTap: () =>
                _open(context, const MaintenanceScreen(initialFilter: 'Open')),
          ),
        ],
      );
    });
  }

  Widget _tenantHero(BuildContext context, AppState state, AppLocalizations l) {
    final due = state.tenantDuePayment;
    final latest = due ?? _latestTenantPayment(state);
    if (latest == null) {
      return Card(
          color: ink,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Text(l.t('dash.noRent'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white)),
          ));
    }
    final paid = latest.status == PaymentStatus.paid;
    return Card(
      color: ink,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context, const PaymentsScreen()),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                  '${formatMonthName(latest.period).toUpperCase()} ${l.t('dash.rent')}',
                  style: const TextStyle(
                      color: Colors.white54,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
              StatusPill(latest.displayStatus),
            ]),
            const SizedBox(height: 14),
            Text(inr(latest.amount),
                style: Theme.of(context)
                    .textTheme
                    .headlineLarge
                    ?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              paid
                  ? '${l.t('dash.paidOn')} ${formatDay(latest.paidDate!)} · ${l.t('dash.room')} ${state.currentTenantRoomLabel}'
                  : '${l.t('dash.dueBy')} ${formatDay(latest.dueDate)} · ${l.t('dash.room')} ${state.currentTenantRoomLabel}',
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => _open(context, const PaymentsScreen()),
              icon:
                  Icon(paid ? Icons.receipt_long_outlined : Icons.lock_outline),
              label: Text(paid ? l.t('dash.viewReceipt') : l.t('dash.payNow')),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30)),
            ),
          ]),
        ),
      ),
    );
  }

  Payment? _latestTenantPayment(AppState state) {
    final mine = state.tenantPayments;
    return mine.isEmpty ? null : mine.first;
  }

  Widget _quickActions(
      BuildContext context, AppState state, UserRole role, AppLocalizations l) {
    final actions = role == UserRole.tenant
        ? [
            (
              l.t('qa.payRent'),
              Icons.account_balance_wallet_outlined,
              const PaymentsScreen()
            ),
            (
              l.t('qa.raiseIssue'),
              Icons.build_outlined,
              const MaintenanceScreen()
            ),
            (
              l.t('qa.addVisitor'),
              Icons.badge_outlined,
              const VisitorsScreen()
            ),
            (
              l.t('qa.updates'),
              Icons.campaign_outlined,
              const AnnouncementsScreen()
            ),
          ]
        : [
            (
              l.t('qa.addTenant'),
              Icons.person_add_alt_1_outlined,
              const TenantsScreen()
            ),
            (
              l.t('qa.recordRent'),
              Icons.payments_outlined,
              const PaymentsScreen()
            ),
            (
              l.t('qa.maintenance'),
              Icons.build_outlined,
              const MaintenanceScreen()
            ),
            (
              l.t('qa.broadcast'),
              Icons.campaign_outlined,
              const AnnouncementsScreen()
            ),
          ];
    return Row(
      children: actions.map((a) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: a == actions.last ? 0 : 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => a.$3)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(children: [
                  Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                          color: primarySoft,
                          borderRadius: BorderRadius.circular(13)),
                      child: Icon(a.$2, color: primary, size: 22)),
                  const SizedBox(height: 9),
                  Text(a.$1,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 11)),
                ]),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _ownerEmpty(
          BuildContext context, AppState state, AppLocalizations l) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
        children: [
          const Icon(Icons.apartment_outlined, size: 56, color: Colors.black26),
          const SizedBox(height: 16),
          Text(
              '${l.t('dash.welcomeUser')}, ${state.displayName.split(' ').first}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(l.t('dash.emptyWorkspace'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => _open(context, const PgSetupWizard()),
            icon: const Icon(Icons.add),
            label: Text(l.t('dash.setupPg')),
          ),
        ],
      );

  String _greeting(AppLocalizations l) {
    final hour = DateTime.now().hour;
    return hour < 12
        ? l.t('dash.morning')
        : hour < 17
            ? l.t('dash.afternoon')
            : l.t('dash.evening');
  }

  static void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

class RevenueChart extends StatelessWidget {
  const RevenueChart({super.key, required this.values});

  /// Normalised 0..1 revenue points, oldest first.
  final List<double> values;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _RevenuePainter(values));
}

class _RevenuePainter extends CustomPainter {
  _RevenuePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE9ECEB)
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.length < 2) return;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      points.add(Offset(size.width * i / (values.length - 1),
          size.height * (1 - values[i] * .9)));
    }
    final fillPath = Path()..moveTo(0, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
        fillPath,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x4D1A7F72), Color(0x001A7F72)])
              .createShader(Offset.zero & size));
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final mid = (previous.dx + current.dx) / 2;
      path.cubicTo(mid, previous.dy, mid, current.dy, current.dx, current.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = primary
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);
    for (final p in points) {
      canvas.drawCircle(p, 4, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3, Paint()..color = primary);
    }
  }

  @override
  bool shouldRepaint(covariant _RevenuePainter oldDelegate) =>
      oldDelegate.values != values;
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pg_management/main.dart';
import 'package:pg_management/src/app_state.dart';
import 'package:pg_management/src/dashboard_screen.dart';
import 'package:pg_management/src/format.dart';
import 'package:pg_management/src/module_screens.dart';
import 'package:pg_management/src/theme.dart';

void main() {
  late Box<dynamic> box;
  late AppState state;
  var testRun = 0;

  // Each test gets its own box in a fresh temp directory. Nothing is torn
  // down between tests: awaiting real Hive IO inside a widget test's
  // fake-async zone deadlocks, and the OS reclaims the temp files anyway.
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp('pg_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('pg_test_${testRun++}');
    state = AppState(box);
    await state.init();
  });

  test('all supported roles have user-facing labels', () {
    expect(UserRole.values.map((role) => role.label).toList(), ['Owner', 'Tenant', 'Admin']);
  });

  test('app theme uses Material 3 and the brand primary colour', () {
    final theme = buildAppTheme();
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary.toARGB32(), primary.toARGB32());
  });

  test('init seeds every collection, stamps the schema version and persists', () {
    expect(state.pgs, isNotEmpty);
    expect(state.rooms, isNotEmpty);
    expect(state.tenants, isNotEmpty);
    expect(state.payments, isNotEmpty);
    expect(box.get('schemaVersion'), AppState.schemaVersion);
    expect(box.get('pgs'), isNotEmpty);
    expect(box.get('payments'), isNotEmpty);
  });

  test('init wipes and reseeds when the stored schema is outdated', () async {
    await box.put('schemaVersion', 1);
    await box.put('pgs', [{'legacy': true}]);

    final fresh = AppState(box);
    await fresh.init();

    expect(box.get('schemaVersion'), AppState.schemaVersion);
    expect(fresh.pgs, isNotEmpty);
    expect(fresh.pgs.first.name, isNot(''));
  });

  test('models survive a toMap/fromMap round trip', () {
    final payment = state.payments.first;
    expect(Payment.fromMap(payment.toMap()).toMap(), payment.toMap());
    final tenant = state.tenants.first;
    expect(Tenant.fromMap(tenant.toMap()).toMap(), tenant.toMap());
    final record = state.attendance.first;
    expect(AttendanceRecord.fromMap(record.toMap()).toMap(), record.toMap());
  });

  test('login persists the session role and logout clears it', () async {
    state.login(UserRole.tenant);
    expect(box.get('sessionRole'), 'tenant');
    final restored = AppState(box);
    await restored.init();
    expect(restored.isLoggedIn, isTrue);
    expect(restored.role, UserRole.tenant);

    await state.logout();
    expect(box.get('sessionRole'), isNull);
  });

  test('payments are linked to real tenants and rooms by id', () {
    for (final payment in state.payments) {
      expect(state.tenantById(payment.tenantId), isNotNull, reason: 'payment ${payment.id} has an orphan tenantId');
    }
    for (final tenant in state.tenants) {
      expect(state.roomById(tenant.roomId), isNotNull, reason: 'tenant ${tenant.id} has an orphan roomId');
    }
  });

  test('overdue is computed from the due date, not stored', () {
    final overdue = state.payments.firstWhere((p) => p.tenantId == 't3' && p.status == PaymentStatus.due);
    expect(overdue.isOverdue, isTrue);
    expect(overdue.displayStatus, 'Overdue');

    final upcoming = state.tenantDuePayment!;
    expect(upcoming.isOverdue, isFalse);
    expect(upcoming.displayStatus, 'Due');
  });

  test('payRent marks the payment paid, stores method and date, and notifies', () {
    final due = state.tenantDuePayment!;
    final collectedBefore = state.collectedAmount;

    state.payRent(due.id, 'UPI');

    final paid = state.payments.firstWhere((p) => p.id == due.id);
    expect(paid.status, PaymentStatus.paid);
    expect(paid.method, 'UPI');
    expect(paid.paidDate, isNotNull);
    expect(state.tenantDuePayment, isNull);
    expect(state.collectedAmount, collectedBefore + due.amount);
    expect(state.notifications.any((n) => n.title == 'Rent received' && n.type == NotificationType.payment), isTrue);
  });

  test('recordPayment inserts a paid entry for the current month', () {
    final collectedBefore = state.collectedAmount;

    state.recordPayment(tenantId: 't2', amount: 9500, method: 'Cash');

    final entry = state.payments.first;
    expect(entry.tenantId, 't2');
    expect(entry.status, PaymentStatus.paid);
    expect(entry.method, 'Cash');
    expect(state.collectedAmount, collectedBefore + 9500);
    expect(state.notifications.any((n) => n.title == 'Payment recorded'), isTrue);
  });

  test('monthlyRevenue aggregates paid rent per month for the chart', () {
    final revenue = state.monthlyRevenue();
    expect(revenue, hasLength(6));
    expect(revenue.last.total, state.collectedAmount);
    // History months carry seeded income.
    expect(revenue[4].total, greaterThan(0));
    expect(state.revenueGrowth, isNotNull);
  });

  test('onboarding a tenant fills a bed in the room and the property', () {
    final room = state.rooms.firstWhere((r) => r.occupied < r.beds);
    final occupiedBefore = room.occupied;
    final pgBefore = state.pgById(room.pgId)!.occupied;

    state.onboardTenant(name: 'Neha Verma', phone: '90000 00001', roomId: room.id, bed: 'B');

    expect(state.tenants.first.name, 'Neha Verma');
    expect(state.tenants.first.kyc, KycStatus.pending);
    expect(state.roomById(room.id)!.occupied, occupiedBefore + 1);
    expect(state.pgById(room.pgId)!.occupied, pgBefore + 1);
  });

  test('setVisitorStatus updates the visitor and raises a notification', () {
    final awaiting = state.visitors.firstWhere((e) => e.status == VisitorStatus.awaitingApproval);

    state.setVisitorStatus(awaiting.id, VisitorStatus.inside);
    expect(state.visitors.firstWhere((e) => e.id == awaiting.id).status, VisitorStatus.inside);
    expect(state.notifications.first.title, 'Visitor checked in');

    state.setVisitorStatus(awaiting.id, VisitorStatus.declined);
    expect(state.notifications.first.title, 'Visitor declined');
  });

  test('setMaintenanceStatus advances the request and assigns a technician', () {
    final open = state.maintenance.firstWhere((e) => e.status == MaintenanceStatus.open);

    state.setMaintenanceStatus(open.id, MaintenanceStatus.inProgress, assignee: 'Ravi Kumar');

    final updated = state.maintenance.firstWhere((e) => e.id == open.id);
    expect(updated.status, MaintenanceStatus.inProgress);
    expect(updated.assignee, 'Ravi Kumar');
    expect(state.notifications.first.type, NotificationType.maintenance);
  });

  test('publishAnnouncement adds the post and a notification', () {
    state.publishAnnouncement('Lift maintenance', 'Lift unavailable on Sunday morning.');

    expect(state.announcements.first.title, 'Lift maintenance');
    expect(state.notifications.first.type, NotificationType.announcement);
  });

  test('toggleCheckIn records a check-in and then a check-out for today', () {
    state.attendance.clear();
    expect(state.todayAttendance, isNull);

    state.toggleCheckIn();
    expect(state.isCheckedIn, isTrue);
    expect(state.todayAttendance!.checkOut, isNull);

    state.toggleCheckIn();
    expect(state.isCheckedIn, isFalse);
    expect(state.todayAttendance!.checkOut, isNotNull);
  });

  test('utility bill amounts derive from units and the stored rate', () {
    state.addUtilityBill(roomId: state.rooms.first.id, previous: 100, current: 150);
    final bill = state.utilities.first;
    expect(bill.units, 50);
    expect(bill.amount, 50 * AppState.utilityRate);
    expect(bill.status, BillStatus.generated);
  });

  test('notifications can be marked read individually and in bulk', () {
    final unread = state.notifications.firstWhere((n) => !n.read);
    state.markNotificationRead(unread.id);
    expect(state.notifications.firstWhere((n) => n.id == unread.id).read, isTrue);

    state.markAllNotificationsRead();
    expect(state.hasUnread, isFalse);
  });

  test('monthly dues generation is idempotent over seeded data', () {
    // Every seeded tenant already has a current-month payment.
    expect(state.generateMonthlyDues(), isFalse);
  });

  test('a missing monthly due is generated at the room rent', () {
    final now = DateTime.now();
    state.payments.removeWhere((p) => p.tenantId == 't1' && p.period.year == now.year && p.period.month == now.month);
    expect(state.generateMonthlyDues(), isTrue);

    final due = state.payments.firstWhere((p) => p.id == 'pay-${now.year}-${now.month}-t1');
    expect(due.amount, 9500); // room r1 rent
    expect(due.status, PaymentStatus.due);
    expect(state.generateMonthlyDues(), isFalse); // deterministic id → no duplicates
  });

  test('onboarding a tenant creates their first monthly due', () {
    state.onboardTenant(name: 'Kiran Kumar', phone: '90000 00002', roomId: 'r4', bed: 'B');
    final tenant = state.tenants.first;
    final due = state.payments.firstWhere((p) => p.tenantId == tenant.id);
    expect(due.amount, 10000); // room r4 rent
    expect(due.status, PaymentStatus.due);
  });

  test('demo sessions act as the default seeded tenant', () async {
    expect(state.currentTenantId, AppState.defaultTenantId);
    state.login(UserRole.tenant);
    expect(state.currentTenant?.name, 'Aarav Mehta');
    await state.logout();
    expect(state.currentTenantId, AppState.defaultTenantId);
  });

  test('inviteTenant reports a friendly error without a cloud connection', () async {
    final result = await state.inviteTenant(tenantId: 't1', email: 'someone@example.com');
    expect(result.error, isNotNull);
    expect(result.error, contains('cloud account'));
    expect(result.tempPassword, isNull);
  });

  test('the active property scopes rooms, tenants and money', () {
    expect(state.activePg?.id, 'p1');
    expect(state.pgRooms, hasLength(5));
    expect(state.pgTenants, hasLength(4));
    expect(state.pgCollectedAmount, state.collectedAmount);

    state.selectPg('p2'); // seeded second property has no rooms yet
    expect(state.activePg?.id, 'p2');
    expect(state.pgRooms, isEmpty);
    expect(state.pgTenants, isEmpty);
    expect(state.pgPayments, isEmpty);
    expect(state.pgCollectedAmount, 0);

    state.selectPg('p1');
    expect(state.pgRooms, hasLength(5));
  });

  test('fresh sessions never start on the set-password gate', () {
    expect(state.mustChangePassword, isFalse);
    state.login(UserRole.owner);
    expect(state.mustChangePassword, isFalse);
  });

  test('a tenant cannot see other tenants notifications or manager activity', () {
    state.login(UserRole.tenant); // demo tenant is t1
    final visible = state.visibleNotifications;

    // Never a manager-scoped notification, and never one addressed to another tenant.
    expect(visible.every((n) => n.roleScope != NotificationScope.managers), isTrue);
    expect(visible.every((n) => n.roleScope != NotificationScope.tenant || n.tenantId == 't1'), isTrue);

    // The seeded "Rent received from Ishita Rao" (manager, t4) is hidden.
    expect(visible.any((n) => n.body.contains('Ishita Rao')), isFalse);
    // The workspace announcement and the tenant's own reminder are visible.
    expect(visible.any((n) => n.roleScope == NotificationScope.everyone), isTrue);
    expect(visible.any((n) => n.tenantId == 't1'), isTrue);
  });

  test('an owner sees managerial and workspace notifications for the active PG', () {
    state.login(UserRole.owner);
    final visible = state.visibleNotifications;

    expect(visible.any((n) => n.body.contains('Ishita Rao')), isTrue); // manager notification
    expect(visible.any((n) => n.roleScope == NotificationScope.everyone), isTrue); // announcement
    // A tenant's private reminder is never in a manager's list.
    expect(visible.any((n) => n.roleScope == NotificationScope.tenant), isFalse);
  });

  test('a tenant only ever sees their own payments', () {
    state.login(UserRole.tenant);
    expect(state.tenantPayments, isNotEmpty);
    expect(state.tenantPayments.every((p) => p.tenantId == 't1'), isTrue);
    // Other tenants' payments exist in the workspace but are not exposed.
    expect(state.payments.any((p) => p.tenantId != 't1'), isTrue);
    expect(state.tenantPayments.any((p) => p.tenantId != 't1'), isFalse);
  });

  test('paying rent notifies managers and the payer separately', () {
    state.login(UserRole.tenant);
    final due = state.tenantDuePayment!;
    state.payRent(due.id, 'UPI');

    final managerNote = state.notifications.firstWhere((n) => n.title == 'Rent received');
    expect(managerNote.roleScope, NotificationScope.managers);
    expect(managerNote.tenantId, 't1');
    expect(managerNote.pgId, 'p1');

    final tenantNote = state.notifications.firstWhere((n) => n.title == 'Payment successful');
    expect(tenantNote.roleScope, NotificationScope.tenant);
    expect(tenantNote.tenantId, 't1');

    // The tenant does not see the manager-facing "Rent received" note.
    expect(state.visibleNotifications.any((n) => n.title == 'Rent received'), isFalse);
    expect(state.visibleNotifications.any((n) => n.title == 'Payment successful'), isTrue);
  });

  test('maintenance updates reach only tenants in that room', () {
    state.login(UserRole.owner);
    final open = state.maintenance.firstWhere((m) => m.roomId == 'r2'); // Rohan (t3) lives in r2
    state.setMaintenanceStatus(open.id, MaintenanceStatus.inProgress, assignee: 'Ravi');

    final note = state.notifications.firstWhere((n) => n.title == 'Maintenance updated');
    expect(note.roleScope, NotificationScope.tenant);
    expect(note.tenantId, 't3'); // the room's occupant, not t1

    // t1 (a different room) must not see it.
    state.login(UserRole.tenant);
    expect(state.visibleNotifications.any((n) => n.title == 'Maintenance updated'), isFalse);
  });

  testWidgets('tenant notification centre hides other tenants activity', (tester) async {
    state.login(UserRole.tenant);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(theme: buildAppTheme(), home: const NotificationsScreen()),
    ));
    await tester.pump();
    expect(find.textContaining('Ishita Rao'), findsNothing); // another tenant's rent
    expect(find.textContaining('Maya Singh'), findsNothing); // another tenant's visitor
    expect(find.text('Rent reminder'), findsOneWidget); // the tenant's own
  });

  test('payments export as spreadsheet-ready CSV', () {
    final csv = state.paymentsCsv();
    final lines = csv.split('\n');
    expect(lines.first, 'Receipt,Tenant,Month,Amount,Status,Due date,Paid date,Method');
    expect(lines.length, state.payments.length + 1);
    expect(csv, contains('"Aarav Mehta"'));
    expect(csv, contains('"9500"'));
    // Values with quotes/commas stay one cell.
    expect(state.paymentsCsv(), isNot(contains('""Aarav')));
  });

  test('formatting helpers render Indian currency and relative time', () {
    expect(inr(9500), '₹9,500');
    expect(inr(384000), '₹3,84,000');
    expect(relativeTime(DateTime.now()), 'Just now');
    expect(relativeTime(DateTime.now().subtract(const Duration(minutes: 12))), '12 min ago');
    expect(relativeTime(DateTime.now().subtract(const Duration(hours: 3))), '3 hrs ago');
  });

  testWidgets('owner navigation shows the management tabs', (tester) async {
    state.login(UserRole.owner);
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('My Rent'), findsNothing);
    expect(find.text('My Requests'), findsNothing);
  });

  testWidgets('tenant navigation shows only tenant tabs', (tester) async {
    state.login(UserRole.tenant);
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('My Rent'), findsOneWidget);
    expect(find.text('My Requests'), findsOneWidget);
    expect(find.text('Visitors'), findsOneWidget);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Properties'), findsNothing);
  });

  testWidgets('admin navigation is property-centric', (tester) async {
    state.login(UserRole.admin);
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Properties'), findsOneWidget);
    expect(find.text('Operations'), findsOneWidget);
    expect(find.text('Manage'), findsNothing);
  });

  testWidgets('tenants are blocked from owner-only screens', (tester) async {
    state.login(UserRole.tenant);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(theme: buildAppTheme(), home: const TenantsScreen()),
    ));
    await tester.pump();
    expect(find.text('This area is for PG managers'), findsOneWidget);
    expect(find.text('Onboard'), findsNothing);
  });

  // Renders the dashboard alone under a real Navigator so tile taps can
  // push their destination screens.
  Widget dashboardHarness() => AppScope(
        notifier: state,
        child: MaterialApp(theme: buildAppTheme(), home: const Scaffold(body: DashboardScreen())),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  // Stat/label text sits inside a FittedBox transform, so tap the enclosing
  // full-tile InkWell rather than the scaled text.
  Finder tileFor(Finder label) => find.ancestor(of: label, matching: find.byType(InkWell)).first;

  testWidgets('owner stat tiles navigate to their scoped screens', (tester) async {
    state.login(UserRole.owner);
    await tester.pumpWidget(dashboardHarness());
    await settle(tester);

    await tester.tap(tileFor(find.text('Occupancy')));
    await settle(tester);
    expect(find.text('Bed occupancy'), findsOneWidget); // Rooms & Beds
    await tester.pageBack();
    await settle(tester);

    await tester.tap(tileFor(find.text('Collected')));
    await settle(tester);
    expect(find.text('Rent collection'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Paid')).selected, isTrue);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(tileFor(find.text('Outstanding')));
    await settle(tester);
    expect(find.text('Rent collection'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Due')).selected, isTrue);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(tileFor(find.text('Open requests')));
    await settle(tester);
    expect(find.text('Service desk'), findsOneWidget); // Maintenance
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Open')).selected, isTrue);
  });

  testWidgets('tenant rent card and quick cards navigate to tenant screens', (tester) async {
    state.login(UserRole.tenant);
    await tester.pumpWidget(dashboardHarness());
    await settle(tester);

    // The rent hero card is tappable via its enclosing InkWell.
    await tester.tap(tileFor(find.textContaining('RENT')));
    await settle(tester);
    expect(find.text('My rent'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(tileFor(find.text('My bill')));
    await settle(tester);
    expect(find.text('Utility billing'), findsOneWidget);
  });

  testWidgets('signing in from the auth screen opens the home shell', (tester) async {
    await tester.pumpWidget(PgManagementApp(state: state));
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    // Bounded pumps instead of pumpAndSettle: pending Hive writes never
    // settle inside the fake-async zone.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.isLoggedIn, isTrue);
    // Owners see the property switcher as the title.
    expect(find.text('HSR Layout PG'), findsWidgets);
    expect(find.text('Quick actions'), findsOneWidget);
  });
}

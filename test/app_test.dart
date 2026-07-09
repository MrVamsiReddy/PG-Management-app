import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pg_management/main.dart';
import 'package:pg_management/src/access.dart';
import 'package:pg_management/src/app_state.dart';
import 'package:pg_management/src/dashboard_screen.dart';
import 'package:pg_management/src/format.dart';
import 'package:pg_management/src/home_shell.dart';
import 'package:pg_management/src/l10n.dart';
import 'package:pg_management/src/module_screens.dart';
import 'package:pg_management/src/owner_app.dart';
import 'package:pg_management/src/saas_models.dart';
import 'package:pg_management/src/tenant_app.dart';
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
    AppState.debugSeedDemoData = true;
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

  test('there is no local session restore across restarts', () async {
    state.login(UserRole.tenant);
    expect(state.isLoggedIn, isTrue);

    final restored = AppState(box);
    await restored.init();
    expect(restored.isLoggedIn, isFalse);
  });

  test('evaluateProfileAccess resolves role, customer and status', () {
    final owner = evaluateProfileAccess(
      profile: {'role': 'owner', 'customer_id': 'c1', 'platform_admin': false},
      customer: {'status': 'enabled'},
    );
    expect(owner.role, UserRole.owner);
    expect(owner.customerId, 'c1');
    expect(owner.error, isNull);

    final tenant = evaluateProfileAccess(
      profile: {'role': 'tenant', 'customer_id': 'c1', 'platform_admin': false},
      customer: {'status': 'enabled'},
    );
    expect(tenant.role, UserRole.tenant);

    final admin = evaluateProfileAccess(
      profile: {'role': 'admin', 'customer_id': null, 'platform_admin': true},
      customer: null,
    );
    expect(admin.role, UserRole.admin);
    expect(admin.error, isNull);

    final unlinked = evaluateProfileAccess(
      profile: {'role': 'owner', 'customer_id': null, 'platform_admin': false},
      customer: null,
    );
    expect(unlinked.role, isNull);
    expect(unlinked.error, isNotNull);

    final legacy = evaluateProfileAccess(profile: null, customer: null);
    expect(legacy.role, isNull);
    expect(legacy.error, isNull);
  });

  test('a disabled customer blocks its owner and tenant', () {
    final disabledOwner = evaluateProfileAccess(
      profile: {'role': 'owner', 'customer_id': 'c1', 'platform_admin': false},
      customer: {'status': 'disabled'},
    );
    expect(disabledOwner.role, isNull);
    expect(disabledOwner.error, contains('disabled'));

    final disabledTenant = evaluateProfileAccess(
      profile: {'role': 'tenant', 'customer_id': 'c1', 'platform_admin': false},
      customer: {'status': 'disabled'},
    );
    expect(disabledTenant.role, isNull);
    expect(disabledTenant.error, contains('disabled'));
  });

  test('each portal accepts only its own role', () {
    expect(portalError(UserRole.owner, LoginPortal.owner), isNull);
    expect(portalError(UserRole.tenant, LoginPortal.tenant), isNull);
    expect(portalError(UserRole.admin, LoginPortal.admin), isNull);
    expect(portalError(UserRole.owner, LoginPortal.tenant), isNotNull);
    expect(portalError(UserRole.tenant, LoginPortal.owner), isNotNull);
    expect(portalError(UserRole.admin, LoginPortal.owner), isNotNull);
    expect(portalError(UserRole.tenant, LoginPortal.admin), isNotNull);
  });

  test('offline sign-in never creates a local session', () async {
    final error = await state.signInCloud(email: 'a@b.c', password: 'password', portal: LoginPortal.owner);
    expect(error, isNotNull);
    expect(state.isLoggedIn, isFalse);
    expect(state.cloudMode, isFalse);
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

  test('recordPayment settles a matching current-month due in place', () {
    final collectedBefore = state.collectedAmount;
    final before = state.payments.length;
    final due = state.payments.firstWhere((p) => p.tenantId == 't2' && p.status == PaymentStatus.due);

    state.recordPayment(tenantId: 't2', amount: due.amount, method: 'Cash');

    // No duplicate row — the existing due was updated.
    expect(state.payments.length, before);
    final settled = state.payments.firstWhere((p) => p.id == due.id);
    expect(settled.status, PaymentStatus.paid);
    expect(settled.method, 'Cash');
    expect(settled.balance, 0);
    expect(state.collectedAmount, collectedBefore + due.amount);
    expect(state.notifications.any((n) => n.title == 'Payment recorded'), isTrue);
  });

  test('recordPayment below the due amount marks it partial', () {
    final due = state.payments.firstWhere((p) => p.tenantId == 't2' && p.status == PaymentStatus.due);
    final before = state.payments.length;

    state.recordPayment(tenantId: 't2', amount: 2000, method: 'Cash');

    expect(state.payments.length, before); // still no new row
    final partial = state.payments.firstWhere((p) => p.id == due.id);
    expect(partial.status, PaymentStatus.partial);
    expect(partial.collected, 2000);
    expect(partial.balance, due.amount - 2000);
    expect(partial.displayStatus, 'Partial');
    expect(state.notifications.any((n) => n.title == 'Part payment recorded'), isTrue);

    // A follow-up payment covering the rest settles it.
    state.recordPayment(tenantId: 't2', amount: due.amount - 2000, method: 'UPI');
    final done = state.payments.firstWhere((p) => p.id == due.id);
    expect(done.status, PaymentStatus.paid);
    expect(done.balance, 0);
    expect(state.payments.length, before);
  });

  test('recordPayment with no matching due creates a standalone advance row', () {
    // t2's current-month due settled first, so the next payment has no match.
    final due = state.payments.firstWhere((p) => p.tenantId == 't2' && p.status == PaymentStatus.due);
    state.recordPayment(tenantId: 't2', amount: due.amount, method: 'Cash');
    final after = state.payments.length;

    state.recordPayment(tenantId: 't2', amount: 5000, method: 'UPI');

    expect(state.payments.length, after + 1); // advance row added
    final advance = state.payments.first;
    expect(advance.tenantId, 't2');
    expect(advance.status, PaymentStatus.paid);
    expect(advance.amount, 5000);
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

    final error = state.onboardTenant(name: 'Neha Verma', phone: '90000 00001', roomId: room.id, bed: state.suggestBed(room.id));

    expect(error, isNull);
    expect(state.tenants.first.name, 'Neha Verma');
    expect(state.tenants.first.kyc, KycStatus.pending);
    expect(state.roomById(room.id)!.occupied, occupiedBefore + 1);
    expect(state.pgById(room.pgId)!.occupied, pgBefore + 1);
  });

  test('onboarding into a full room is blocked and changes nothing', () {
    final full = state.rooms.firstWhere((r) => r.occupied >= r.beds); // r1 (2/2)
    final tenantsBefore = state.tenants.length;
    final occupiedBefore = full.occupied;
    final pgBefore = state.pgById(full.pgId)!.occupied;

    final error = state.onboardTenant(name: 'Full Roomer', phone: '90000 12345', roomId: full.id, bed: 'C');

    expect(error, isNotNull);
    expect(error, contains('full'));
    expect(state.tenants.length, tenantsBefore);
    expect(state.roomById(full.id)!.occupied, occupiedBefore);
    expect(state.pgById(full.pgId)!.occupied, pgBefore);
  });

  test('onboarding onto a taken bed label in the same room is blocked', () {
    // r2 has Rohan (t3) on bed A and a free bed.
    final error = state.onboardTenant(name: 'Bed Clash', phone: '90000 22222', roomId: 'r2', bed: 'a');
    expect(error, isNotNull);
    expect(error, contains('taken'));
    expect(state.tenants.any((t) => t.name == 'Bed Clash'), isFalse);

    // A different free bed in the same room succeeds.
    final ok = state.onboardTenant(name: 'Bed Ok', phone: '90000 22223', roomId: 'r2', bed: state.suggestBed('r2'));
    expect(ok, isNull);
    expect(state.tenants.first.name, 'Bed Ok');
  });

  test('onboarding validates name and phone before touching data', () {
    final before = state.tenants.length;
    expect(state.onboardTenant(name: '   ', phone: '90000 00001', roomId: 'r4', bed: 'B'), contains('name'));
    expect(state.onboardTenant(name: 'Shorty', phone: '12345', roomId: 'r4', bed: 'B'), contains('phone'));
    expect(state.tenants.length, before); // nothing added on invalid input
  });

  test('suggestBed returns the first free bed and empty when the room is full', () {
    expect(state.suggestBed('r2'), 'B'); // A taken by Rohan
    expect(state.suggestBed('r1'), ''); // full
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

  test('generateMonthlyDues never duplicates when a partial or paid row exists', () {
    final now = DateTime.now();
    // Turn t1's current due into a partial payment, then regenerate.
    final i = state.payments.indexWhere((p) => p.tenantId == 't1' && p.period.year == now.year && p.period.month == now.month);
    state.payments[i] = state.payments[i].copyWith(status: PaymentStatus.partial, paidAmount: 1000);

    expect(state.generateMonthlyDues(), isFalse);
    final t1ThisMonth = state.payments.where((p) => p.tenantId == 't1' && p.period.year == now.year && p.period.month == now.month);
    expect(t1ThisMonth, hasLength(1)); // still exactly one row
  });

  test('startup materialises a tenant\'s own due without generating owner-wide rows', () {
    final now = DateTime.now();
    // Wipe every current-month due so there is something to generate.
    state.payments.removeWhere((p) => p.period.year == now.year && p.period.month == now.month);

    state.login(UserRole.tenant); // demo tenant t1

    // t1's due exists in memory for display…
    expect(state.tenantPayments.any((p) => p.status == PaymentStatus.due), isTrue);
    // …but the tenant session did not generate other tenants' dues.
    final others = state.payments.where((p) =>
        p.tenantId != 't1' && p.period.year == now.year && p.period.month == now.month);
    expect(others, isEmpty);
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
    expect(lines.first, 'Receipt,Tenant,Month,Amount,Collected,Balance,Status,Due date,Paid date,Method');
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

  testWidgets('utility billing and attendance are gone from the module grid', (tester) async {
    state.login(UserRole.owner);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(theme: buildAppTheme(), home: const ModulesHubScreen()),
    ));
    await tester.pump();
    expect(find.text('Utility billing'), findsNothing);
    expect(find.text('Attendance'), findsNothing);
    // Surviving modules still render.
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Announcements'), findsOneWidget);
  });

  test('every record a session creates is stamped with its customer id', () {
    state.login(UserRole.owner); // local demo session => customer 'demo'
    expect(state.customerId, 'demo');

    final room = state.rooms.firstWhere((r) => r.occupied < r.beds);
    state.onboardTenant(name: 'Stamp Test', phone: '90000 12399', roomId: room.id, bed: state.suggestBed(room.id));
    final tenant = state.tenants.first;
    expect(tenant.customerId, 'demo');
    // The tenant's generated monthly due carries the scope too.
    expect(state.payments.firstWhere((p) => p.tenantId == tenant.id).customerId, 'demo');

    state.publishAnnouncement('Scoped', 'Body');
    expect(state.announcements.first.customerId, 'demo');
    expect(state.notifications.first.customerId, 'demo');

    state.addVisitor(name: 'Scoped Visitor', tenantId: tenant.id, purpose: 'Family');
    expect(state.visitors.first.customerId, 'demo');

    state.addMaintenanceRequest(title: 'Scoped issue', roomId: room.id, category: 'Other', priority: Priority.low);
    expect(state.maintenance.first.customerId, 'demo');

    state.addRoom(const Room(id: 'r-scope', pgId: 'p1', number: '999', floor: 9, beds: 2, occupied: 0, rent: 5000));
    expect(state.rooms.last.customerId, 'demo');

    state.savePg(const Pg(id: 'p-scope', name: 'Scoped PG', address: 'X', beds: 10, occupied: 0, amenities: '', rating: 4.0));
    expect(state.pgs.first.customerId, 'demo');
  });

  test('SaaS models survive a toMap/fromMap round trip', () {
    final now = DateTime.now();
    final customer = Customer(id: 'c1', businessName: 'Acme PG', ownerName: 'A', ownerEmail: 'a@b.c', phone: '9', status: CustomerStatus.disabled, plan: 'pro', createdAt: now, disabledAt: now);
    expect(Customer.fromMap(customer.toMap()).toMap(), customer.toMap());
    expect(customer.enabled, isFalse);

    final invite = TenantInvite(id: 'i1', customerId: 'c1', tenantId: 't1', email: 'x@y.z', token: 'tok', status: InviteStatus.pending, expiresAt: now.add(const Duration(days: 7)));
    expect(TenantInvite.fromMap(invite.toMap()).toMap(), invite.toMap());
    expect(invite.usable, isTrue);
    expect(TenantInvite.fromMap({...invite.toMap(), 'status': 'revoked'}).usable, isFalse);

    final submission = PaymentSubmission(id: 's1', customerId: 'c1', pgId: 'p1', tenantId: 't1', dueId: 'd1', amount: 9500, utr: 'UTR123', submittedAt: now);
    expect(PaymentSubmission.fromMap(submission.toMap()).toMap(), submission.toMap());
    expect(submission.status, SubmissionStatus.pendingConfirmation);

    const bed = Bed(id: 'b1', customerId: 'c1', pgId: 'p1', roomId: 'r1', label: 'A');
    expect(Bed.fromMap(bed.toMap()).toMap(), bed.toMap());

    final rule = RentRule(id: 'rr1', customerId: 'c1', pgId: 'p1', sharingType: 2, amount: 9500, effectiveFrom: now);
    expect(RentRule.fromMap(rule.toMap()).toMap(), rule.toMap());

    final log = AuditLog(id: 'l1', customerId: null, actorUserId: 'u1', actorRole: 'admin', action: 'customer_created', entityType: 'customer', entityId: 'c1', afterJson: const {'status': 'enabled'}, createdAt: now);
    expect(AuditLog.fromMap(log.toMap()).toMap(), log.toMap());
  });

  test('the SaaS migration scopes and locks down every business table', () {
    final sql = File('supabase/004_saas_core.sql').readAsStringSync();
    const tables = [
      'customers', 'profiles', 'pgs', 'floors', 'rooms', 'beds', 'tenants',
      'tenant_invites', 'rent_rules', 'pg_payment_settings', 'payment_dues',
      'payments', 'payment_submissions', 'payment_proof_files', 'complaints',
      'notices', 'visitors', 'audit_logs',
    ];
    for (final table in tables) {
      expect(sql, contains('create table if not exists public.$table'), reason: '$table must exist');
      expect(sql, contains('alter table public.$table enable row level security'), reason: '$table must enable RLS');
    }
    // Every business table carries the customer scope (customers is the scope).
    for (final table in tables.where((t) => t != 'customers' && t != 'profiles' && t != 'audit_logs')) {
      expect(sql, contains(RegExp('create table if not exists public\\.$table[^;]*customer_id\\s+uuid not null', dotAll: true)), reason: '$table must require customer_id');
    }
    // Disabled customers are excluded at the helper level, tenants never
    // write dues, and the proofs bucket exists with scoped policies.
    expect(sql, contains("c.status = 'enabled'"));
    expect(sql.contains('payment_dues_tenant_read'), isTrue);
    expect(sql.contains('payment_dues_tenant_insert'), isFalse, reason: 'tenants must never write dues');
    expect(sql, contains("'payment-proofs'"));
    expect(sql, contains('pp_tenant_insert'));
    expect(sql, contains('unique (tenant_id, period)'));
  });

  test('language preference persists across restarts', () async {
    expect(state.language, AppLanguage.english);
    state.setLanguage(AppLanguage.telugu);
    expect(box.get('language'), 'te');

    final restored = AppState(box);
    await restored.init();
    expect(restored.language, AppLanguage.telugu);
    expect(restored.locale.languageCode, 'te');
  });

  test('push preference gates and persists', () async {
    expect(state.pushEnabled, isTrue);
    state.setPushEnabled(false);
    expect(box.get('pushEnabled'), isFalse);

    final restored = AppState(box);
    await restored.init();
    expect(restored.pushEnabled, isFalse);
  });

  test('announcement audience filtering respects property and tenant', () {
    // A property-specific announcement for p1, and a workspace-wide one.
    state.publishAnnouncement('HSR only', 'For HSR tenants', pgId: 'p1');
    state.publishAnnouncement('Everyone', 'For all tenants');

    // Owner on p1 sees both; switching to p2 hides the p1-only one.
    state.login(UserRole.owner);
    state.selectPg('p1');
    expect(state.visibleAnnouncements.any((a) => a.title == 'HSR only'), isTrue);
    expect(state.visibleAnnouncements.any((a) => a.title == 'Everyone'), isTrue);
    state.selectPg('p2');
    expect(state.visibleAnnouncements.any((a) => a.title == 'HSR only'), isFalse);
    expect(state.visibleAnnouncements.any((a) => a.title == 'Everyone'), isTrue);

    // Tenant t1 lives in p1, so sees both.
    state.login(UserRole.tenant);
    expect(state.visibleAnnouncements.any((a) => a.title == 'HSR only'), isTrue);
    expect(state.visibleAnnouncements.any((a) => a.title == 'Everyone'), isTrue);
  });

  test('updatePersonalDetails edits a tenant record', () async {
    state.login(UserRole.tenant);
    final error = await state.updatePersonalDetails(name: 'Aarav M', phone: '90000 99999');
    expect(error, isNull);
    expect(state.currentTenant?.name, 'Aarav M');
    expect(state.currentTenant?.phone, '90000 99999');
    expect(state.displayName, 'Aarav M');
  });

  testWidgets('navigation labels localize to the selected language', (tester) async {
    state.login(UserRole.owner);
    state.setLanguage(AppLanguage.hindi);
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('प्रबंधन'), findsOneWidget); // Manage
    expect(find.text('किराया'), findsOneWidget); // Rent
    expect(find.text('Manage'), findsNothing);
  });

  testWidgets('profile personal-details row opens an editable sheet', (tester) async {
    state.login(UserRole.tenant);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: state.locale,
        localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ProfileScreen()),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Personal details'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });

  testWidgets('rental agreement is gone from the tenant details and profile', (tester) async {
    state.login(UserRole.owner);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(theme: buildAppTheme(), home: const TenantsScreen()),
    ));
    await tester.pump();
    await tester.tap(find.text('Aarav Mehta')); // expand the first tenant
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Agreement'), findsNothing);
    expect(find.textContaining('e-sign'), findsNothing);
    expect(find.text('Call tenant'), findsOneWidget);
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

    await tester.tap(tileFor(find.text('Raise issue')));
    await settle(tester);
    expect(find.text('My requests'), findsOneWidget); // Maintenance (tenant)
  });

  testWidgets('auth screen shows role portals and no demo or sign-up', (tester) async {
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump();

    expect(find.text('Owner login'), findsOneWidget);
    expect(find.text('Tenant login'), findsOneWidget);
    expect(find.text('Admin login'), findsOneWidget);
    expect(find.textContaining('demo', findRichText: true), findsNothing);
    expect(find.text('Create account'), findsNothing);

    await tester.tap(find.text('Owner login'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('tenant app shows only tenant surfaces and no owner routes', (tester) async {
    state.login(UserRole.tenant);
    await tester.pumpWidget(TenantApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('My Rent'), findsOneWidget);
    expect(find.text('My Requests'), findsOneWidget);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Properties'), findsNothing);
    expect(find.text('Onboard'), findsNothing);
  });

  testWidgets('tenant app blocks a non-tenant account', (tester) async {
    state.login(UserRole.owner);
    await tester.pumpWidget(TenantApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('My Rent'), findsNothing);
  });

  testWidgets('owner/admin app auth offers no tenant portal or sign-up', (tester) async {
    await tester.pumpWidget(OwnerAdminApp(state: state));
    await tester.pump();
    expect(find.text('Owner login'), findsOneWidget);
    expect(find.text('Admin login'), findsOneWidget);
    expect(find.text('Tenant login'), findsNothing);
    expect(find.text('Create account'), findsNothing);
  });
}

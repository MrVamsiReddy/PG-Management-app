import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pg_management/main.dart';
import 'package:pg_management/src/access.dart';
import 'package:pg_management/src/app_state.dart';
import 'package:pg_management/src/auth_screen.dart';
import 'package:pg_management/src/dashboard_screen.dart';
import 'package:pg_management/src/format.dart';
import 'package:pg_management/src/home_shell.dart';
import 'package:pg_management/src/invite_message.dart';
import 'package:pg_management/src/l10n.dart';
import 'package:pg_management/src/module_screens.dart';
import 'package:pg_management/src/owner_app.dart';
import 'package:pg_management/src/pg_wizard.dart';
import 'package:pg_management/src/supabase_config.dart';
import 'package:pg_management/src/tenant_app.dart';
import 'package:pg_management/src/theme.dart';

// Cloud-only build: there is no local store, seed path or demo login in the
// product. Tests inject an in-memory fixture directly into the public
// collections and use the @visibleForTesting debugSignIn seam to set a role.
void seedFixture(AppState s) {
  final now = DateTime.now();
  DateTime month(int offset) => DateTime(now.year, now.month + offset);

  s.pgs = [
    const Pg(
        id: 'p1',
        name: 'HSR Layout PG',
        address: '27th Main, HSR Layout, Bengaluru',
        beds: 48,
        occupied: 41,
        amenities: 'Wi-Fi • Food • Laundry • CCTV',
        rating: 4.8),
    const Pg(
        id: 'p2',
        name: 'Koramangala PG',
        address: '5th Block, Koramangala, Bengaluru',
        beds: 36,
        occupied: 29,
        amenities: 'Wi-Fi • AC • Gym • Power backup',
        rating: 4.6),
  ];
  s.rooms = [
    const Room(
        id: 'r1',
        pgId: 'p1',
        number: '101',
        floor: 1,
        beds: 2,
        occupied: 2,
        rent: 9500),
    const Room(
        id: 'r2',
        pgId: 'p1',
        number: '102',
        floor: 1,
        beds: 3,
        occupied: 2,
        rent: 8200),
    const Room(
        id: 'r3',
        pgId: 'p1',
        number: '201',
        floor: 2,
        beds: 1,
        occupied: 1,
        rent: 14500),
    const Room(
        id: 'r4',
        pgId: 'p1',
        number: '202',
        floor: 2,
        beds: 2,
        occupied: 1,
        rent: 10000),
    const Room(
        id: 'r5',
        pgId: 'p1',
        number: '301',
        floor: 3,
        beds: 3,
        occupied: 3,
        rent: 7800),
  ];
  s.tenants = [
    Tenant(
        id: 't1',
        name: 'Aarav Mehta',
        phone: '98765 43210',
        roomId: 'r1',
        bed: 'A',
        kyc: KycStatus.verified,
        agreement: AgreementStatus.signed,
        joinDate: DateTime(month(-5).year, month(-5).month, 12)),
    Tenant(
        id: 't2',
        name: 'Diya Sharma',
        phone: '99887 66110',
        roomId: 'r1',
        bed: 'B',
        kyc: KycStatus.verified,
        agreement: AgreementStatus.signed,
        joinDate: DateTime(month(-5).year, month(-5).month, 4)),
    Tenant(
        id: 't3',
        name: 'Rohan Nair',
        phone: '90123 45678',
        roomId: 'r2',
        bed: 'A',
        kyc: KycStatus.pending,
        agreement: AgreementStatus.awaitingSign,
        joinDate: now.subtract(const Duration(days: 12))),
    Tenant(
        id: 't4',
        name: 'Ishita Rao',
        phone: '91234 56780',
        roomId: 'r3',
        bed: 'A',
        kyc: KycStatus.verified,
        agreement: AgreementStatus.signed,
        joinDate: DateTime(month(-4).year, month(-4).month, 10)),
  ];

  var payId = 0;
  Payment paid(String tenantId, DateTime m, int amount, String method) =>
      Payment(
        id: 'pay${++payId}',
        tenantId: tenantId,
        period: m,
        amount: amount,
        status: PaymentStatus.paid,
        dueDate: DateTime(m.year, m.month, 5),
        paidDate: DateTime(m.year, m.month, 3),
        method: method,
      );
  s.payments = [
    Payment(
        id: 'pay${++payId}',
        tenantId: 't4',
        period: month(0),
        amount: 14500,
        status: PaymentStatus.paid,
        dueDate: DateTime(now.year, now.month, 5),
        paidDate: now.subtract(const Duration(days: 1)),
        method: 'UPI'),
    Payment(
        id: 'pay${++payId}',
        tenantId: 't1',
        period: month(0),
        amount: 9500,
        status: PaymentStatus.due,
        dueDate: now.add(const Duration(days: 2))),
    Payment(
        id: 'pay${++payId}',
        tenantId: 't2',
        period: month(0),
        amount: 9500,
        status: PaymentStatus.due,
        dueDate: now.add(const Duration(days: 2))),
    Payment(
        id: 'pay${++payId}',
        tenantId: 't3',
        period: month(0),
        amount: 8200,
        status: PaymentStatus.due,
        dueDate: now.subtract(const Duration(days: 2))),
    paid('t1', month(-1), 9500, 'UPI'),
    paid('t1', month(-2), 9500, 'UPI'),
    paid('t1', month(-3), 9000, 'Bank transfer'),
    paid('t1', month(-4), 9000, 'UPI'),
    paid('t1', month(-5), 9000, 'Cash'),
    paid('t2', month(-1), 9500, 'UPI'),
    paid('t2', month(-2), 9500, 'Card'),
    paid('t2', month(-3), 9500, 'UPI'),
    paid('t2', month(-4), 9500, 'UPI'),
    paid('t2', month(-5), 9500, 'Bank transfer'),
    paid('t4', month(-1), 14500, 'UPI'),
    paid('t4', month(-2), 14500, 'UPI'),
    paid('t4', month(-3), 13500, 'Bank transfer'),
    paid('t4', month(-4), 13500, 'UPI'),
    paid('t3', month(-1), 2500, 'UPI'),
  ];
  s.maintenance = [
    MaintenanceRequest(
        id: 'm1',
        roomId: 'r2',
        title: 'Bathroom tap leaking',
        category: 'Plumbing',
        status: MaintenanceStatus.inProgress,
        priority: Priority.high,
        assignee: 'Ravi Kumar',
        createdAt: now.subtract(const Duration(hours: 4))),
    MaintenanceRequest(
        id: 'm2',
        roomId: 'r3',
        title: 'Wi-Fi not connecting',
        category: 'Internet',
        status: MaintenanceStatus.open,
        priority: Priority.medium,
        createdAt: now.subtract(const Duration(days: 1))),
    MaintenanceRequest(
        id: 'm3',
        roomId: 'r5',
        title: 'Tube light replacement',
        category: 'Electrical',
        status: MaintenanceStatus.resolved,
        priority: Priority.low,
        assignee: 'Suresh',
        createdAt: now.subtract(const Duration(days: 3))),
  ];
  s.visitors = [
    Visitor(
        id: 'v1',
        tenantId: 't1',
        name: 'Karan Mehta',
        purpose: 'Family',
        status: VisitorStatus.inside,
        expectedAt: now.subtract(const Duration(hours: 1))),
    Visitor(
        id: 'v2',
        tenantId: 't2',
        name: 'Maya Singh',
        purpose: 'Friend',
        status: VisitorStatus.awaitingApproval,
        expectedAt: now.subtract(const Duration(hours: 2))),
    Visitor(
        id: 'v3',
        tenantId: 't3',
        name: 'Delivery partner',
        purpose: 'Delivery',
        status: VisitorStatus.checkedOut,
        expectedAt: now.subtract(const Duration(hours: 5))),
  ];
  s.announcements = [
    Announcement(
        id: 'a1',
        title: 'Water tank cleaning',
        body: 'Water supply will be paused from 10 AM to 12 PM this Sunday.',
        author: 'Management',
        postedAt: now.subtract(const Duration(hours: 2))),
    Announcement(
        id: 'a2',
        title: 'Community dinner',
        body: 'Join us on the terrace this Saturday at 7:30 PM.',
        author: 'Management, Owner',
        postedAt: now.subtract(const Duration(days: 2))),
  ];
  s.attendance = [
    AttendanceRecord(
        id: 'at1',
        tenantId: 't1',
        checkIn: now.subtract(const Duration(hours: 3))),
    AttendanceRecord(
        id: 'at2',
        tenantId: 't2',
        checkIn: now.subtract(const Duration(hours: 6)),
        checkOut: now.subtract(const Duration(minutes: 30))),
    AttendanceRecord(
        id: 'at3',
        tenantId: 't3',
        checkIn: now.subtract(const Duration(hours: 2))),
  ];
  s.utilities = [
    const UtilityBill(
        id: 'u1',
        roomId: 'r1',
        previous: 1280,
        current: 1384,
        rate: AppState.utilityRate,
        status: BillStatus.generated),
    const UtilityBill(
        id: 'u2',
        roomId: 'r2',
        previous: 988,
        current: 1108,
        rate: AppState.utilityRate,
        status: BillStatus.generated),
    const UtilityBill(
        id: 'u3',
        roomId: 'r3',
        previous: 740,
        current: 807,
        rate: AppState.utilityRate,
        status: BillStatus.pendingReading),
  ];
  s.notifications = [
    AppNotification(
        id: 'n1',
        title: 'Rent received',
        body: '₹14,500 received from Ishita Rao.',
        type: NotificationType.payment,
        createdAt: now.subtract(const Duration(minutes: 12)),
        roleScope: NotificationScope.managers,
        pgId: 'p1',
        tenantId: 't4',
        relatedEntityId: 'pay1'),
    AppNotification(
        id: 'n2',
        title: 'Visitor awaiting approval',
        body: 'Maya Singh is waiting at the reception.',
        type: NotificationType.visitor,
        createdAt: now.subtract(const Duration(hours: 1)),
        roleScope: NotificationScope.managers,
        pgId: 'p1',
        tenantId: 't2',
        relatedEntityId: 'v2'),
    AppNotification(
        id: 'n3',
        title: 'Water tank cleaning',
        body: 'Water supply paused 10 AM–12 PM this Sunday.',
        type: NotificationType.announcement,
        createdAt: now.subtract(const Duration(hours: 3)),
        roleScope: NotificationScope.everyone,
        relatedEntityId: 'a1'),
    AppNotification(
        id: 'n4',
        title: 'Rent reminder',
        body: 'Your rent of ₹9,500 is due soon.',
        type: NotificationType.payment,
        createdAt: now.subtract(const Duration(hours: 5)),
        roleScope: NotificationScope.tenant,
        tenantId: 't1',
        pgId: 'p1'),
  ];
}

void main() {
  late AppState state;

  setUp(() {
    state = AppState();
    seedFixture(state);
  });

  test('all supported roles have user-facing labels', () {
    expect(UserRole.values.map((role) => role.label).toList(),
        ['Owner', 'Tenant', 'Admin']);
  });

  test('app theme uses Material 3 and the brand primary colour', () {
    final theme = buildAppTheme();
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary.toARGB32(), primary.toARGB32());
  });

  test('a fresh AppState holds no data and is signed out', () {
    final fresh = AppState();
    expect(fresh.isLoggedIn, isFalse);
    expect(fresh.pgs, isEmpty);
    expect(fresh.tenants, isEmpty);
    expect(fresh.payments, isEmpty);
  });

  test('models survive a toMap/fromMap round trip', () {
    final payment = state.payments.first;
    expect(Payment.fromMap(payment.toMap()).toMap(), payment.toMap());
    final tenant = state.tenants.first;
    expect(Tenant.fromMap(tenant.toMap()).toMap(), tenant.toMap());
    final record = state.attendance.first;
    expect(AttendanceRecord.fromMap(record.toMap()).toMap(), record.toMap());
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

  test('an expired subscription blocks owner and tenant login', () {
    final past =
        DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    final future =
        DateTime.now().add(const Duration(days: 5)).toIso8601String();

    final expiredOwner = evaluateProfileAccess(
      profile: {'role': 'owner', 'customer_id': 'c1', 'platform_admin': false},
      customer: {'status': 'enabled', 'expires_at': past},
    );
    expect(expiredOwner.role, isNull);
    expect(expiredOwner.error, contains('expired'));

    final expiredTenant = evaluateProfileAccess(
      profile: {'role': 'tenant', 'customer_id': 'c1', 'platform_admin': false},
      customer: {'status': 'enabled', 'expires_at': past},
    );
    expect(expiredTenant.role, isNull);
    expect(expiredTenant.error, contains('expired'));

    // Still within the window → allowed.
    final active = evaluateProfileAccess(
      profile: {'role': 'owner', 'customer_id': 'c1', 'platform_admin': false},
      customer: {'status': 'enabled', 'expires_at': future},
    );
    expect(active.role, UserRole.owner);
    expect(active.error, isNull);
  });

  test('Customer subscription window drives expired/active', () {
    final now = DateTime.now();
    final expired = Customer(
        id: 'c1',
        businessName: 'X',
        createdAt: now,
        startsAt: now.subtract(const Duration(days: 31)),
        expiresAt: now.subtract(const Duration(days: 1)));
    expect(expired.expired, isTrue);
    expect(expired.active, isFalse);

    final live = Customer(
        id: 'c2',
        businessName: 'Y',
        createdAt: now,
        startsAt: now,
        expiresAt: now.add(const Duration(days: 30)));
    expect(live.expired, isFalse);
    expect(live.active, isTrue);
    // Round-trips with the new fields.
    expect(Customer.fromMap(live.toMap()).expiresAt, live.expiresAt);
  });

  test('the subscriptions migration adds the window and gates expiry', () {
    final sql = File('supabase/009_subscriptions.sql').readAsStringSync();
    expect(sql, contains('add column if not exists starts_at'));
    expect(sql, contains('add column if not exists expires_at'));
    expect(sql, contains("interval '30 days'"));
    expect(sql, contains('c.expires_at > now()')); // helper is expiry-aware
    final fn =
        File('supabase/functions/create-customer/index.ts').readAsStringSync();
    expect(fn, contains('starts_at'));
    expect(fn, contains('expires_at'));
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

  test(
      'sign-in fails closed and creates no session when Supabase is unavailable',
      () async {
    final error = await state.signInCloud(
        email: 'a@b.c', password: 'password', portal: LoginPortal.owner);
    expect(error, isNotNull);
    expect(state.isLoggedIn, isFalse);
  });

  test('payments are linked to real tenants and rooms by id', () {
    for (final payment in state.payments) {
      expect(state.tenantById(payment.tenantId), isNotNull,
          reason: 'payment ${payment.id} has an orphan tenantId');
    }
    for (final tenant in state.tenants) {
      expect(state.roomById(tenant.roomId), isNotNull,
          reason: 'tenant ${tenant.id} has an orphan roomId');
    }
  });

  test('overdue is computed from the due date, not stored', () {
    final overdue = state.payments
        .firstWhere((p) => p.tenantId == 't3' && p.status == PaymentStatus.due);
    expect(overdue.isOverdue, isTrue);
    expect(overdue.displayStatus, 'Overdue');

    state.currentTenantId = 't1';
    final upcoming = state.tenantDuePayment!;
    expect(upcoming.isOverdue, isFalse);
    expect(upcoming.displayStatus, 'Due');
  });

  test('a submission drives the derived payment status and resubmit rule', () {
    state.currentTenantId = 't1';
    final due = state.tenantDuePayment!;
    expect(state.paymentStatusKey(due), anyOf('due', 'overdue'));
    expect(state.canSubmit(due), isTrue);

    UpiSubmission sub(UpiStatus status) => UpiSubmission(
        id: 's1',
        tenantId: 't1',
        paymentId: due.id,
        amount: due.amount,
        utr: 'UTR1',
        status: status,
        submittedAt: DateTime.now());

    state.submissions = [sub(UpiStatus.pendingConfirmation)];
    expect(state.paymentStatusKey(due), 'pending');
    expect(state.canSubmit(due), isFalse);

    state.submissions = [sub(UpiStatus.rejected)];
    expect(state.paymentStatusKey(due), 'rejected');
    expect(state.canSubmit(due), isTrue);
  });

  test('recordPayment settles a matching current-month due in place', () {
    final collectedBefore = state.collectedAmount;
    final before = state.payments.length;
    final due = state.payments
        .firstWhere((p) => p.tenantId == 't2' && p.status == PaymentStatus.due);

    state.recordPayment(tenantId: 't2', amount: due.amount, method: 'Cash');

    expect(state.payments.length, before);
    final settled = state.payments.firstWhere((p) => p.id == due.id);
    expect(settled.status, PaymentStatus.paid);
    expect(settled.method, 'Cash');
    expect(settled.balance, 0);
    expect(state.collectedAmount, collectedBefore + due.amount);
    expect(
        state.notifications.any((n) => n.title == 'Payment recorded'), isTrue);
  });

  test('recordPayment below the due amount marks it partial', () {
    final due = state.payments
        .firstWhere((p) => p.tenantId == 't2' && p.status == PaymentStatus.due);
    final before = state.payments.length;

    state.recordPayment(tenantId: 't2', amount: 2000, method: 'Cash');

    expect(state.payments.length, before);
    final partial = state.payments.firstWhere((p) => p.id == due.id);
    expect(partial.status, PaymentStatus.partial);
    expect(partial.collected, 2000);
    expect(partial.balance, due.amount - 2000);
    expect(partial.displayStatus, 'Partial');
    expect(state.notifications.any((n) => n.title == 'Part payment recorded'),
        isTrue);

    state.recordPayment(
        tenantId: 't2', amount: due.amount - 2000, method: 'UPI');
    final done = state.payments.firstWhere((p) => p.id == due.id);
    expect(done.status, PaymentStatus.paid);
    expect(done.balance, 0);
    expect(state.payments.length, before);
  });

  test('recordPayment with no matching due creates a standalone advance row',
      () {
    final due = state.payments
        .firstWhere((p) => p.tenantId == 't2' && p.status == PaymentStatus.due);
    state.recordPayment(tenantId: 't2', amount: due.amount, method: 'Cash');
    final after = state.payments.length;

    state.recordPayment(tenantId: 't2', amount: 5000, method: 'UPI');

    expect(state.payments.length, after + 1);
    final advance = state.payments.first;
    expect(advance.tenantId, 't2');
    expect(advance.status, PaymentStatus.paid);
    expect(advance.amount, 5000);
  });

  test('monthlyRevenue aggregates paid rent per month for the chart', () {
    final revenue = state.monthlyRevenue();
    expect(revenue, hasLength(6));
    expect(revenue.last.total, state.collectedAmount);
    expect(revenue[4].total, greaterThan(0));
    expect(state.revenueGrowth, isNotNull);
  });

  test('onboarding a tenant fills a bed in the room and the property', () {
    final room = state.rooms.firstWhere((r) => r.occupied < r.beds);
    final occupiedBefore = room.occupied;
    final pgBefore = state.pgById(room.pgId)!.occupied;

    final error = state.onboardTenant(
        name: 'Neha Verma',
        phone: '90000 00001',
        roomId: room.id,
        bed: state.suggestBed(room.id));

    expect(error, isNull);
    expect(state.tenants.first.name, 'Neha Verma');
    expect(state.tenants.first.kyc, KycStatus.pending);
    expect(state.roomById(room.id)!.occupied, occupiedBefore + 1);
    expect(state.pgById(room.pgId)!.occupied, pgBefore + 1);
  });

  test('onboarding into a full room is blocked and changes nothing', () {
    final full = state.rooms.firstWhere((r) => r.occupied >= r.beds);
    final tenantsBefore = state.tenants.length;
    final occupiedBefore = full.occupied;
    final pgBefore = state.pgById(full.pgId)!.occupied;

    final error = state.onboardTenant(
        name: 'Full Roomer', phone: '90000 12345', roomId: full.id, bed: 'C');

    expect(error, isNotNull);
    expect(error, contains('full'));
    expect(state.tenants.length, tenantsBefore);
    expect(state.roomById(full.id)!.occupied, occupiedBefore);
    expect(state.pgById(full.pgId)!.occupied, pgBefore);
  });

  test('onboarding onto a taken bed label in the same room is blocked', () {
    final error = state.onboardTenant(
        name: 'Bed Clash', phone: '90000 22222', roomId: 'r2', bed: 'a');
    expect(error, isNotNull);
    expect(error, contains('taken'));
    expect(state.tenants.any((t) => t.name == 'Bed Clash'), isFalse);

    final ok = state.onboardTenant(
        name: 'Bed Ok',
        phone: '90000 22223',
        roomId: 'r2',
        bed: state.suggestBed('r2'));
    expect(ok, isNull);
    expect(state.tenants.first.name, 'Bed Ok');
  });

  test('onboarding validates name and phone before touching data', () {
    final before = state.tenants.length;
    expect(
        state.onboardTenant(
            name: '   ', phone: '90000 00001', roomId: 'r4', bed: 'B'),
        contains('name'));
    expect(
        state.onboardTenant(
            name: 'Shorty', phone: '12345', roomId: 'r4', bed: 'B'),
        contains('phone'));
    expect(state.tenants.length, before);
  });

  test('suggestBed returns the first free bed and empty when the room is full',
      () {
    expect(state.suggestBed('r2'), 'B');
    expect(state.suggestBed('r1'), '');
  });

  test('setVisitorStatus updates the visitor and raises a notification', () {
    final awaiting = state.visitors
        .firstWhere((e) => e.status == VisitorStatus.awaitingApproval);

    state.setVisitorStatus(awaiting.id, VisitorStatus.inside);
    expect(state.visitors.firstWhere((e) => e.id == awaiting.id).status,
        VisitorStatus.inside);
    expect(state.notifications.first.title, 'Visitor checked in');

    state.setVisitorStatus(awaiting.id, VisitorStatus.declined);
    expect(state.notifications.first.title, 'Visitor declined');
  });

  test('setMaintenanceStatus advances the request and assigns a technician',
      () {
    final open =
        state.maintenance.firstWhere((e) => e.status == MaintenanceStatus.open);

    state.setMaintenanceStatus(open.id, MaintenanceStatus.inProgress,
        assignee: 'Ravi Kumar');

    final updated = state.maintenance.firstWhere((e) => e.id == open.id);
    expect(updated.status, MaintenanceStatus.inProgress);
    expect(updated.assignee, 'Ravi Kumar');
    expect(state.notifications.first.type, NotificationType.maintenance);
  });

  test('publishAnnouncement adds the post and a notification', () {
    state.publishAnnouncement(
        'Lift maintenance', 'Lift unavailable on Sunday morning.');

    expect(state.announcements.first.title, 'Lift maintenance');
    expect(state.notifications.first.type, NotificationType.announcement);
  });

  test('notifications can be marked read individually and in bulk', () {
    final unread = state.notifications.firstWhere((n) => !n.read);
    state.markNotificationRead(unread.id);
    expect(
        state.notifications.firstWhere((n) => n.id == unread.id).read, isTrue);

    state.markAllNotificationsRead();
    expect(state.hasUnread, isFalse);
  });

  test('monthly dues generation is idempotent over the current data', () {
    expect(state.generateMonthlyDues(), isFalse);
  });

  test('a missing monthly due is generated at the room rent', () {
    final now = DateTime.now();
    state.payments.removeWhere((p) =>
        p.tenantId == 't1' &&
        p.period.year == now.year &&
        p.period.month == now.month);
    expect(state.generateMonthlyDues(), isTrue);

    final due = state.payments
        .firstWhere((p) => p.id == 'pay-${now.year}-${now.month}-t1');
    expect(due.amount, 9500);
    expect(due.status, PaymentStatus.due);
    expect(state.generateMonthlyDues(), isFalse);
  });

  test('generateMonthlyDues never duplicates when a partial or paid row exists',
      () {
    final now = DateTime.now();
    final i = state.payments.indexWhere((p) =>
        p.tenantId == 't1' &&
        p.period.year == now.year &&
        p.period.month == now.month);
    state.payments[i] = state.payments[i]
        .copyWith(status: PaymentStatus.partial, paidAmount: 1000);

    expect(state.generateMonthlyDues(), isFalse);
    final t1ThisMonth = state.payments.where((p) =>
        p.tenantId == 't1' &&
        p.period.year == now.year &&
        p.period.month == now.month);
    expect(t1ThisMonth, hasLength(1));
  });

  test(
      'a tenant session materialises its own due without generating owner-wide rows',
      () {
    final now = DateTime.now();
    state.payments.removeWhere(
        (p) => p.period.year == now.year && p.period.month == now.month);

    state.debugSignIn(UserRole.tenant, tenantId: 't1');

    expect(
        state.tenantPayments.any((p) => p.status == PaymentStatus.due), isTrue);
    final others = state.payments.where((p) =>
        p.tenantId != 't1' &&
        p.period.year == now.year &&
        p.period.month == now.month);
    expect(others, isEmpty);
  });

  test('onboarding a tenant creates their first monthly due', () {
    state.onboardTenant(
        name: 'Kiran Kumar', phone: '90000 00002', roomId: 'r4', bed: 'B');
    final tenant = state.tenants.first;
    final due = state.payments.firstWhere((p) => p.tenantId == tenant.id);
    expect(due.amount, 10000);
    expect(due.status, PaymentStatus.due);
  });

  test('onboarding into a new room sets its sharing/rent; tenant inherits', () {
    // p2 starts with no rooms; the room is created during onboarding.
    expect(state.rooms.where((r) => r.pgId == 'p2'), isEmpty);
    final roomId = state.ensureRoom(
        pgId: 'p2', floor: 2, roomNumber: '201', sharingType: 3, rent: 8500);
    final room = state.roomById(roomId)!;
    expect(room.beds, 3);
    expect(room.rent, 8500);
    expect(room.type, 'Triple sharing');

    final error = state.onboardTenant(
        name: 'Nisha Rao', phone: '9000000123', roomId: roomId, bed: 'A');
    expect(error, isNull);
    final tenant = state.tenants.firstWhere((t) => t.name == 'Nisha Rao');
    expect(tenant.roomId, roomId);
    final due = state.payments.firstWhere((p) => p.tenantId == tenant.id);
    expect(due.amount, 8500); // inherited the room's current rent as a snapshot

    // ensureRoom is idempotent on room number within a PG.
    final same = state.ensureRoom(
        pgId: 'p2', floor: 2, roomNumber: '201', sharingType: 1, rent: 1);
    expect(same, roomId);
  });

  test('a tenant session resolves to its linked tenant and logout clears it',
      () async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    expect(state.currentTenant?.name, 'Aarav Mehta');
    await state.logout();
    expect(state.currentTenantId, '');
    expect(state.isLoggedIn, isFalse);
    expect(state.pgs, isEmpty);
  });

  test('inviteTenant reports a friendly error without a cloud connection',
      () async {
    final result =
        await state.inviteTenant(tenantId: 't1', email: 'someone@example.com');
    expect(result.error, isNotNull);
    expect(result.error, contains('cloud account'));
    expect(result.tempPassword, isNull);
  });

  test('the active property scopes rooms, tenants and money', () {
    expect(state.activePg?.id, 'p1');
    expect(state.pgRooms, hasLength(5));
    expect(state.pgTenants, hasLength(4));
    expect(state.pgCollectedAmount, state.collectedAmount);

    state.selectPg('p2');
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
    expect(state.needsPasswordSet, isFalse);
    state.debugSignIn(UserRole.owner);
    expect(state.mustChangePassword, isFalse);
    expect(state.needsPasswordSet, isFalse);
  });

  test('a reset link opens the set-password gate; logout clears it', () async {
    expect(state.needsPasswordSet, isFalse);
    state.markPasswordRecovery();
    expect(state.passwordRecovery, isTrue);
    expect(state.needsPasswordSet, isTrue);
    await state.logout();
    expect(state.needsPasswordSet, isFalse);
  });

  test('changePassword fails closed without a cloud connection', () async {
    state.debugSignIn(UserRole.owner);
    expect(await state.changePassword('newpass1', currentPassword: 'temp'),
        isNotNull);
  });

  test('a tenant cannot see other tenants notifications or manager activity',
      () {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    final visible = state.visibleNotifications;

    expect(visible.every((n) => n.roleScope != NotificationScope.managers),
        isTrue);
    expect(
        visible.every((n) =>
            n.roleScope != NotificationScope.tenant || n.tenantId == 't1'),
        isTrue);

    expect(visible.any((n) => n.body.contains('Ishita Rao')), isFalse);
    expect(
        visible.any((n) => n.roleScope == NotificationScope.everyone), isTrue);
    expect(visible.any((n) => n.tenantId == 't1'), isTrue);
  });

  test('an owner sees managerial and workspace notifications for the active PG',
      () {
    state.debugSignIn(UserRole.owner);
    final visible = state.visibleNotifications;

    expect(visible.any((n) => n.body.contains('Ishita Rao')), isTrue);
    expect(
        visible.any((n) => n.roleScope == NotificationScope.everyone), isTrue);
    expect(
        visible.any((n) => n.roleScope == NotificationScope.tenant), isFalse);
  });

  test('a tenant only ever sees their own payments', () {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    expect(state.tenantPayments, isNotEmpty);
    expect(state.tenantPayments.every((p) => p.tenantId == 't1'), isTrue);
    expect(state.payments.any((p) => p.tenantId != 't1'), isTrue);
    expect(state.tenantPayments.any((p) => p.tenantId != 't1'), isFalse);
  });

  test('a tenant can never mark a due paid — no client API and no cloud',
      () async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    final due = state.tenantDuePayment!;
    // The only tenant action is submitting proof; it fails closed offline and
    // never flips the due to paid.
    final error = await state.submitPayment(payment: due, utr: '123456789012');
    expect(error, isNotNull);
    expect(state.payments.firstWhere((p) => p.id == due.id).status,
        PaymentStatus.due);
  });

  test('confirm and reject fail closed without a cloud connection', () async {
    state.debugSignIn(UserRole.owner);
    final sub = UpiSubmission(
        id: 's9',
        tenantId: 't1',
        paymentId: 'pay-x',
        amount: 9500,
        utr: 'UTR9',
        status: UpiStatus.pendingConfirmation,
        submittedAt: DateTime.now());
    expect(await state.confirmSubmission(sub), isNotNull);
    expect(await state.rejectSubmission(sub, 'blurry'), isNotNull);
    expect(await state.rejectSubmission(sub, ''), isNotNull);
  });

  test('owner sees a duplicate UTR + amount warning', () {
    state.debugSignIn(UserRole.owner);
    final a = UpiSubmission(
        id: 'a',
        tenantId: 't1',
        paymentId: 'p-a',
        amount: 9500,
        utr: 'DUP',
        status: UpiStatus.pendingConfirmation,
        submittedAt: DateTime.now());
    final b = UpiSubmission(
        id: 'b',
        tenantId: 't2',
        paymentId: 'p-b',
        amount: 9500,
        utr: 'DUP',
        status: UpiStatus.pendingConfirmation,
        submittedAt: DateTime.now());
    final c = UpiSubmission(
        id: 'c',
        tenantId: 't3',
        paymentId: 'p-c',
        amount: 100,
        utr: 'OTHER',
        status: UpiStatus.pendingConfirmation,
        submittedAt: DateTime.now());
    state.submissions = [a, b, c];
    expect(state.duplicateOf(a)?.id, 'b');
    expect(state.duplicateOf(c), isNull);
    expect(state.pendingSubmissions.length, 3);
  });

  test('maintenance updates reach only tenants in that room', () {
    state.debugSignIn(UserRole.owner);
    final open = state.maintenance.firstWhere((m) => m.roomId == 'r2');
    state.setMaintenanceStatus(open.id, MaintenanceStatus.inProgress,
        assignee: 'Ravi');

    final note =
        state.notifications.firstWhere((n) => n.title == 'Maintenance updated');
    expect(note.roleScope, NotificationScope.tenant);
    expect(note.tenantId, 't3');

    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    expect(
        state.visibleNotifications.any((n) => n.title == 'Maintenance updated'),
        isFalse);
  });

  testWidgets('tenant notification centre hides other tenants activity',
      (tester) async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(
          theme: buildAppTheme(), home: const NotificationsScreen()),
    ));
    await tester.pump();
    expect(find.textContaining('Ishita Rao'), findsNothing);
    expect(find.textContaining('Maya Singh'), findsNothing);
    expect(find.text('Rent reminder'), findsOneWidget);
  });

  test('payments export as spreadsheet-ready CSV', () {
    final csv = state.paymentsCsv();
    final lines = csv.split('\n');
    expect(lines.first,
        'Receipt,Tenant,Month,Amount,Collected,Balance,Status,Due date,Paid date,Method');
    expect(lines.length, state.payments.length + 1);
    expect(csv, contains('"Aarav Mehta"'));
    expect(csv, contains('"9500"'));
    expect(state.paymentsCsv(), isNot(contains('""Aarav')));
  });

  test('formatting helpers render Indian currency and relative time', () {
    expect(inr(9500), '₹9,500');
    expect(inr(384000), '₹3,84,000');
    expect(relativeTime(DateTime.now()), 'Just now');
    expect(relativeTime(DateTime.now().subtract(const Duration(minutes: 12))),
        '12 min ago');
    expect(relativeTime(DateTime.now().subtract(const Duration(hours: 3))),
        '3 hrs ago');
  });

  testWidgets('owner navigation shows the management tabs', (tester) async {
    state.debugSignIn(UserRole.owner);
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Manage'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('My Rent'), findsNothing);
    expect(find.text('My Requests'), findsNothing);
  });

  testWidgets('tenant navigation shows only tenant tabs', (tester) async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('My Rent'), findsOneWidget);
    expect(find.text('My Requests'), findsOneWidget);
    expect(find.text('Visitors'), findsOneWidget);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Properties'), findsNothing);
  });

  testWidgets('admin sees customer management, not the PG owner UI',
      (tester) async {
    state.debugSignIn(UserRole.admin);
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Properties'), findsNothing);
    expect(find.text('Operations'), findsNothing);
    expect(find.text('Manage'), findsNothing);
  });

  testWidgets('tenants are blocked from owner-only screens', (tester) async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(theme: buildAppTheme(), home: const TenantsScreen()),
    ));
    await tester.pump();
    expect(find.text('This area is for PG managers'), findsOneWidget);
    expect(find.text('Onboard'), findsNothing);
  });

  testWidgets('utility billing and attendance are gone from the module grid',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child:
          MaterialApp(theme: buildAppTheme(), home: const ModulesHubScreen()),
    ));
    await tester.pump();
    expect(find.text('Utility billing'), findsNothing);
    expect(find.text('Attendance'), findsNothing);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Announcements'), findsOneWidget);
  });

  test('every record a session creates is stamped with its customer scope', () {
    state.debugSignIn(UserRole.owner);
    final scope = state.customerId;

    final room = state.rooms.firstWhere((r) => r.occupied < r.beds);
    state.onboardTenant(
        name: 'Stamp Test',
        phone: '90000 12399',
        roomId: room.id,
        bed: state.suggestBed(room.id));
    final tenant = state.tenants.first;
    expect(tenant.customerId, scope);
    expect(state.payments.firstWhere((p) => p.tenantId == tenant.id).customerId,
        scope);

    state.publishAnnouncement('Scoped', 'Body');
    expect(state.announcements.first.customerId, scope);
    expect(state.notifications.first.customerId, scope);

    state.addVisitor(
        name: 'Scoped Visitor', tenantId: tenant.id, purpose: 'Family');
    expect(state.visitors.first.customerId, scope);

    state.addMaintenanceRequest(
        title: 'Scoped issue',
        roomId: room.id,
        category: 'Other',
        priority: Priority.low);
    expect(state.maintenance.first.customerId, scope);

    state.addRoom(const Room(
        id: 'r-scope',
        pgId: 'p1',
        number: '999',
        floor: 9,
        beds: 2,
        occupied: 0,
        rent: 5000));
    expect(state.rooms.last.customerId, scope);

    state.savePg(const Pg(
        id: 'p-scope',
        name: 'Scoped PG',
        address: 'X',
        beds: 10,
        occupied: 0,
        amenities: '',
        rating: 4.0));
    expect(state.pgs.first.customerId, scope);
  });

  test('SaaS models survive a toMap/fromMap round trip', () {
    final now = DateTime.now();
    final customer = Customer(
        id: 'c1',
        businessName: 'Acme PG',
        ownerName: 'A',
        ownerEmail: 'a@b.c',
        phone: '9',
        status: CustomerStatus.disabled,
        plan: 'pro',
        createdAt: now,
        disabledAt: now);
    expect(Customer.fromMap(customer.toMap()).toMap(), customer.toMap());
    expect(customer.enabled, isFalse);

    final invite = TenantInvite(
        id: 'i1',
        customerId: 'c1',
        tenantId: 't1',
        email: 'x@y.z',
        token: 'tok',
        status: InviteStatus.pending,
        expiresAt: now.add(const Duration(days: 7)));
    expect(TenantInvite.fromMap(invite.toMap()).toMap(), invite.toMap());
    expect(invite.usable, isTrue);
    expect(
        TenantInvite.fromMap({...invite.toMap(), 'status': 'revoked'}).usable,
        isFalse);

    final submission = PaymentSubmission(
        id: 's1',
        customerId: 'c1',
        pgId: 'p1',
        tenantId: 't1',
        dueId: 'd1',
        amount: 9500,
        utr: 'UTR123',
        submittedAt: now);
    expect(PaymentSubmission.fromMap(submission.toMap()).toMap(),
        submission.toMap());
    expect(submission.status, SubmissionStatus.pendingConfirmation);

    const bed =
        Bed(id: 'b1', customerId: 'c1', pgId: 'p1', roomId: 'r1', label: 'A');
    expect(Bed.fromMap(bed.toMap()).toMap(), bed.toMap());

    final rule = RentRule(
        id: 'rr1',
        customerId: 'c1',
        pgId: 'p1',
        sharingType: 2,
        amount: 9500,
        effectiveFrom: now);
    expect(RentRule.fromMap(rule.toMap()).toMap(), rule.toMap());

    final log = AuditLog(
        id: 'l1',
        customerId: null,
        actorUserId: 'u1',
        actorRole: 'admin',
        action: 'customer_created',
        entityType: 'customer',
        entityId: 'c1',
        afterJson: const {'status': 'enabled'},
        createdAt: now);
    expect(AuditLog.fromMap(log.toMap()).toMap(), log.toMap());
  });

  test('the SaaS migration scopes and locks down every business table', () {
    final sql = File('supabase/004_saas_core.sql').readAsStringSync();
    const tables = [
      'customers',
      'profiles',
      'pgs',
      'floors',
      'rooms',
      'beds',
      'tenants',
      'tenant_invites',
      'rent_rules',
      'pg_payment_settings',
      'payment_dues',
      'payments',
      'payment_submissions',
      'payment_proof_files',
      'complaints',
      'notices',
      'visitors',
      'audit_logs',
    ];
    for (final table in tables) {
      expect(sql, contains('create table if not exists public.$table'),
          reason: '$table must exist');
      expect(
          sql, contains('alter table public.$table enable row level security'),
          reason: '$table must enable RLS');
    }
    for (final table in tables.where(
        (t) => t != 'customers' && t != 'profiles' && t != 'audit_logs')) {
      expect(
          sql,
          contains(RegExp(
              'create table if not exists public\\.$table[^;]*customer_id\\s+uuid not null',
              dotAll: true)),
          reason: '$table must require customer_id');
    }
    expect(sql, contains("c.status = 'enabled'"));
    expect(sql.contains('payment_dues_tenant_read'), isTrue);
    expect(sql.contains('payment_dues_tenant_insert'), isFalse,
        reason: 'tenants must never write dues');
    expect(sql, contains("'payment-proofs'"));
    expect(sql, contains('pp_tenant_insert'));
    expect(sql, contains('unique (tenant_id, period)'));
  });

  // ---- Prompt 7: tenant invite tokens & temporary passwords ----

  test('invite message contains credentials, links and instructions', () {
    final expiry = DateTime(2026, 7, 17);
    final message = buildInviteMessage(
        tenantName: 'Aarav Mehta',
        pgName: 'HSR Layout PG',
        email: 'aarav@example.com',
        tempPassword: 'x7kQm2p4Rt',
        inviteToken: 'tok123abc',
        expiresAt: expiry);
    expect(message, contains('aarav@example.com'));
    expect(message, contains('Temporary password: x7kQm2p4Rt'));
    expect(message, contains(apkDownloadUrl));
    expect(message, contains(appWebUrl));
    expect(message, contains(inviteLink('tok123abc')));
    expect(message, contains('set your own password'));
    expect(message, contains('temporary password stops working'));
    expect(message, contains('expires on ${formatFullDate(expiry)}'));
  });

  test('invite message for a linked existing account never shows a password',
      () {
    final message = buildInviteMessage(
        tenantName: 'Aarav Mehta',
        pgName: 'HSR Layout PG',
        email: 'aarav@example.com',
        tempPassword: null,
        inviteToken: 'tok123abc');
    expect(message, isNot(contains('Temporary password')));
    expect(message, contains('existing password'));
    expect(message, contains('aarav@example.com'));
    expect(message, contains(apkDownloadUrl));
    expect(message, contains(appWebUrl));
  });

  test('invite tokens are single-use and validate every lifecycle state', () {
    final now = DateTime(2026, 7, 10);
    final future = now.add(const Duration(days: 7));
    final past = now.subtract(const Duration(days: 1));

    // A pending, unexpired invite is the only acceptable one.
    expect(inviteAcceptError(InviteStatus.pending, future, now), isNull);
    // Expiry: pending past expires_at, or already marked expired.
    expect(inviteAcceptError(InviteStatus.pending, past, now),
        'code:invite_expired');
    expect(inviteAcceptError(InviteStatus.expired, future, now),
        'code:invite_expired');
    // Reuse prevention: accepted once means never again.
    expect(inviteAcceptError(InviteStatus.accepted, future, now),
        'code:invite_used');
    // Revocation, and a superseded (resent) invite behaves the same.
    expect(inviteAcceptError(InviteStatus.revoked, future, now),
        'code:invite_revoked');
    expect(inviteAcceptError(InviteStatus.resent, future, now),
        'code:invite_revoked');
  });

  test('invite lifecycle statuses round-trip, including resent', () {
    expect(InviteStatus.fromWire('resent'), InviteStatus.resent);
    final invite = TenantInvite(
        id: 'i2',
        customerId: 'c1',
        tenantId: 't1',
        email: 'x@y.z',
        token: 'tok',
        status: InviteStatus.resent,
        expiresAt: DateTime.now().add(const Duration(days: 7)));
    expect(TenantInvite.fromMap(invite.toMap()).status, InviteStatus.resent);
    expect(invite.usable, isFalse);
  });

  test('invite error codes map to friendly messages', () {
    expect(inviteActionMessage('code:invite_expired'), contains('expired'));
    expect(inviteActionMessage('code:invite_revoked'), contains('revoked'));
    expect(inviteActionMessage('code:invite_used'), contains('already used'));
    expect(inviteActionMessage(null), contains('went wrong'));
  });

  test('resend and revoke report a friendly error without a cloud connection',
      () async {
    state.debugSignIn(UserRole.owner);
    final resent = await state.resendInvite(tenantId: 't1');
    expect(resent.error, contains('cloud account'));
    expect(resent.tempPassword, isNull);
    final revoked = await state.revokeInvite(tenantId: 't1');
    expect(revoked.error, contains('cloud account'));
  });

  test('the invites migration defines the full lifecycle securely', () {
    final sql = File('supabase/006_invites.sql').readAsStringSync();
    expect(sql, contains('create table if not exists public.invites'));
    for (final status in [
      'pending',
      'accepted',
      'expired',
      'revoked',
      'resent'
    ]) {
      expect(sql, contains("'$status'"), reason: '$status state must exist');
    }
    expect(sql, contains('token'));
    expect(sql, contains('unique'), reason: 'tokens must be single-use');
    expect(sql, contains('expires_at'));
    expect(sql, contains('customer_id'));
    expect(
        sql, contains('alter table public.invites enable row level security'));
    expect(
        RegExp(r'create policy "[^"]*" on public\.invites\s+for (insert|update|delete)')
            .hasMatch(sql),
        isFalse,
        reason: 'clients must never write invites directly');
    // must_change_password is enforced in the backend, not only the UI.
    expect(sql, contains('as restrictive for insert'));
    expect(sql, contains('as restrictive for update'));
    expect(sql, contains('as restrictive for delete'));
    expect(sql, contains("must_change_password"));
    // The relational mirror gains the same vocabulary.
    expect(sql, contains('tenant_invites_status_check'));
  });

  test('the invite function enforces lifecycle and never logs passwords', () {
    final fn = File('supabase/functions/invite/index.ts').readAsStringSync();
    for (final action in [
      '"create"',
      '"resend"',
      '"revoke"',
      '"validate"',
      '"accept"'
    ]) {
      expect(fn, contains(action), reason: '$action action must exist');
    }
    expect(fn, contains('must_change_password'));
    expect(fn, contains('code:invite_expired'));
    expect(fn, contains('code:invite_revoked'));
    expect(fn, contains('code:invite_used'));
    // Single-use consumption is guarded by the pending-status transition.
    expect(fn, contains('.eq("status", "pending")'));
    // Temporary passwords are returned once and never logged.
    expect(fn, isNot(contains('console.log')));
    expect(fn, isNot(contains('console.error')));
  });

  // ---- Prompt 8: audit logs ----

  test('audit_logs RLS isolates admin, owner and tenant', () {
    final sql = File('supabase/004_saas_core.sql').readAsStringSync();
    for (final field in [
      'customer_id',
      'actor_user_id',
      'actor_role',
      'action',
      'entity_type',
      'entity_id',
      'before_json',
      'after_json',
      'ip',
      'user_agent',
      'created_at',
    ]) {
      expect(sql, contains(field), reason: '$field column must exist');
    }
    expect(sql, contains('audit_logs_admin_read'));
    expect(sql, contains('audit_logs_admin_insert'));
    expect(sql, contains('audit_logs_owner_read'));
    expect(sql, contains('audit_logs_owner_insert'));
    expect(sql, isNot(contains('audit_logs_tenant')),
        reason: 'tenants must have no audit access');
  });

  test('AuditLog.fromRow maps snake_case db columns', () {
    final log = AuditLog.fromRow({
      'id': 42,
      'customer_id': 'c1',
      'actor_user_id': 'u1',
      'actor_role': 'owner',
      'action': 'pg_created',
      'entity_type': 'pg',
      'entity_id': 'p1',
      'before_json': null,
      'after_json': {'name': 'HSR'},
      'created_at': DateTime(2026, 7, 10).toIso8601String(),
    });
    expect(log.id, '42');
    expect(log.customerId, 'c1');
    expect(log.action, 'pg_created');
    expect(log.afterJson?['name'], 'HSR');
  });

  test('loadAuditLogs fails closed without a cloud connection', () async {
    expect(await state.loadAuditLogs(), isEmpty);
  });

  test('edge functions write audit_logs for sensitive actions', () {
    final invite =
        File('supabase/functions/invite/index.ts').readAsStringSync();
    for (final action in [
      'tenant_invited',
      'tenant_invite_resent',
      'tenant_invite_revoked'
    ]) {
      expect(invite, contains(action));
    }
    expect(invite, contains('audit_logs'));

    final customer =
        File('supabase/functions/create-customer/index.ts').readAsStringSync();
    expect(customer, contains('customer_created'));
    expect(customer, contains('owner_created'));
    expect(customer, contains('audit_logs'));

    final adminFn =
        File('supabase/functions/create-admin/index.ts').readAsStringSync();
    expect(adminFn, contains('admin_created'));
    expect(adminFn, contains('audit_logs'));
  });

  // ---- Prompt 9: manual UPI payments ----

  test('UpiSettings.usable requires an enabled, valid UPI id', () {
    expect(const UpiSettings(enabled: true, upiId: 'a@bank').usable, isTrue);
    expect(const UpiSettings(enabled: false, upiId: 'a@bank').usable, isFalse);
    expect(const UpiSettings(enabled: true, upiId: 'notaupi').usable, isFalse);
  });

  test('UpiSubmission.fromRow maps db columns and status', () {
    final s = UpiSubmission.fromRow({
      'id': 'sub1',
      'tenant_id': 't1',
      'payment_id': 'pay-1',
      'amount': 9500,
      'utr': 'UTR123',
      'status': 'confirmed',
      'submitted_at': DateTime(2026, 7, 10).toIso8601String(),
      'screenshot_path': 'o/p/t/pay-1/x.jpg',
    });
    expect(s.id, 'sub1');
    expect(s.status, UpiStatus.confirmed);
    expect(s.amount, 9500);
    expect(s.screenshotPath, isNotNull);
  });

  test('payment actions fail closed without a cloud connection', () async {
    expect(
        await state.saveUpiSettings('p1',
            upiId: 'x@y', payeeName: 'A', enabled: true),
        isNotNull);
    expect(await state.loadUpiSettings('p1'), isNull);
    await state.loadSubmissions();
    expect(state.submissions, isEmpty);
  });

  test('the payments migration enforces UPI RLS and tenant restrictions', () {
    final sql = File('supabase/007_payments.sql').readAsStringSync();
    expect(sql, contains('create table if not exists public.pg_upi_settings'));
    expect(sql, contains('create table if not exists public.upi_submissions'));
    for (final s in ['pending_confirmation', 'confirmed', 'rejected']) {
      expect(sql, contains("'$s'"));
    }
    // Tenant may only INSERT a pending submission (no update/confirm path).
    expect(sql, contains('member submits payment'));
    expect(sql, contains("status = 'pending_confirmation'"));
    expect(sql, isNot(contains('member updates submissions')));
    // Owner + admin read, cross-customer isolation via owner_id / admin check.
    expect(sql, contains('owner manages submissions'));
    expect(sql, contains('admin reads submissions'));
    expect(sql, contains('public.is_platform_admin()'));
    // Tenants can no longer write the payments blob (cannot self-mark paid).
    expect(
        sql,
        contains(
            "key in ('maintenance', 'visitors', 'attendance', 'notifications')"));
    // Storage proofs are workspace-scoped.
    expect(sql, contains("'payment-proofs'"));
    expect(sql, contains('can_access_workspace'));
    // Duplicate detection index on customer/amount/utr scope.
    expect(sql, contains('upi_submissions_dup_idx'));
  });

  test('setLanguage switches the active language and locale', () {
    expect(state.language, AppLanguage.english);
    state.setLanguage(AppLanguage.telugu);
    expect(state.language, AppLanguage.telugu);
    expect(state.locale.languageCode, 'te');
  });

  test('setPushEnabled toggles the push preference', () {
    expect(state.pushEnabled, isTrue);
    state.setPushEnabled(false);
    expect(state.pushEnabled, isFalse);
  });

  test('dashboard favourites toggle, persist in-memory and order first',
      () async {
    SharedPreferences.setMockInitialValues({});
    expect(state.isFavorite('qa.recordRent'), isFalse);

    state.toggleFavorite('qa.recordRent');
    expect(state.isFavorite('qa.recordRent'), isTrue);
    state.toggleFavorite('qa.recordRent');
    expect(state.isFavorite('qa.recordRent'), isFalse);

    // Favourites float to the front, preserving relative order otherwise.
    state.toggleFavorite('qa.maintenance');
    final items = ['qa.addTenant', 'qa.recordRent', 'qa.maintenance', 'qa.b'];
    final ordered = state.favoritesFirst(items, (e) => e);
    expect(ordered.first, 'qa.maintenance');
    expect(
        ordered, ['qa.maintenance', 'qa.addTenant', 'qa.recordRent', 'qa.b']);
  });

  test('announcement audience filtering respects property and tenant', () {
    state.publishAnnouncement('HSR only', 'For HSR tenants', pgId: 'p1');
    state.publishAnnouncement('Everyone', 'For all tenants');

    state.debugSignIn(UserRole.owner);
    state.selectPg('p1');
    expect(
        state.visibleAnnouncements.any((a) => a.title == 'HSR only'), isTrue);
    expect(
        state.visibleAnnouncements.any((a) => a.title == 'Everyone'), isTrue);
    state.selectPg('p2');
    expect(
        state.visibleAnnouncements.any((a) => a.title == 'HSR only'), isFalse);
    expect(
        state.visibleAnnouncements.any((a) => a.title == 'Everyone'), isTrue);

    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    expect(
        state.visibleAnnouncements.any((a) => a.title == 'HSR only'), isTrue);
    expect(
        state.visibleAnnouncements.any((a) => a.title == 'Everyone'), isTrue);
  });

  test('updatePersonalDetails edits a tenant record', () async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    final error = await state.updatePersonalDetails(
        name: 'Aarav M', phone: '90000 99999');
    expect(error, isNull);
    expect(state.currentTenant?.name, 'Aarav M');
    expect(state.currentTenant?.phone, '90000 99999');
    expect(state.displayName, 'Aarav M');
  });

  testWidgets('navigation labels localize to the selected language',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    state.setLanguage(AppLanguage.hindi);
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('प्रबंधन'), findsOneWidget);
    expect(find.text('किराया'), findsOneWidget);
    expect(find.text('Manage'), findsNothing);
  });

  // ---- Prompt 10: full localization ----

  test('the chosen language is read back on startup (persistence)', () async {
    SharedPreferences.setMockInitialValues({'app_language': 'te'});
    final fresh = AppState();
    expect(fresh.language, AppLanguage.english);
    await fresh.loadLanguage();
    expect(fresh.language, AppLanguage.telugu);
  });

  test('setLanguage writes the selection to shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    state.setLanguage(AppLanguage.hindi);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_language'), 'hi');
  });

  test('backend error codes map to localized messages', () {
    const en = AppLocalizations(Locale('en'));
    const hi = AppLocalizations(Locale('hi'));
    expect(en.error('code:bad_credentials'), 'Wrong email or password.');
    expect(hi.error('code:bad_credentials'), isNot('Wrong email or password.'));
    expect(en.error('code:network'), contains('server'));
    // A non-code string is returned unchanged (already a message).
    expect(en.error('Already readable'), 'Already readable');
    expect(en.error(null), contains('went wrong'));
  });

  test('every added key is translated in Hindi and Telugu', () {
    const keys = [
      'auth.choose',
      'auth.ownerLogin',
      'auth.signIn',
      'dash.quickActions',
      'wiz.title',
      'wiz.stepReview',
      'inv.inviteToApp',
      'upi.pay',
      'status.pending',
    ];
    for (final code in ['hi', 'te']) {
      final l = AppLocalizations(Locale(code));
      const en = AppLocalizations(Locale('en'));
      for (final k in keys) {
        expect(l.t(k), isNotEmpty, reason: '$code missing $k');
        expect(l.t(k), isNot(en.t(k)), reason: '$code not translated: $k');
      }
    }
  });

  Widget localized(AppState s, Widget home, {bool wrap = false}) => AppScope(
        notifier: s,
        child: MaterialApp(
          theme: buildAppTheme(),
          locale: s.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: wrap ? Scaffold(body: home) : home,
        ),
      );

  testWidgets('auth portals render in the selected language', (tester) async {
    state.setLanguage(AppLanguage.hindi);
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('मालिक लॉगिन'), findsOneWidget);
    expect(find.text('किरायेदार लॉगिन'), findsOneWidget);
    expect(find.text('Owner login'), findsNothing);
  });

  testWidgets('dashboard is localized for the owner', (tester) async {
    state.debugSignIn(UserRole.owner);
    state.setLanguage(AppLanguage.telugu);
    await tester
        .pumpWidget(localized(state, const DashboardScreen(), wrap: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('త్వరిత చర్యలు'), findsOneWidget);
    expect(find.text('Quick actions'), findsNothing);
  });

  testWidgets('quick-action tiles show favourite stars on the dashboard',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    await tester
        .pumpWidget(localized(state, const DashboardScreen(), wrap: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.star_border), findsWidgets);
  });

  testWidgets('the pushed Manage hub has a working Back button',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ModulesHubScreen())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Pushed hub shows an app bar with a Back button…
    expect(find.byType(BackButton), findsOneWidget);
    // …and tapping it returns to the previous screen.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the PG setup wizard is localized', (tester) async {
    state.debugSignIn(UserRole.owner);
    state.setLanguage(AppLanguage.hindi);
    await tester.pumpWidget(localized(state, const PgSetupWizard()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('अपना पीजी सेट करें'), findsWidgets);
    expect(find.text('संपत्ति विवरण'), findsOneWidget);
  });

  testWidgets('the invite action is localized', (tester) async {
    state.debugSignIn(UserRole.owner);
    state.setLanguage(AppLanguage.hindi);
    await tester.pumpWidget(localized(state, const TenantsScreen()));
    await tester.pump();
    await tester.tap(find.text('Aarav Mehta'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('ऐप में आमंत्रित करें'), findsOneWidget);
  });

  testWidgets('first login requires temporary + new + confirm password',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    await tester.pumpWidget(localized(state, const SetPasswordScreen()));
    await tester.pump();
    expect(find.text('Temporary password'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });

  testWidgets('reset-link flow hides the temporary-password field',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    state.markPasswordRecovery();
    await tester.pumpWidget(localized(state, const SetPasswordScreen()));
    await tester.pump();
    expect(find.text('Temporary password'), findsNothing);
    expect(find.text('New password'), findsOneWidget);
  });

  testWidgets('profile personal-details row opens an editable sheet',
      (tester) async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: state.locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate
        ],
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

  testWidgets('rental agreement is gone from the tenant details and profile',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(theme: buildAppTheme(), home: const TenantsScreen()),
    ));
    await tester.pump();
    await tester.tap(find.text('Aarav Mehta'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Agreement'), findsNothing);
    expect(find.textContaining('e-sign'), findsNothing);
    expect(find.text('Call tenant'), findsOneWidget);
  });

  Widget dashboardHarness() => AppScope(
        notifier: state,
        child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(body: DashboardScreen())),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  Finder tileFor(Finder label) =>
      find.ancestor(of: label, matching: find.byType(InkWell)).first;

  testWidgets('owner stat tiles navigate to their scoped screens',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    await tester.pumpWidget(dashboardHarness());
    await settle(tester);

    await tester.tap(tileFor(find.text('Occupancy')));
    await settle(tester);
    expect(find.text('Bed occupancy'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(tileFor(find.text('Collected')));
    await settle(tester);
    expect(find.text('Rent collection'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Paid'))
            .selected,
        isTrue);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(tileFor(find.text('Outstanding')));
    await settle(tester);
    expect(find.text('Rent collection'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Due'))
            .selected,
        isTrue);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(tileFor(find.text('Open requests')));
    await settle(tester);
    expect(find.text('Service desk'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Open'))
            .selected,
        isTrue);
  });

  testWidgets('tenant rent card and quick cards navigate to tenant screens',
      (tester) async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    await tester.pumpWidget(dashboardHarness());
    await settle(tester);

    await tester.tap(tileFor(find.textContaining('RENT')));
    await settle(tester);
    expect(find.text('My rent'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(tileFor(find.text('Raise issue')));
    await settle(tester);
    expect(find.text('My requests'), findsOneWidget);
  });

  testWidgets('auth screen shows role portals and no demo or sign-up',
      (tester) async {
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

  testWidgets('tenant app shows only tenant surfaces and no owner routes',
      (tester) async {
    state.debugSignIn(UserRole.tenant, tenantId: 't1');
    await tester.pumpWidget(TenantApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('My Rent'), findsOneWidget);
    expect(find.text('My Requests'), findsOneWidget);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Properties'), findsNothing);
    expect(find.text('Onboard'), findsNothing);
  });

  testWidgets('tenant app blocks a non-tenant account', (tester) async {
    state.debugSignIn(UserRole.owner);
    await tester.pumpWidget(TenantApp(state: state));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('My Rent'), findsNothing);
  });

  testWidgets('owner/admin app auth offers no tenant portal or sign-up',
      (tester) async {
    await tester.pumpWidget(OwnerAdminApp(state: state));
    await tester.pump();
    expect(find.text('Owner login'), findsOneWidget);
    expect(find.text('Admin login'), findsOneWidget);
    expect(find.text('Tenant login'), findsNothing);
    expect(find.text('Create account'), findsNothing);
  });

  test('createAdmin fails without a server and never needs a hardcoded key',
      () async {
    final error = await state.createAdmin(
        fullName: 'A',
        email: 'a@b.c',
        password: 'password1',
        setupKey: 'whatever');
    expect(error, isNotNull);
  });

  test('adminSetupMessage maps server error codes', () {
    expect(adminSetupMessage('code:invalid_key'), contains('Invalid'));
    expect(adminSetupMessage('code:rate_limited'), contains('Too many'));
    expect(adminSetupMessage('code:key_expired'), contains('expired'));
    expect(adminSetupMessage('code:weak_password'), contains('8'));
    expect(adminSetupMessage(null), isNotEmpty);
  });

  test('the create-admin function reads the key from a secret and guards it',
      () {
    final fn =
        File('supabase/functions/create-admin/index.ts').readAsStringSync();
    expect(fn, contains('Deno.env.get("ADMIN_SETUP_KEY")'));
    expect(fn, contains('timingSafeEqual'));
    expect(fn, contains('ADMIN_SETUP_KEY_EXPIRES_AT'));
    expect(fn, contains('ADMIN_SETUP_KEY_PREVIOUS'));
    expect(fn, contains('admin_setup_attempts'));
    expect(fn, contains('"code:rate_limited"'));
    expect(fn, contains('platform_admin: true'));
    expect(fn, contains('must_change_password: false'));
    for (final line
        in fn.split('\n').where((l) => l.contains('return json('))) {
      expect(line.contains('setupKey'), isFalse,
          reason: 'the setup key must never be returned');
    }
  });

  test('the admin-setup migration locks its attempts table', () {
    final sql = File('supabase/005_admin_setup.sql').readAsStringSync();
    expect(sql,
        contains('create table if not exists public.admin_setup_attempts'));
    expect(
        sql,
        contains(
            'alter table public.admin_setup_attempts enable row level security'));
  });

  testWidgets('admin login offers admin setup with a setup-key field',
      (tester) async {
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump();
    await tester.tap(find.text('Admin login'));
    await tester.pumpAndSettle();
    expect(find.text('Set up a platform admin'), findsOneWidget);

    await tester.tap(find.text('Set up a platform admin'));
    await tester.pumpAndSettle();
    expect(find.text('Setup key'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create admin'), findsOneWidget);
  });

  testWidgets('owner login does not offer admin setup', (tester) async {
    await tester.pumpWidget(PgManagementApp(state: state));
    await tester.pump();
    await tester.tap(find.text('Owner login'));
    await tester.pumpAndSettle();
    expect(find.text('Set up a platform admin'), findsNothing);
  });

  test('the create-customer function is admin-only and seeds no data', () {
    final fn =
        File('supabase/functions/create-customer/index.ts').readAsStringSync();
    expect(fn, contains('platform_admin'));
    expect(fn, contains('"code:not_admin"'));
    expect(fn, contains('from("customers").insert'));
    expect(fn, contains('role: "owner"'));
    expect(fn, contains('customer_id: customer.id'));
    expect(fn, contains('must_change_password: true'));
    expect(fn.contains('.from("pgs")'), isFalse,
        reason: 'new customers must start empty');
    expect(fn.contains('.from("rooms")'), isFalse);
    expect(fn.contains('.from("tenants")'), isFalse);
  });

  test('customer admin actions fail closed without a server', () async {
    expect(await state.loadCustomers(), isEmpty);
    final created = await state.createCustomer(
        businessName: 'B', ownerName: 'O', ownerEmail: 'o@b.c', phone: '9');
    expect(created.error, isNotNull);
    expect(await state.setCustomerStatus('c1', false), isNotNull);
    expect(await state.deleteCustomer('c1'), isNotNull);
  });

  test('admins can read app_data so "View PGs" works, and it fails closed',
      () async {
    // The fix reads PGs from the app_data blob; a matching admin read policy
    // exists in migration 010.
    final sql = File('supabase/010_admin_app_data.sql').readAsStringSync();
    expect(sql, contains('admin reads all app_data'));
    expect(sql, contains('public.is_platform_admin()'));
    // No cloud → empty, never throws.
    expect(await state.loadCustomerPgNames('c1'), isEmpty);
  });

  test('customer deletion cascades every table atomically and is admin-only',
      () {
    final sql = File('supabase/008_delete_customer.sql').readAsStringSync();
    expect(sql, contains('function public.admin_delete_customer'));
    expect(sql, contains('security definer'));
    for (final table in [
      'app_data',
      'members',
      'invites',
      'pg_upi_settings',
      'upi_submissions',
      'push_tokens',
      'audit_logs',
      'profiles',
      'customers',
    ]) {
      expect(sql, contains('from $table'), reason: '$table must be purged');
    }
    expect(
        sql, contains('revoke all on function public.admin_delete_customer'));

    final fn =
        File('supabase/functions/delete-customer/index.ts').readAsStringSync();
    expect(fn, contains('platform_admin'));
    expect(fn, contains('admin_delete_customer'));
    expect(fn, contains('deleteUser'));
    expect(fn, contains('payment-proofs'));
  });

  testWidgets('a platform admin sees customer management, not PG screens',
      (tester) async {
    state.debugSignIn(UserRole.admin);
    await tester.pumpWidget(OwnerAdminApp(state: state));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('New customer'), findsOneWidget);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Properties'), findsNothing);
  });

  testWidgets('a new owner with no PGs is guided into the setup wizard',
      (tester) async {
    state.debugSignIn(UserRole.owner);
    state.pgs.clear();
    await tester.pumpWidget(OwnerAdminApp(state: state));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Set up your PG'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Set up your PG'));
    await tester.pumpAndSettle();
    // PG creation collects only basic details — no rent/sharing here.
    expect(find.text('Property details'), findsOneWidget);
    expect(find.text('Rent by sharing'), findsNothing);
    expect(find.text('Beds per room'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
  });

  test('createProperty can create a PG with no rooms (rent set later)', () {
    final before = state.pgs.length;
    final error =
        state.createProperty(name: 'Bare PG', address: 'Y', amenities: '');
    expect(error, isNull);
    expect(state.pgs.length, before + 1);
    expect(state.pgs.first.beds, 0);
    expect(state.rooms.where((r) => r.pgId == state.pgs.first.id), isEmpty);
  });

  test('createProperty builds the PG with floors, rooms, beds and rent', () {
    final pgsBefore = state.pgs.length;
    final error = state.createProperty(
      name: 'Indiranagar PG',
      address: 'X',
      amenities: 'Wi-Fi',
      specs: [
        (number: '101', floor: 1, beds: 2, rent: 9500),
        (number: '102', floor: 1, beds: 3, rent: 7800),
        (number: '201', floor: 2, beds: 1, rent: 14000),
      ],
    );
    expect(error, isNull);
    expect(state.pgs.length, pgsBefore + 1);
    final pg = state.pgs.first;
    expect(pg.name, 'Indiranagar PG');
    expect(pg.beds, 6);
    expect(state.activePg?.id, pg.id);

    final made = state.rooms.where((r) => r.pgId == pg.id).toList();
    expect(made, hasLength(3));
    expect(made.map((r) => r.floor).toSet(), {1, 2});
    expect(made.firstWhere((r) => r.number == '102').rent, 7800);
    expect(made.every((r) => r.customerId == state.customerId), isTrue);
  });

  test('changing a room rent never rewrites existing payments', () {
    final room = state.rooms.firstWhere((r) => r.id == 'r1');
    final due = state.payments
        .firstWhere((p) => p.tenantId == 't1' && p.status == PaymentStatus.due);
    final originalAmount = due.amount;

    expect(state.setRoomRent(room.id, 12000), isNull);
    expect(state.roomById(room.id)!.rent, 12000);
    expect(state.payments.firstWhere((p) => p.id == due.id).amount,
        originalAmount);
  });

  test('room pricing model: sharing type + rent live on the room', () {
    final roomId = state.ensureRoom(
        pgId: 'p2', floor: 1, roomNumber: '301', sharingType: 2, rent: 7000);
    final room = state.roomById(roomId)!;
    expect(room.sharingType, 2);
    expect(room.sharingType, room.beds);
    expect(room.rent, 7000);
  });

  test('a rent change applies to future dues only; history is preserved', () {
    final roomId = state.ensureRoom(
        pgId: 'p2', floor: 1, roomNumber: '302', sharingType: 2, rent: 7000);
    state.onboardTenant(
        name: 'First In', phone: '9000000001', roomId: roomId, bed: 'A');
    final first = state.tenants.firstWhere((t) => t.name == 'First In');
    final firstDue = state.payments.firstWhere((p) => p.tenantId == first.id);
    expect(firstDue.amount, 7000);

    expect(state.setRoomRent(roomId, 9000), isNull);
    // The already-created due keeps its snapshot (history preserved).
    expect(state.payments.firstWhere((p) => p.id == firstDue.id).amount, 7000);

    // A tenant assigned after the change inherits the new rent.
    state.onboardTenant(
        name: 'Second In', phone: '9000000002', roomId: roomId, bed: 'B');
    final second = state.tenants.firstWhere((t) => t.name == 'Second In');
    final secondDue = state.payments.firstWhere((p) => p.tenantId == second.id);
    expect(secondDue.amount, 9000);
  });

  test('editRoom changes number/floor and rejects duplicates', () {
    final roomId = state.ensureRoom(
        pgId: 'p2', floor: 1, roomNumber: '401', sharingType: 2, rent: 8000);
    state.ensureRoom(
        pgId: 'p2', floor: 1, roomNumber: '402', sharingType: 2, rent: 8000);
    // Rename to a free number + move floor.
    expect(state.editRoom(roomId, number: '450', floor: 3), isNull);
    final r = state.roomById(roomId)!;
    expect(r.number, '450');
    expect(r.floor, 3);
    // Duplicate number in the same PG is rejected.
    expect(state.editRoom(roomId, number: '402', floor: 3), contains('exists'));
  });

  test('deleting an empty room removes it and adjusts the PG bed count', () {
    final roomId = state.ensureRoom(
        pgId: 'p2', floor: 1, roomNumber: '501', sharingType: 3, rent: 7000);
    final pgBedsAfterAdd = state.pgById('p2')!.beds;
    expect(state.rooms.any((r) => r.id == roomId), isTrue);

    expect(state.removeRoom(roomId), isNull);
    expect(state.rooms.any((r) => r.id == roomId), isFalse);
    expect(state.pgById('p2')!.beds, pgBedsAfterAdd - 3);
  });

  test('an occupied room cannot be deleted', () {
    final roomId = state.ensureRoom(
        pgId: 'p2', floor: 1, roomNumber: '601', sharingType: 2, rent: 7000);
    state.onboardTenant(
        name: 'Occupant', phone: '9000000009', roomId: roomId, bed: 'A');
    expect(state.removeRoom(roomId), contains('active tenants'));
    expect(state.rooms.any((r) => r.id == roomId), isTrue);
  });

  test('structure reduction is blocked when beds are occupied', () {
    final occupied = state.rooms.firstWhere((r) => r.id == 'r1');
    expect(state.removeRoom(occupied.id), contains('active tenants'));
    expect(state.setRoomBeds(occupied.id, 1), contains('below occupied'));
    expect(state.rooms.any((r) => r.id == occupied.id), isTrue);

    state.createProperty(
        name: 'Fresh',
        address: 'X',
        amenities: '',
        specs: [(number: '901', floor: 9, beds: 3, rent: 5000)]);
    final empty = state.rooms.firstWhere((r) => r.number == '901');
    expect(state.setRoomBeds(empty.id, 1), isNull);
    expect(state.removeRoom(empty.id), isNull);
    expect(state.rooms.any((r) => r.id == empty.id), isFalse);
  });
}

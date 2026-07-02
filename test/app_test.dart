import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nestora_pg/main.dart';
import 'package:nestora_pg/src/app_state.dart';
import 'package:nestora_pg/src/theme.dart';

void main() {
  late Box<dynamic> box;
  late AppState state;
  var testRun = 0;

  // Each test gets its own box in a fresh temp directory. Nothing is torn
  // down between tests: awaiting real Hive IO inside a widget test's
  // fake-async zone deadlocks, and the OS reclaims the temp files anyway.
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp('nestora_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('nestora_test_${testRun++}');
    state = AppState(box)..seedIfNeeded();
  });

  test('all supported roles have user-facing labels', () {
    expect(UserRole.values.map((role) => role.label).toList(), ['Owner', 'Tenant', 'Admin']);
  });

  test('app theme uses Material 3 and the Nestora primary colour', () {
    final theme = buildAppTheme();
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary.toARGB32(), primary.toARGB32());
  });

  test('seeding populates every collection and persists to Hive', () {
    expect(state.pgs, isNotEmpty);
    expect(state.rooms, isNotEmpty);
    expect(state.tenants, isNotEmpty);
    expect(state.payments, isNotEmpty);
    expect(box.get('pgs'), isNotEmpty);
    expect(box.get('payments'), isNotEmpty);
  });

  test('login persists the session role and logout clears it', () {
    state.login(UserRole.tenant);
    expect(box.get('sessionRole'), 'tenant');
    expect(AppState(box).isLoggedIn, isTrue);

    state.logout();
    expect(box.get('sessionRole'), isNull);
    expect(AppState(box).isLoggedIn, isFalse);
  });

  test('tenantDuePayment surfaces the unpaid rent for the demo tenant', () {
    final due = state.tenantDuePayment;
    expect(due, isNotNull);
    expect(due!['tenant'], AppState.currentTenantName);
    expect(due['status'], isNot('Paid'));
  });

  test('payRent marks the payment paid, stores the method and notifies', () {
    final due = state.tenantDuePayment!;
    final collectedBefore = state.collectedAmount;

    state.payRent(due['id'] as String, 'UPI');

    expect(due['status'], 'Paid');
    expect(due['method'], 'UPI');
    expect(state.tenantDuePayment, isNull);
    expect(state.collectedAmount, collectedBefore + (due['amount'] as int));
    expect(state.notifications.first['type'], 'payment');
    expect(state.notifications.first['title'], 'Rent received');
  });

  test('recordPayment inserts a paid entry and updates totals', () {
    final collectedBefore = state.collectedAmount;

    state.recordPayment(tenant: 'Diya Sharma', amount: 9500, method: 'Cash');

    final entry = state.payments.first;
    expect(entry['tenant'], 'Diya Sharma');
    expect(entry['status'], 'Paid');
    expect(entry['method'], 'Cash');
    expect(state.collectedAmount, collectedBefore + 9500);
    expect(state.notifications.first['title'], 'Payment recorded');
  });

  test('setVisitorStatus updates the visitor and raises a notification', () {
    final awaiting = state.visitors.firstWhere((e) => e['status'] == 'Awaiting approval');

    state.setVisitorStatus(awaiting['id'] as String, 'Inside');

    expect(awaiting['status'], 'Inside');
    expect(state.notifications.first['title'], 'Visitor checked in');

    state.setVisitorStatus(awaiting['id'] as String, 'Checked out');
    expect(awaiting['status'], 'Checked out');
    expect(state.notifications.first['title'], 'Visitor checked out');
  });

  test('setMaintenanceStatus advances the request and assigns a technician', () {
    final open = state.maintenance.firstWhere((e) => e['status'] == 'Open');

    state.setMaintenanceStatus(open['id'] as String, 'In progress', assignee: 'Ravi Kumar');

    expect(open['status'], 'In progress');
    expect(open['assignee'], 'Ravi Kumar');
    expect(state.notifications.first['type'], 'maintenance');
  });

  test('publishAnnouncement adds the post and a notification', () {
    state.publishAnnouncement('Lift maintenance', 'Lift unavailable on Sunday morning.');

    expect(state.announcements.first['title'], 'Lift maintenance');
    expect(state.notifications.first['type'], 'announcement');
    expect(state.notifications.first['title'], 'New announcement');
  });

  test('toggleCheckIn records a check-in and then a check-out for today', () {
    // Seeded records can collide with the real date; start from a clean log.
    state.attendance.clear();
    expect(state.todayAttendance, isNull);

    state.toggleCheckIn();
    expect(state.isCheckedIn, isTrue);
    expect(state.todayAttendance!['checkOut'], '—');

    state.toggleCheckIn();
    expect(state.isCheckedIn, isFalse);
    expect(state.todayAttendance!['checkOut'], isNot('—'));
  });

  test('inr formats amounts in Indian currency style', () {
    expect(inr(9500), '₹9,500');
    expect(inr(384000), '₹3,84,000');
  });

  testWidgets('signing in from the auth screen opens the home shell', (tester) async {
    await tester.pumpWidget(NestoraApp(state: state));
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    // Bounded pumps instead of pumpAndSettle: pending Hive writes never
    // settle inside the fake-async zone.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.isLoggedIn, isTrue);
    expect(find.text('nestora'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
  });
}

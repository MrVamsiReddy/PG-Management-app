import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

String inr(num value) => NumberFormat.currency(
      locale: 'en_IN', symbol: '₹', decimalDigits: 0,
    ).format(value);

enum UserRole { owner, tenant, admin }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.owner => 'Owner',
        UserRole.tenant => 'Tenant',
        UserRole.admin => 'Admin',
      };
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required super.notifier, required super.child});

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class AppState extends ChangeNotifier {
  AppState(this.box) {
    final savedRole = box.get('sessionRole') as String?;
    if (savedRole != null) {
      role = UserRole.values.firstWhere((e) => e.name == savedRole);
      isLoggedIn = true;
    }
  }

  // The demo profile behind the tenant role. A multi-user build would load
  // this from the signed-in account instead.
  static const currentTenantName = 'Aarav Mehta';
  static const currentTenantRoom = '101';
  static const currentTenantBed = '101-A';
  static const ownerName = 'Ananya Kapoor';

  final Box<dynamic> box;
  bool isLoggedIn = false;
  UserRole role = UserRole.owner;

  String get displayName => role == UserRole.tenant ? currentTenantName : ownerName;
  String get initials => displayName.split(' ').map((e) => e[0]).take(2).join();

  List<Map<String, dynamic>> pgs = [];
  List<Map<String, dynamic>> rooms = [];
  List<Map<String, dynamic>> tenants = [];
  List<Map<String, dynamic>> payments = [];
  List<Map<String, dynamic>> maintenance = [];
  List<Map<String, dynamic>> visitors = [];
  List<Map<String, dynamic>> announcements = [];
  List<Map<String, dynamic>> attendance = [];
  List<Map<String, dynamic>> utilities = [];
  List<Map<String, dynamic>> notifications = [];

  void seedIfNeeded() {
    pgs = _read('pgs');
    rooms = _read('rooms');
    tenants = _read('tenants');
    payments = _read('payments');
    maintenance = _read('maintenance');
    visitors = _read('visitors');
    announcements = _read('announcements');
    attendance = _read('attendance');
    utilities = _read('utilities');
    notifications = _read('notifications');
    if (pgs.isNotEmpty) return;

    pgs = [
      {'id': 'p1', 'name': 'Nestora HSR', 'address': '27th Main, HSR Layout, Bengaluru', 'beds': 48, 'occupied': 41, 'amenities': 'Wi-Fi • Food • Laundry • CCTV', 'rating': 4.8},
      {'id': 'p2', 'name': 'Nestora Koramangala', 'address': '5th Block, Koramangala, Bengaluru', 'beds': 36, 'occupied': 29, 'amenities': 'Wi-Fi • AC • Gym • Power backup', 'rating': 4.6},
    ];
    rooms = [
      {'id': 'r1', 'number': '101', 'floor': 1, 'type': 'Double sharing', 'rent': 9500, 'beds': 2, 'occupied': 2},
      {'id': 'r2', 'number': '102', 'floor': 1, 'type': 'Triple sharing', 'rent': 8200, 'beds': 3, 'occupied': 2},
      {'id': 'r3', 'number': '201', 'floor': 2, 'type': 'Single', 'rent': 14500, 'beds': 1, 'occupied': 1},
      {'id': 'r4', 'number': '202', 'floor': 2, 'type': 'Double sharing', 'rent': 10000, 'beds': 2, 'occupied': 1},
      {'id': 'r5', 'number': '301', 'floor': 3, 'type': 'Triple sharing', 'rent': 7800, 'beds': 3, 'occupied': 3},
    ];
    tenants = [
      {'id': 't1', 'name': 'Aarav Mehta', 'phone': '98765 43210', 'room': '101-A', 'kyc': 'Verified', 'joinDate': '12 Jan 2026', 'agreement': 'Signed'},
      {'id': 't2', 'name': 'Diya Sharma', 'phone': '99887 66110', 'room': '101-B', 'kyc': 'Verified', 'joinDate': '04 Feb 2026', 'agreement': 'Signed'},
      {'id': 't3', 'name': 'Rohan Nair', 'phone': '90123 45678', 'room': '102-A', 'kyc': 'Pending', 'joinDate': '21 Jun 2026', 'agreement': 'Awaiting sign'},
      {'id': 't4', 'name': 'Ishita Rao', 'phone': '91234 56780', 'room': '201-A', 'kyc': 'Verified', 'joinDate': '10 Mar 2026', 'agreement': 'Signed'},
    ];
    payments = [
      {'id': 'pay1', 'tenant': 'Aarav Mehta', 'month': 'July 2026', 'amount': 9500, 'status': 'Due', 'date': '05 Jul'},
      {'id': 'pay2', 'tenant': 'Diya Sharma', 'month': 'July 2026', 'amount': 9500, 'status': 'Due', 'date': '05 Jul'},
      {'id': 'pay3', 'tenant': 'Rohan Nair', 'month': 'July 2026', 'amount': 8200, 'status': 'Overdue', 'date': '01 Jul'},
      {'id': 'pay4', 'tenant': 'Ishita Rao', 'month': 'July 2026', 'amount': 14500, 'status': 'Paid', 'date': '01 Jul'},
    ];
    maintenance = [
      {'id': 'm1', 'title': 'Bathroom tap leaking', 'room': '102', 'category': 'Plumbing', 'status': 'In progress', 'priority': 'High', 'assignee': 'Ravi Kumar', 'date': 'Today, 9:30 AM'},
      {'id': 'm2', 'title': 'Wi-Fi not connecting', 'room': '201', 'category': 'Internet', 'status': 'Open', 'priority': 'Medium', 'assignee': 'Unassigned', 'date': 'Yesterday'},
      {'id': 'm3', 'title': 'Tube light replacement', 'room': '301', 'category': 'Electrical', 'status': 'Resolved', 'priority': 'Low', 'assignee': 'Suresh', 'date': '30 Jun'},
    ];
    visitors = [
      {'id': 'v1', 'name': 'Karan Mehta', 'tenant': 'Aarav Mehta', 'purpose': 'Family', 'time': 'Today, 5:20 PM', 'status': 'Inside'},
      {'id': 'v2', 'name': 'Maya Singh', 'tenant': 'Diya Sharma', 'purpose': 'Friend', 'time': 'Today, 4:10 PM', 'status': 'Awaiting approval'},
      {'id': 'v3', 'name': 'Delivery partner', 'tenant': 'Rohan Nair', 'purpose': 'Delivery', 'time': 'Today, 1:45 PM', 'status': 'Checked out'},
    ];
    announcements = [
      {'id': 'a1', 'title': 'Water tank cleaning', 'body': 'Water supply will be paused from 10 AM to 12 PM this Sunday.', 'date': 'Today', 'author': 'Management'},
      {'id': 'a2', 'title': 'July community dinner', 'body': 'Join us on the terrace this Saturday at 7:30 PM.', 'date': '01 Jul', 'author': 'Ananya, Owner'},
    ];
    attendance = [
      {'id': 'at1', 'name': 'Aarav Mehta', 'date': '03 Jul', 'checkIn': '8:45 AM', 'checkOut': '—', 'status': 'In'},
      {'id': 'at2', 'name': 'Diya Sharma', 'date': '03 Jul', 'checkIn': '9:10 AM', 'checkOut': '6:30 PM', 'status': 'Out'},
      {'id': 'at3', 'name': 'Rohan Nair', 'date': '03 Jul', 'checkIn': '10:05 AM', 'checkOut': '—', 'status': 'In'},
    ];
    utilities = [
      {'id': 'u1', 'room': '101', 'previous': 1280, 'current': 1384, 'units': 104, 'amount': 832, 'status': 'Generated'},
      {'id': 'u2', 'room': '102', 'previous': 988, 'current': 1108, 'units': 120, 'amount': 960, 'status': 'Generated'},
      {'id': 'u3', 'room': '201', 'previous': 740, 'current': 807, 'units': 67, 'amount': 536, 'status': 'Pending reading'},
    ];
    notifications = [
      {'id': 'n1', 'title': 'Rent received', 'body': '₹14,500 received from Ishita Rao.', 'time': '12 min ago', 'read': false, 'type': 'payment'},
      {'id': 'n2', 'title': 'Visitor awaiting approval', 'body': 'Maya Singh is waiting at the reception.', 'time': '1 hr ago', 'read': false, 'type': 'visitor'},
      {'id': 'n3', 'title': 'Maintenance updated', 'body': 'Bathroom tap issue is now in progress.', 'time': '3 hrs ago', 'read': true, 'type': 'maintenance'},
    ];
    persistAll();
  }

  List<Map<String, dynamic>> _read(String key) {
    final raw = box.get(key, defaultValue: <dynamic>[]) as List;
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> persistAll() async {
    await Future.wait([
      box.put('pgs', pgs), box.put('rooms', rooms), box.put('tenants', tenants),
      box.put('payments', payments), box.put('maintenance', maintenance),
      box.put('visitors', visitors), box.put('announcements', announcements),
      box.put('attendance', attendance), box.put('utilities', utilities),
      box.put('notifications', notifications),
    ]);
    notifyListeners();
  }

  void login(UserRole selectedRole) {
    role = selectedRole;
    isLoggedIn = true;
    box.put('sessionRole', role.name);
    notifyListeners();
  }

  void logout() {
    isLoggedIn = false;
    box.delete('sessionRole');
    notifyListeners();
  }

  void addItem(List<Map<String, dynamic>> list, Map<String, dynamic> item) {
    list.insert(0, item);
    persistAll();
  }

  String get today => DateFormat('dd MMM').format(DateTime.now());
  String get timeNow => DateFormat('h:mm a').format(DateTime.now());
  String get currentMonth => DateFormat('MMMM yyyy').format(DateTime.now());

  void _notify(String title, String body, String type) {
    notifications.insert(0, {
      'id': 'n${DateTime.now().millisecondsSinceEpoch}',
      'title': title, 'body': body, 'time': 'Just now', 'read': false, 'type': type,
    });
  }

  Map<String, dynamic>? get tenantDuePayment {
    for (final payment in payments) {
      if (payment['tenant'] == currentTenantName && payment['status'] != 'Paid') return payment;
    }
    return null;
  }

  void payRent(String id, String method) {
    final payment = payments.firstWhere((e) => e['id'] == id);
    payment['status'] = 'Paid';
    payment['date'] = today;
    payment['method'] = method;
    _notify('Rent received', '${inr(payment['amount'] as int)} received from ${payment['tenant']}.', 'payment');
    persistAll();
  }

  void recordPayment({required String tenant, required int amount, required String method}) {
    payments.insert(0, {
      'id': 'pay${DateTime.now().millisecondsSinceEpoch}',
      'tenant': tenant, 'month': currentMonth, 'amount': amount,
      'status': 'Paid', 'date': today, 'method': method,
    });
    _notify('Payment recorded', '${inr(amount)} from $tenant marked as received.', 'payment');
    persistAll();
  }

  void setVisitorStatus(String id, String status) {
    final visitor = visitors.firstWhere((e) => e['id'] == id);
    visitor['status'] = status;
    final title = switch (status) {
      'Inside' => 'Visitor checked in',
      'Checked out' => 'Visitor checked out',
      'Declined' => 'Visitor declined',
      _ => 'Visitor updated',
    };
    _notify(title, '${visitor['name']} · ${visitor['purpose']} visit for ${visitor['tenant']}.', 'visitor');
    persistAll();
  }

  void setMaintenanceStatus(String id, String status, {String? assignee}) {
    final item = maintenance.firstWhere((e) => e['id'] == id);
    item['status'] = status;
    if (assignee != null && assignee.trim().isNotEmpty) item['assignee'] = assignee.trim();
    _notify('Maintenance updated', '${item['title']} is now ${status.toLowerCase()}.', 'maintenance');
    persistAll();
  }

  void publishAnnouncement(String title, String body) {
    announcements.insert(0, {
      'id': 'a${DateTime.now().millisecondsSinceEpoch}',
      'title': title, 'body': body, 'date': 'Just now', 'author': '$ownerName, ${role.label}',
    });
    _notify('New announcement', title, 'announcement');
    persistAll();
  }

  Map<String, dynamic>? get todayAttendance {
    for (final record in attendance) {
      if (record['name'] == currentTenantName && record['date'] == today) return record;
    }
    return null;
  }

  bool get isCheckedIn => todayAttendance?['status'] == 'In';

  void toggleCheckIn() {
    final record = todayAttendance;
    if (record == null || record['status'] == 'Out') {
      attendance.insert(0, {
        'id': 'at${DateTime.now().millisecondsSinceEpoch}',
        'name': currentTenantName, 'date': today,
        'checkIn': timeNow, 'checkOut': '—', 'status': 'In',
      });
    } else {
      record['checkOut'] = timeNow;
      record['status'] = 'Out';
    }
    persistAll();
  }

  int get totalBeds => pgs.fold(0, (sum, e) => sum + (e['beds'] as int));
  int get occupiedBeds => pgs.fold(0, (sum, e) => sum + (e['occupied'] as int));
  int get dueAmount => payments.where((e) => e['status'] != 'Paid').fold(0, (sum, e) => sum + (e['amount'] as int));
  int get collectedAmount => payments.where((e) => e['status'] == 'Paid').fold(0, (sum, e) => sum + (e['amount'] as int));
}

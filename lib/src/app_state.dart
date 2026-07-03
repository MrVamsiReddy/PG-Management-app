import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, User;

import 'format.dart';
import 'models.dart';
import 'repositories.dart';
import 'supabase_config.dart';

export 'models.dart';

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

T? _firstOrNull<T>(List<T> list, bool Function(T) test) {
  for (final item in list) {
    if (test(item)) return item;
  }
  return null;
}

class AppState extends ChangeNotifier {
  AppState(this.box) {
    _useHiveRepos();
  }

  static const schemaVersion = 2;
  static const utilityRate = 8; // ₹ per unit

  // The demo profile behind the tenant role. A multi-user build would load
  // this from the signed-in account instead.
  static const currentTenantId = 't1';
  static const ownerName = 'Ananya Kapoor';

  final Box<dynamic> box;
  late Repository<Pg> _pgRepo;
  late Repository<Room> _roomRepo;
  late Repository<Tenant> _tenantRepo;
  late Repository<Payment> _paymentRepo;
  late Repository<MaintenanceRequest> _maintenanceRepo;
  late Repository<Visitor> _visitorRepo;
  late Repository<Announcement> _announcementRepo;
  late Repository<AttendanceRecord> _attendanceRepo;
  late Repository<UtilityBill> _utilityRepo;
  late Repository<AppNotification> _notificationRepo;

  bool isLoggedIn = false;
  UserRole role = UserRole.owner;

  /// True when signed in with a real Supabase account; data then lives in the
  /// cloud instead of the local Hive box.
  bool cloudMode = false;
  String? accountEmail;
  String? _cloudName;

  void _useHiveRepos() {
    _pgRepo = HiveRepository<Pg>(box, 'pgs', fromMap: Pg.fromMap, toMap: (e) => e.toMap());
    _roomRepo = HiveRepository<Room>(box, 'rooms', fromMap: Room.fromMap, toMap: (e) => e.toMap());
    _tenantRepo = HiveRepository<Tenant>(box, 'tenants', fromMap: Tenant.fromMap, toMap: (e) => e.toMap());
    _paymentRepo = HiveRepository<Payment>(box, 'payments', fromMap: Payment.fromMap, toMap: (e) => e.toMap());
    _maintenanceRepo = HiveRepository<MaintenanceRequest>(box, 'maintenance', fromMap: MaintenanceRequest.fromMap, toMap: (e) => e.toMap());
    _visitorRepo = HiveRepository<Visitor>(box, 'visitors', fromMap: Visitor.fromMap, toMap: (e) => e.toMap());
    _announcementRepo = HiveRepository<Announcement>(box, 'announcements', fromMap: Announcement.fromMap, toMap: (e) => e.toMap());
    _attendanceRepo = HiveRepository<AttendanceRecord>(box, 'attendance', fromMap: AttendanceRecord.fromMap, toMap: (e) => e.toMap());
    _utilityRepo = HiveRepository<UtilityBill>(box, 'utilities', fromMap: UtilityBill.fromMap, toMap: (e) => e.toMap());
    _notificationRepo = HiveRepository<AppNotification>(box, 'notifications', fromMap: AppNotification.fromMap, toMap: (e) => e.toMap());
  }

  void _useSupabaseRepos() {
    final client = supabaseOrNull!;
    _pgRepo = SupabaseRepository<Pg>(client, 'pgs', fromMap: Pg.fromMap, toMap: (e) => e.toMap());
    _roomRepo = SupabaseRepository<Room>(client, 'rooms', fromMap: Room.fromMap, toMap: (e) => e.toMap());
    _tenantRepo = SupabaseRepository<Tenant>(client, 'tenants', fromMap: Tenant.fromMap, toMap: (e) => e.toMap());
    _paymentRepo = SupabaseRepository<Payment>(client, 'payments', fromMap: Payment.fromMap, toMap: (e) => e.toMap());
    _maintenanceRepo = SupabaseRepository<MaintenanceRequest>(client, 'maintenance', fromMap: MaintenanceRequest.fromMap, toMap: (e) => e.toMap());
    _visitorRepo = SupabaseRepository<Visitor>(client, 'visitors', fromMap: Visitor.fromMap, toMap: (e) => e.toMap());
    _announcementRepo = SupabaseRepository<Announcement>(client, 'announcements', fromMap: Announcement.fromMap, toMap: (e) => e.toMap());
    _attendanceRepo = SupabaseRepository<AttendanceRecord>(client, 'attendance', fromMap: AttendanceRecord.fromMap, toMap: (e) => e.toMap());
    _utilityRepo = SupabaseRepository<UtilityBill>(client, 'utilities', fromMap: UtilityBill.fromMap, toMap: (e) => e.toMap());
    _notificationRepo = SupabaseRepository<AppNotification>(client, 'notifications', fromMap: AppNotification.fromMap, toMap: (e) => e.toMap());
  }

  List<Pg> pgs = [];
  List<Room> rooms = [];
  List<Tenant> tenants = [];
  List<Payment> payments = [];
  List<MaintenanceRequest> maintenance = [];
  List<Visitor> visitors = [];
  List<Announcement> announcements = [];
  List<AttendanceRecord> attendance = [];
  List<UtilityBill> utilities = [];
  List<AppNotification> notifications = [];

  Future<void> init() async {
    if (box.get('schemaVersion') != schemaVersion) {
      await box.clear();
      await box.put('schemaVersion', schemaVersion);
    }
    final savedRole = box.get('sessionRole') as String?;
    if (savedRole != null) {
      role = UserRole.values.firstWhere((e) => e.name == savedRole);
      isLoggedIn = true;
    }
    await _loadAll();
    if (pgs.isEmpty) {
      _seed();
      await persistAll();
    }
  }

  Future<void> _loadAll() async {
    pgs = await _pgRepo.loadAll();
    rooms = await _roomRepo.loadAll();
    tenants = await _tenantRepo.loadAll();
    payments = await _paymentRepo.loadAll();
    maintenance = await _maintenanceRepo.loadAll();
    visitors = await _visitorRepo.loadAll();
    announcements = await _announcementRepo.loadAll();
    attendance = await _attendanceRepo.loadAll();
    utilities = await _utilityRepo.loadAll();
    notifications = await _notificationRepo.loadAll();
  }

  Future<void> persistAll() async {
    await Future.wait([
      _pgRepo.saveAll(pgs), _roomRepo.saveAll(rooms), _tenantRepo.saveAll(tenants),
      _paymentRepo.saveAll(payments), _maintenanceRepo.saveAll(maintenance),
      _visitorRepo.saveAll(visitors), _announcementRepo.saveAll(announcements),
      _attendanceRepo.saveAll(attendance), _utilityRepo.saveAll(utilities),
      _notificationRepo.saveAll(notifications),
    ]);
    notifyListeners();
  }

  // ---- Session ----

  /// Local demo session: no account, data stays in the on-device Hive box.
  void login(UserRole selectedRole) {
    role = selectedRole;
    isLoggedIn = true;
    box.put('sessionRole', role.name);
    notifyListeners();
  }

  Future<void> logout() async {
    if (cloudMode) {
      try {
        await supabaseOrNull?.auth.signOut();
      } catch (_) {} // Signing out while offline still logs out locally.
      cloudMode = false;
      accountEmail = null;
      _cloudName = null;
      _useHiveRepos();
      await _loadAll();
    }
    isLoggedIn = false;
    box.delete('sessionRole');
    notifyListeners();
  }

  // ---- Cloud accounts (Supabase) ----

  /// Returns a user-facing error message, or null on success.
  Future<String?> signUpCloud({required String name, required String email, required String password, required UserRole selectedRole}) async {
    final client = supabaseOrNull;
    if (client == null) return 'Cloud accounts are unavailable right now — try demo mode.';
    try {
      final result = await client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name, 'role': selectedRole.name},
      );
      if (result.session == null) {
        return 'Account created — confirm the link sent to $email, then sign in.';
      }
      await _enterCloud(result.session!.user);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }

  /// Returns a user-facing error message, or null on success.
  Future<String?> signInCloud({required String email, required String password}) async {
    final client = supabaseOrNull;
    if (client == null) return 'Cloud accounts are unavailable right now — try demo mode.';
    try {
      final result = await client.auth.signInWithPassword(email: email, password: password);
      await _enterCloud(result.user!);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }

  /// Restores a previously signed-in cloud session at app start, if any.
  Future<void> restoreCloudSession() async {
    final user = supabaseOrNull?.auth.currentSession?.user;
    if (user == null) return;
    try {
      await _enterCloud(user);
    } catch (_) {
      // Offline at startup with a cloud session: stay signed out; demo mode
      // remains available from the auth screen.
    }
  }

  Future<void> _enterCloud(User user) async {
    final metaRole = user.userMetadata?['role'] as String?;
    role = UserRole.values.firstWhere((e) => e.name == metaRole, orElse: () => UserRole.owner);
    _cloudName = user.userMetadata?['full_name'] as String?;
    accountEmail = user.email;
    cloudMode = true;
    _useSupabaseRepos();
    await _loadAll();
    if (pgs.isEmpty) {
      _seed();
      await persistAll();
    }
    isLoggedIn = true;
    notifyListeners();
  }

  // ---- Lookups ----

  Pg? pgById(String id) => _firstOrNull(pgs, (e) => e.id == id);
  Room? roomById(String id) => _firstOrNull(rooms, (e) => e.id == id);
  Tenant? tenantById(String id) => _firstOrNull(tenants, (e) => e.id == id);

  String tenantName(String id) => tenantById(id)?.name ?? 'Former tenant';
  String roomNumber(String roomId) => roomById(roomId)?.number ?? '—';
  String tenantRoomLabel(Tenant tenant) => '${roomNumber(tenant.roomId)}-${tenant.bed}';

  Tenant? get currentTenant => tenantById(currentTenantId);
  String get currentTenantRoomLabel {
    final tenant = currentTenant;
    return tenant == null ? '—' : tenantRoomLabel(tenant);
  }

  String pgNameForTenant(String tenantId) {
    final room = roomById(tenantById(tenantId)?.roomId ?? '');
    return pgById(room?.pgId ?? '')?.name ?? 'PG Management';
  }

  String get displayName {
    if (cloudMode) return _cloudName ?? accountEmail?.split('@').first ?? 'Account';
    return role == UserRole.tenant ? (currentTenant?.name ?? 'Tenant') : ownerName;
  }
  String get initials => displayName.split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join();

  // ---- Aggregates ----

  int get totalBeds => pgs.fold(0, (sum, e) => sum + e.beds);
  int get occupiedBeds => pgs.fold(0, (sum, e) => sum + e.occupied);
  int get dueAmount => payments.where((e) => e.status == PaymentStatus.due).fold(0, (sum, e) => sum + e.amount);

  int get collectedAmount {
    final now = DateTime.now();
    return payments
        .where((e) => e.status == PaymentStatus.paid && e.period.year == now.year && e.period.month == now.month)
        .fold(0, (sum, e) => sum + e.amount);
  }

  List<({DateTime month, int total})> monthlyRevenue({int months = 6}) {
    final now = DateTime.now();
    return List.generate(months, (i) {
      final month = DateTime(now.year, now.month - (months - 1 - i));
      final total = payments
          .where((e) => e.status == PaymentStatus.paid && e.period.year == month.year && e.period.month == month.month)
          .fold(0, (sum, e) => sum + e.amount);
      return (month: month, total: total);
    });
  }

  /// Growth of the last completed month over the one before, in percent.
  double? get revenueGrowth {
    final revenue = monthlyRevenue();
    if (revenue.length < 3) return null;
    final previous = revenue[revenue.length - 3].total;
    final last = revenue[revenue.length - 2].total;
    if (previous == 0) return null;
    return (last - previous) / previous * 100;
  }

  // ---- Actions ----

  String _id(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch}';

  void _notify(String title, String body, NotificationType type) {
    notifications.insert(0, AppNotification(
      id: _id('n'), title: title, body: body, type: type, createdAt: DateTime.now(),
    ));
  }

  bool get hasUnread => notifications.any((n) => !n.read);

  void markNotificationRead(String id) {
    final i = notifications.indexWhere((n) => n.id == id);
    if (i == -1) return;
    notifications[i] = notifications[i].copyWith(read: true);
    persistAll();
  }

  void markAllNotificationsRead() {
    notifications = notifications.map((n) => n.copyWith(read: true)).toList();
    persistAll();
  }

  void savePg(Pg pg) {
    final i = pgs.indexWhere((e) => e.id == pg.id);
    if (i == -1) {
      pgs.insert(0, pg);
    } else {
      pgs[i] = pg;
    }
    persistAll();
  }

  void addRoom(Room room) {
    rooms.add(room);
    persistAll();
  }

  void onboardTenant({required String name, required String phone, required String roomId, required String bed}) {
    tenants.insert(0, Tenant(
      id: _id('t'), name: name, phone: phone, roomId: roomId, bed: bed,
      kyc: KycStatus.pending, agreement: AgreementStatus.awaitingSign, joinDate: DateTime.now(),
    ));
    final i = rooms.indexWhere((r) => r.id == roomId);
    if (i != -1 && rooms[i].occupied < rooms[i].beds) {
      rooms[i] = rooms[i].copyWith(occupied: rooms[i].occupied + 1);
      final p = pgs.indexWhere((e) => e.id == rooms[i].pgId);
      if (p != -1 && pgs[p].occupied < pgs[p].beds) {
        pgs[p] = pgs[p].copyWith(occupied: pgs[p].occupied + 1);
      }
    }
    persistAll();
  }

  Payment? get tenantDuePayment =>
      _firstOrNull(payments, (p) => p.tenantId == currentTenantId && p.status == PaymentStatus.due);

  void payRent(String id, String method) {
    final i = payments.indexWhere((p) => p.id == id);
    if (i == -1) return;
    payments[i] = payments[i].copyWith(status: PaymentStatus.paid, paidDate: DateTime.now(), method: method);
    _notify('Rent received', '${inr(payments[i].amount)} received from ${tenantName(payments[i].tenantId)}.', NotificationType.payment);
    persistAll();
  }

  void recordPayment({required String tenantId, required int amount, required String method}) {
    final now = DateTime.now();
    payments.insert(0, Payment(
      id: _id('pay'), tenantId: tenantId, period: DateTime(now.year, now.month),
      amount: amount, status: PaymentStatus.paid,
      dueDate: DateTime(now.year, now.month, 5), paidDate: now, method: method,
    ));
    _notify('Payment recorded', '${inr(amount)} from ${tenantName(tenantId)} marked as received.', NotificationType.payment);
    persistAll();
  }

  void addMaintenanceRequest({required String title, required String roomId, required String category, required Priority priority}) {
    maintenance.insert(0, MaintenanceRequest(
      id: _id('m'), roomId: roomId, title: title, category: category,
      status: MaintenanceStatus.open, priority: priority, createdAt: DateTime.now(),
    ));
    persistAll();
  }

  void setMaintenanceStatus(String id, MaintenanceStatus status, {String? assignee}) {
    final i = maintenance.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final trimmed = assignee?.trim();
    maintenance[i] = maintenance[i].copyWith(status: status, assignee: (trimmed?.isEmpty ?? true) ? null : trimmed);
    _notify('Maintenance updated', '${maintenance[i].title} is now ${status.label.toLowerCase()}.', NotificationType.maintenance);
    persistAll();
  }

  void addVisitor({required String name, required String tenantId, required String purpose}) {
    visitors.insert(0, Visitor(
      id: _id('v'), tenantId: tenantId, name: name, purpose: purpose,
      status: VisitorStatus.awaitingApproval, expectedAt: DateTime.now(),
    ));
    persistAll();
  }

  void setVisitorStatus(String id, VisitorStatus status) {
    final i = visitors.indexWhere((e) => e.id == id);
    if (i == -1) return;
    visitors[i] = visitors[i].copyWith(status: status);
    final visitor = visitors[i];
    final title = switch (status) {
      VisitorStatus.inside => 'Visitor checked in',
      VisitorStatus.checkedOut => 'Visitor checked out',
      VisitorStatus.declined => 'Visitor declined',
      VisitorStatus.awaitingApproval => 'Visitor updated',
    };
    _notify(title, '${visitor.name} · ${visitor.purpose} visit for ${tenantName(visitor.tenantId)}.', NotificationType.visitor);
    persistAll();
  }

  void publishAnnouncement(String title, String body) {
    announcements.insert(0, Announcement(
      id: _id('a'), title: title, body: body,
      author: '$ownerName, ${role.label}', postedAt: DateTime.now(),
    ));
    _notify('New announcement', title, NotificationType.announcement);
    persistAll();
  }

  void addUtilityBill({required String roomId, required int previous, required int current}) {
    utilities.insert(0, UtilityBill(
      id: _id('u'), roomId: roomId, previous: previous, current: current,
      rate: utilityRate, status: BillStatus.generated,
    ));
    persistAll();
  }

  AttendanceRecord? get todayAttendance =>
      _firstOrNull(attendance, (a) => a.tenantId == currentTenantId && isSameDay(a.checkIn, DateTime.now()));

  bool get isCheckedIn => todayAttendance?.isIn ?? false;

  void toggleCheckIn() {
    final record = todayAttendance;
    if (record == null || !record.isIn) {
      attendance.insert(0, AttendanceRecord(id: _id('at'), tenantId: currentTenantId, checkIn: DateTime.now()));
    } else {
      final i = attendance.indexWhere((a) => a.id == record.id);
      attendance[i] = record.copyWith(checkOut: DateTime.now());
    }
    persistAll();
  }

  // ---- Seed data ----

  void _seed() {
    final now = DateTime.now();
    DateTime month(int offset) => DateTime(now.year, now.month + offset);

    pgs = [
      const Pg(id: 'p1', name: 'HSR Layout PG', address: '27th Main, HSR Layout, Bengaluru', beds: 48, occupied: 41, amenities: 'Wi-Fi • Food • Laundry • CCTV', rating: 4.8),
      const Pg(id: 'p2', name: 'Koramangala PG', address: '5th Block, Koramangala, Bengaluru', beds: 36, occupied: 29, amenities: 'Wi-Fi • AC • Gym • Power backup', rating: 4.6),
    ];
    rooms = [
      const Room(id: 'r1', pgId: 'p1', number: '101', floor: 1, beds: 2, occupied: 2, rent: 9500),
      const Room(id: 'r2', pgId: 'p1', number: '102', floor: 1, beds: 3, occupied: 2, rent: 8200),
      const Room(id: 'r3', pgId: 'p1', number: '201', floor: 2, beds: 1, occupied: 1, rent: 14500),
      const Room(id: 'r4', pgId: 'p1', number: '202', floor: 2, beds: 2, occupied: 1, rent: 10000),
      const Room(id: 'r5', pgId: 'p1', number: '301', floor: 3, beds: 3, occupied: 3, rent: 7800),
    ];
    tenants = [
      Tenant(id: 't1', name: 'Aarav Mehta', phone: '98765 43210', roomId: 'r1', bed: 'A', kyc: KycStatus.verified, agreement: AgreementStatus.signed, joinDate: DateTime(month(-5).year, month(-5).month, 12)),
      Tenant(id: 't2', name: 'Diya Sharma', phone: '99887 66110', roomId: 'r1', bed: 'B', kyc: KycStatus.verified, agreement: AgreementStatus.signed, joinDate: DateTime(month(-5).year, month(-5).month, 4)),
      Tenant(id: 't3', name: 'Rohan Nair', phone: '90123 45678', roomId: 'r2', bed: 'A', kyc: KycStatus.pending, agreement: AgreementStatus.awaitingSign, joinDate: now.subtract(const Duration(days: 12))),
      Tenant(id: 't4', name: 'Ishita Rao', phone: '91234 56780', roomId: 'r3', bed: 'A', kyc: KycStatus.verified, agreement: AgreementStatus.signed, joinDate: DateTime(month(-4).year, month(-4).month, 10)),
    ];

    var payId = 0;
    Payment paid(String tenantId, DateTime m, int amount, String method) => Payment(
          id: 'pay${++payId}', tenantId: tenantId, period: m, amount: amount,
          status: PaymentStatus.paid,
          dueDate: DateTime(m.year, m.month, 5), paidDate: DateTime(m.year, m.month, 3), method: method,
        );
    payments = [
      // Current month: one collected, two due, one overdue.
      Payment(id: 'pay${++payId}', tenantId: 't4', period: month(0), amount: 14500, status: PaymentStatus.paid, dueDate: DateTime(now.year, now.month, 5), paidDate: now.subtract(const Duration(days: 1)), method: 'UPI'),
      Payment(id: 'pay${++payId}', tenantId: 't1', period: month(0), amount: 9500, status: PaymentStatus.due, dueDate: now.add(const Duration(days: 2))),
      Payment(id: 'pay${++payId}', tenantId: 't2', period: month(0), amount: 9500, status: PaymentStatus.due, dueDate: now.add(const Duration(days: 2))),
      Payment(id: 'pay${++payId}', tenantId: 't3', period: month(0), amount: 8200, status: PaymentStatus.due, dueDate: now.subtract(const Duration(days: 2))),
      // History powering the revenue chart.
      paid('t1', month(-1), 9500, 'UPI'), paid('t1', month(-2), 9500, 'UPI'),
      paid('t1', month(-3), 9000, 'Bank transfer'), paid('t1', month(-4), 9000, 'UPI'), paid('t1', month(-5), 9000, 'Cash'),
      paid('t2', month(-1), 9500, 'UPI'), paid('t2', month(-2), 9500, 'Card'),
      paid('t2', month(-3), 9500, 'UPI'), paid('t2', month(-4), 9500, 'UPI'), paid('t2', month(-5), 9500, 'Bank transfer'),
      paid('t4', month(-1), 14500, 'UPI'), paid('t4', month(-2), 14500, 'UPI'),
      paid('t4', month(-3), 13500, 'Bank transfer'), paid('t4', month(-4), 13500, 'UPI'),
      paid('t3', month(-1), 2500, 'UPI'), // prorated first month
    ];
    maintenance = [
      MaintenanceRequest(id: 'm1', roomId: 'r2', title: 'Bathroom tap leaking', category: 'Plumbing', status: MaintenanceStatus.inProgress, priority: Priority.high, assignee: 'Ravi Kumar', createdAt: now.subtract(const Duration(hours: 4))),
      MaintenanceRequest(id: 'm2', roomId: 'r3', title: 'Wi-Fi not connecting', category: 'Internet', status: MaintenanceStatus.open, priority: Priority.medium, createdAt: now.subtract(const Duration(days: 1))),
      MaintenanceRequest(id: 'm3', roomId: 'r5', title: 'Tube light replacement', category: 'Electrical', status: MaintenanceStatus.resolved, priority: Priority.low, assignee: 'Suresh', createdAt: now.subtract(const Duration(days: 3))),
    ];
    visitors = [
      Visitor(id: 'v1', tenantId: 't1', name: 'Karan Mehta', purpose: 'Family', status: VisitorStatus.inside, expectedAt: now.subtract(const Duration(hours: 1))),
      Visitor(id: 'v2', tenantId: 't2', name: 'Maya Singh', purpose: 'Friend', status: VisitorStatus.awaitingApproval, expectedAt: now.subtract(const Duration(hours: 2))),
      Visitor(id: 'v3', tenantId: 't3', name: 'Delivery partner', purpose: 'Delivery', status: VisitorStatus.checkedOut, expectedAt: now.subtract(const Duration(hours: 5))),
    ];
    announcements = [
      Announcement(id: 'a1', title: 'Water tank cleaning', body: 'Water supply will be paused from 10 AM to 12 PM this Sunday.', author: 'Management', postedAt: now.subtract(const Duration(hours: 2))),
      Announcement(id: 'a2', title: 'Community dinner', body: 'Join us on the terrace this Saturday at 7:30 PM.', author: '$ownerName, Owner', postedAt: now.subtract(const Duration(days: 2))),
    ];
    attendance = [
      AttendanceRecord(id: 'at1', tenantId: 't1', checkIn: now.subtract(const Duration(hours: 3))),
      AttendanceRecord(id: 'at2', tenantId: 't2', checkIn: now.subtract(const Duration(hours: 6)), checkOut: now.subtract(const Duration(minutes: 30))),
      AttendanceRecord(id: 'at3', tenantId: 't3', checkIn: now.subtract(const Duration(hours: 2))),
    ];
    utilities = [
      const UtilityBill(id: 'u1', roomId: 'r1', previous: 1280, current: 1384, rate: utilityRate, status: BillStatus.generated),
      const UtilityBill(id: 'u2', roomId: 'r2', previous: 988, current: 1108, rate: utilityRate, status: BillStatus.generated),
      const UtilityBill(id: 'u3', roomId: 'r3', previous: 740, current: 807, rate: utilityRate, status: BillStatus.pendingReading),
    ];
    notifications = [
      AppNotification(id: 'n1', title: 'Rent received', body: '₹14,500 received from Ishita Rao.', type: NotificationType.payment, createdAt: now.subtract(const Duration(minutes: 12))),
      AppNotification(id: 'n2', title: 'Visitor awaiting approval', body: 'Maya Singh is waiting at the reception.', type: NotificationType.visitor, createdAt: now.subtract(const Duration(hours: 1))),
      AppNotification(id: 'n3', title: 'Maintenance updated', body: 'Bathroom tap issue is now in progress.', type: NotificationType.maintenance, createdAt: now.subtract(const Duration(hours: 3)), read: true),
    ];
  }
}

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, PostgrestException, User, UserAttributes;

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

  static const schemaVersion = 3;
  static const utilityRate = 8; // ₹ per unit

  /// Demo/unlinked accounts act as this seeded tenant; a linked tenant
  /// account gets the id from its membership instead.
  static const defaultTenantId = 't1';
  static const ownerName = 'Ananya Kapoor';

  String currentTenantId = defaultTenantId;

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
  String? _workspaceOwnerId;

  /// True right after signing in with a temporary password: the app blocks
  /// on the set-password screen until a permanent one is chosen.
  bool mustChangePassword = false;

  String? _activePgId;

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

  void _useSupabaseRepos(String workspaceOwnerId) {
    final client = supabaseOrNull!;
    _pgRepo = SupabaseRepository<Pg>(client, 'pgs', workspaceOwnerId: workspaceOwnerId, fromMap: Pg.fromMap, toMap: (e) => e.toMap());
    _roomRepo = SupabaseRepository<Room>(client, 'rooms', workspaceOwnerId: workspaceOwnerId, fromMap: Room.fromMap, toMap: (e) => e.toMap());
    _tenantRepo = SupabaseRepository<Tenant>(client, 'tenants', workspaceOwnerId: workspaceOwnerId, fromMap: Tenant.fromMap, toMap: (e) => e.toMap());
    _paymentRepo = SupabaseRepository<Payment>(client, 'payments', workspaceOwnerId: workspaceOwnerId, fromMap: Payment.fromMap, toMap: (e) => e.toMap());
    _maintenanceRepo = SupabaseRepository<MaintenanceRequest>(client, 'maintenance', workspaceOwnerId: workspaceOwnerId, fromMap: MaintenanceRequest.fromMap, toMap: (e) => e.toMap());
    _visitorRepo = SupabaseRepository<Visitor>(client, 'visitors', workspaceOwnerId: workspaceOwnerId, fromMap: Visitor.fromMap, toMap: (e) => e.toMap());
    _announcementRepo = SupabaseRepository<Announcement>(client, 'announcements', workspaceOwnerId: workspaceOwnerId, fromMap: Announcement.fromMap, toMap: (e) => e.toMap());
    _attendanceRepo = SupabaseRepository<AttendanceRecord>(client, 'attendance', workspaceOwnerId: workspaceOwnerId, fromMap: AttendanceRecord.fromMap, toMap: (e) => e.toMap());
    _utilityRepo = SupabaseRepository<UtilityBill>(client, 'utilities', workspaceOwnerId: workspaceOwnerId, fromMap: UtilityBill.fromMap, toMap: (e) => e.toMap());
    _notificationRepo = SupabaseRepository<AppNotification>(client, 'notifications', workspaceOwnerId: workspaceOwnerId, fromMap: AppNotification.fromMap, toMap: (e) => e.toMap());
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
    _activePgId = box.get('activePgId') as String?;
    await _loadAll();
    if (pgs.isEmpty) {
      _seed();
      await persistAll();
    }
    if (role != UserRole.tenant && generateMonthlyDues()) {
      await _persist({'payments'});
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

  Future<void> persistAll() => _persist({
        'pgs', 'rooms', 'tenants', 'payments', 'maintenance',
        'visitors', 'announcements', 'attendance', 'utilities', 'notifications',
      });

  /// Saves only the collections that changed — with photos stored inline and
  /// the cloud backend uploading whole collections, saving everything on
  /// every action would get expensive.
  Future<void> _persist(Set<String> keys) async {
    await Future.wait([
      if (keys.contains('pgs')) _pgRepo.saveAll(pgs),
      if (keys.contains('rooms')) _roomRepo.saveAll(rooms),
      if (keys.contains('tenants')) _tenantRepo.saveAll(tenants),
      if (keys.contains('payments')) _paymentRepo.saveAll(payments),
      if (keys.contains('maintenance')) _maintenanceRepo.saveAll(maintenance),
      if (keys.contains('visitors')) _visitorRepo.saveAll(visitors),
      if (keys.contains('announcements')) _announcementRepo.saveAll(announcements),
      if (keys.contains('attendance')) _attendanceRepo.saveAll(attendance),
      if (keys.contains('utilities')) _utilityRepo.saveAll(utilities),
      if (keys.contains('notifications')) _notificationRepo.saveAll(notifications),
    ]);
    notifyListeners();
  }

  /// Pull-to-refresh: re-read from the backing store (picks up changes made
  /// on other devices in cloud mode). Keeps current data if offline.
  Future<void> refresh() async {
    try {
      await _loadAll();
    } catch (_) {}
    notifyListeners();
  }

  // ---- Session ----

  /// Local demo session: no account, data stays in the on-device Hive box.
  void login(UserRole selectedRole) {
    role = selectedRole;
    isLoggedIn = true;
    box.put('sessionRole', role.name);
    if (role != UserRole.tenant && generateMonthlyDues()) {
      _persist({'payments'}); // also notifies
    } else {
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (cloudMode) {
      try {
        await supabaseOrNull?.auth.signOut();
      } catch (_) {} // Signing out while offline still logs out locally.
      cloudMode = false;
      accountEmail = null;
      _cloudName = null;
      _workspaceOwnerId = null;
      mustChangePassword = false;
      currentTenantId = defaultTenantId;
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
    } on PostgrestException catch (e) {
      return 'Signed in, but the database rejected the request: ${e.message}. '
          'If this mentions app_data, run supabase/schema.sql in the Supabase SQL Editor.';
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
    } on PostgrestException catch (e) {
      return 'Signed in, but the database rejected the request: ${e.message}. '
          'If this mentions app_data, run supabase/schema.sql in the Supabase SQL Editor.';
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }

  /// Emails a password-reset link. Returns an error message, or null.
  Future<String?> sendPasswordReset(String email) async {
    final client = supabaseOrNull;
    if (client == null) return 'Password reset needs an internet connection.';
    try {
      await client.auth.resetPasswordForEmail(email);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not send the reset email. Check your connection.';
    }
  }

  /// Changes the signed-in account's password and clears the temporary-
  /// password flag. Returns an error, or null.
  Future<String?> changePassword(String password) async {
    final client = supabaseOrNull;
    if (client == null || !cloudMode) return 'Sign in with an account to change your password.';
    try {
      await client.auth.updateUser(UserAttributes(password: password, data: {'must_change_password': false}));
      mustChangePassword = false;
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not update the password. Check your connection.';
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
    final client = supabaseOrNull!;

    // A membership row means an owner invited this email: attach to that
    // owner's workspace as the linked tenant instead of a private workspace.
    String workspaceOwnerId = user.id;
    String? linkedTenantId;
    try {
      final membership = await client
          .from('members')
          .select('owner_id, tenant_id')
          .eq('member_email', (user.email ?? '').toLowerCase())
          .limit(1)
          .maybeSingle();
      if (membership != null) {
        workspaceOwnerId = membership['owner_id'] as String;
        linkedTenantId = membership['tenant_id'] as String;
      }
    } catch (_) {
      // members table missing or unreachable: fall back to a private workspace.
    }

    if (linkedTenantId != null) {
      role = UserRole.tenant;
      currentTenantId = linkedTenantId;
    } else {
      final metaRole = user.userMetadata?['role'] as String?;
      role = UserRole.values.firstWhere((e) => e.name == metaRole, orElse: () => UserRole.owner);
      currentTenantId = defaultTenantId;
    }
    _cloudName = user.userMetadata?['full_name'] as String?;
    accountEmail = user.email;
    mustChangePassword = user.userMetadata?['must_change_password'] == true;
    cloudMode = true;
    _workspaceOwnerId = workspaceOwnerId;
    _useSupabaseRepos(workspaceOwnerId);
    await _loadAll();
    // Seed only a brand-new private workspace — never an owner's shared one.
    if (pgs.isEmpty && workspaceOwnerId == user.id) {
      _seed();
      await persistAll();
    }
    if (role != UserRole.tenant && generateMonthlyDues()) {
      await _persist({'payments'});
    }
    isLoggedIn = true;
    notifyListeners();
  }

  /// Creates the tenant's login (temporary password, forced change on first
  /// sign-in) and links it to this workspace, via the `invite` Edge Function.
  /// Falls back to link-only membership when the function isn't deployed.
  /// [tempPassword] is null when the email already had an account.
  Future<({String? error, String? tempPassword})> inviteTenant({required String tenantId, required String email}) async {
    final client = supabaseOrNull;
    if (client == null || !cloudMode) {
      return (error: 'Sign in with a cloud account to invite tenants.', tempPassword: null);
    }
    final address = email.trim().toLowerCase();
    final tenant = tenantById(tenantId);
    try {
      final result = await client.functions.invoke('invite', body: {
        'email': address,
        'tenantId': tenantId,
        'tenantName': tenant?.name ?? '',
      });
      final data = result.data as Map?;
      return (error: null, tempPassword: data?['tempPassword'] as String?);
    } catch (_) {
      // Function not deployed or unreachable: save a link-only invite so the
      // tenant can still self-register with this email.
      try {
        await client.from('members').upsert({
          'owner_id': client.auth.currentUser!.id,
          'member_email': address,
          'tenant_id': tenantId,
        }, onConflict: 'owner_id,member_email');
        return (error: null, tempPassword: null);
      } on PostgrestException catch (e) {
        return (error: 'Could not save the invite: ${e.message}', tempPassword: null);
      } catch (_) {
        return (error: 'Could not reach the server. Check your connection.', tempPassword: null);
      }
    }
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

  // ---- Active property (multi-PG owners work one property at a time) ----

  Pg? get activePg {
    if (pgs.isEmpty) return null;
    return pgById(_activePgId ?? '') ?? pgs.first;
  }

  void selectPg(String id) {
    _activePgId = id;
    box.put('activePgId', id);
    notifyListeners();
  }

  List<Room> get pgRooms {
    final pg = activePg;
    return pg == null ? rooms : rooms.where((r) => r.pgId == pg.id).toList();
  }

  Set<String> get _pgRoomIds => pgRooms.map((r) => r.id).toSet();

  List<Tenant> get pgTenants {
    final ids = _pgRoomIds;
    return tenants.where((t) => ids.contains(t.roomId)).toList();
  }

  Set<String> get _pgTenantIds => pgTenants.map((t) => t.id).toSet();

  List<Payment> get pgPayments {
    final ids = _pgTenantIds;
    return payments.where((p) => ids.contains(p.tenantId)).toList();
  }

  List<MaintenanceRequest> get pgMaintenance {
    final ids = _pgRoomIds;
    return maintenance.where((m) => ids.contains(m.roomId)).toList();
  }

  List<UtilityBill> get pgUtilities {
    final ids = _pgRoomIds;
    return utilities.where((u) => ids.contains(u.roomId)).toList();
  }

  List<Visitor> get pgVisitors {
    final ids = _pgTenantIds;
    return visitors.where((v) => ids.contains(v.tenantId)).toList();
  }

  List<AttendanceRecord> get pgAttendance {
    final ids = _pgTenantIds;
    return attendance.where((a) => ids.contains(a.tenantId)).toList();
  }

  int get pgDueAmount => pgPayments.where((e) => e.status == PaymentStatus.due).fold(0, (sum, e) => sum + e.amount);

  int get pgCollectedAmount {
    final now = DateTime.now();
    return pgPayments
        .where((e) => e.status == PaymentStatus.paid && e.period.year == now.year && e.period.month == now.month)
        .fold(0, (sum, e) => sum + e.amount);
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

  List<({DateTime month, int total})> monthlyRevenue({int months = 6, List<Payment>? source}) {
    final now = DateTime.now();
    final pool = source ?? payments;
    return List.generate(months, (i) {
      final month = DateTime(now.year, now.month - (months - 1 - i));
      final total = pool
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

  void _notify(String title, String body, NotificationType type, {
    NotificationScope scope = NotificationScope.managers,
    String? tenantId,
    String? pgId,
    String? relatedEntityId,
  }) {
    notifications.insert(0, AppNotification(
      id: _id('n'), title: title, body: body, type: type, createdAt: DateTime.now(),
      roleScope: scope, tenantId: tenantId, pgId: pgId, relatedEntityId: relatedEntityId,
    ));
    _pushToWorkspace(title, body, scope: scope, tenantId: tenantId);
  }

  /// Fire-and-forget push via the `push` Edge Function. Scope and tenant are
  /// passed so the function can target the right devices; push failures never
  /// block the action itself.
  void _pushToWorkspace(String title, String body, {required NotificationScope scope, String? tenantId}) {
    final client = supabaseOrNull;
    final owner = _workspaceOwnerId;
    if (client == null || !cloudMode || owner == null) return;
    client.functions.invoke('push', body: {
      'workspaceOwnerId': owner,
      'title': title,
      'body': body,
      'scope': scope.name,
      if (tenantId != null) 'tenantId': tenantId,
    }).ignore();
  }

  // Which property a tenant/room belongs to — used to scope notifications.
  String? _pgIdForTenant(String tenantId) => roomById(tenantById(tenantId)?.roomId ?? '')?.pgId;
  String? _pgIdForRoom(String roomId) => roomById(roomId)?.pgId;
  List<Tenant> _tenantsInRoom(String roomId) => tenants.where((t) => t.roomId == roomId).toList();

  /// Notifications the current session is allowed to see. Tenants get only
  /// their own personal notifications plus workspace-wide announcements;
  /// owners/admins get managerial and workspace notifications scoped to the
  /// property they are currently managing.
  List<AppNotification> get visibleNotifications {
    if (role == UserRole.tenant) {
      final id = currentTenantId;
      return notifications.where((n) =>
          n.roleScope == NotificationScope.everyone ||
          (n.roleScope == NotificationScope.tenant && n.tenantId == id)).toList();
    }
    final pgId = activePg?.id;
    return notifications.where((n) {
      if (n.roleScope == NotificationScope.tenant) return false; // personal to a tenant
      if (n.pgId != null && pgId != null && n.pgId != pgId) return false; // another property
      return true;
    }).toList();
  }

  bool get hasUnread => visibleNotifications.any((n) => !n.read);

  void markNotificationRead(String id) {
    final i = notifications.indexWhere((n) => n.id == id);
    if (i == -1) return;
    notifications[i] = notifications[i].copyWith(read: true);
    _persist({'notifications'});
  }

  void markAllNotificationsRead() {
    // Only clear the ones this session can actually see.
    final visibleIds = visibleNotifications.map((n) => n.id).toSet();
    notifications = notifications.map((n) => visibleIds.contains(n.id) ? n.copyWith(read: true) : n).toList();
    _persist({'notifications'});
  }

  void savePg(Pg pg) {
    final i = pgs.indexWhere((e) => e.id == pg.id);
    if (i == -1) {
      pgs.insert(0, pg);
    } else {
      pgs[i] = pg;
    }
    _persist({'pgs'});
  }

  void addRoom(Room room) {
    rooms.add(room);
    _persist({'rooms'});
  }

  void onboardTenant({required String name, required String phone, required String roomId, required String bed, String? kycDoc}) {
    tenants.insert(0, Tenant(
      id: _id('t'), name: name, phone: phone, roomId: roomId, bed: bed,
      kyc: KycStatus.pending, agreement: AgreementStatus.awaitingSign, joinDate: DateTime.now(),
      kycDoc: kycDoc,
    ));
    final i = rooms.indexWhere((r) => r.id == roomId);
    if (i != -1 && rooms[i].occupied < rooms[i].beds) {
      rooms[i] = rooms[i].copyWith(occupied: rooms[i].occupied + 1);
      final p = pgs.indexWhere((e) => e.id == rooms[i].pgId);
      if (p != -1 && pgs[p].occupied < pgs[p].beds) {
        pgs[p] = pgs[p].copyWith(occupied: pgs[p].occupied + 1);
      }
    }
    // The new tenant's first due appears immediately in rent collection.
    generateMonthlyDues();
    _persist({'tenants', 'rooms', 'pgs', 'payments'});
  }

  Payment? get tenantDuePayment =>
      _firstOrNull(payments, (p) => p.tenantId == currentTenantId && p.status == PaymentStatus.due);

  /// The signed-in tenant's own payments — never anyone else's.
  List<Payment> get tenantPayments =>
      payments.where((p) => p.tenantId == currentTenantId).toList();

  /// Rent collection as spreadsheet-ready CSV (newest first, like the UI).
  String paymentsCsv() {
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
    final rows = <String>['Receipt,Tenant,Month,Amount,Status,Due date,Paid date,Method'];
    for (final p in payments) {
      rows.add([
        p.id,
        tenantName(p.tenantId),
        formatMonth(p.period),
        '${p.amount}',
        p.displayStatus,
        formatFullDate(p.dueDate),
        p.paidDate == null ? '' : formatFullDate(p.paidDate!),
        p.method ?? '',
      ].map(cell).join(','));
    }
    return rows.join('\n');
  }

  /// Creates this month's Due payment for every tenant who doesn't have one
  /// (new tenants join at their room's full rent — no proration yet).
  /// Deterministic ids make it idempotent. Returns true if anything was added.
  bool generateMonthlyDues() {
    final now = DateTime.now();
    final period = DateTime(now.year, now.month);
    final fifth = DateTime(now.year, now.month, 5);
    final dueDate = now.isBefore(fifth) ? fifth : now.add(const Duration(days: 3));
    var added = false;
    for (final tenant in tenants) {
      final exists = payments.any((p) =>
          p.tenantId == tenant.id && p.period.year == period.year && p.period.month == period.month);
      if (exists) continue;
      final rent = roomById(tenant.roomId)?.rent ?? 0;
      if (rent <= 0) continue;
      payments.insert(0, Payment(
        id: 'pay-${period.year}-${period.month}-${tenant.id}',
        tenantId: tenant.id, period: period, amount: rent,
        status: PaymentStatus.due, dueDate: dueDate,
      ));
      added = true;
    }
    return added;
  }

  void payRent(String id, String method) {
    final i = payments.indexWhere((p) => p.id == id);
    if (i == -1) return;
    final paid = payments[i] = payments[i].copyWith(status: PaymentStatus.paid, paidDate: DateTime.now(), method: method);
    final pgId = _pgIdForTenant(paid.tenantId);
    // Managers see the income; the paying tenant gets a private confirmation.
    _notify('Rent received', '${inr(paid.amount)} received from ${tenantName(paid.tenantId)}.', NotificationType.payment,
        scope: NotificationScope.managers, pgId: pgId, tenantId: paid.tenantId, relatedEntityId: paid.id);
    _notify('Payment successful', 'Your ${formatMonthName(paid.period)} rent of ${inr(paid.amount)} is paid.', NotificationType.payment,
        scope: NotificationScope.tenant, tenantId: paid.tenantId, pgId: pgId, relatedEntityId: paid.id);
    _persist({'payments', 'notifications'});
  }

  void recordPayment({required String tenantId, required int amount, required String method}) {
    final now = DateTime.now();
    final payment = Payment(
      id: _id('pay'), tenantId: tenantId, period: DateTime(now.year, now.month),
      amount: amount, status: PaymentStatus.paid,
      dueDate: DateTime(now.year, now.month, 5), paidDate: now, method: method,
    );
    payments.insert(0, payment);
    final pgId = _pgIdForTenant(tenantId);
    _notify('Payment recorded', '${inr(amount)} from ${tenantName(tenantId)} marked as received.', NotificationType.payment,
        scope: NotificationScope.managers, pgId: pgId, tenantId: tenantId, relatedEntityId: payment.id);
    _notify('Rent received', 'Your ${formatMonthName(payment.period)} rent of ${inr(amount)} was recorded.', NotificationType.payment,
        scope: NotificationScope.tenant, tenantId: tenantId, pgId: pgId, relatedEntityId: payment.id);
    _persist({'payments', 'notifications'});
  }

  void addMaintenanceRequest({required String title, required String roomId, required String category, required Priority priority, String? photo}) {
    final request = MaintenanceRequest(
      id: _id('m'), roomId: roomId, title: title, category: category,
      status: MaintenanceStatus.open, priority: priority, createdAt: DateTime.now(),
      photo: photo,
    );
    maintenance.insert(0, request);
    // Managers are alerted to the new request; it also appears in the raising
    // tenant's own "My requests" list.
    _notify('New maintenance request', '$title · Room ${roomNumber(roomId)}', NotificationType.maintenance,
        scope: NotificationScope.managers, pgId: _pgIdForRoom(roomId), relatedEntityId: request.id);
    _persist({'maintenance', 'notifications'});
  }

  void setMaintenanceStatus(String id, MaintenanceStatus status, {String? assignee}) {
    final i = maintenance.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final trimmed = assignee?.trim();
    final request = maintenance[i] = maintenance[i].copyWith(status: status, assignee: (trimmed?.isEmpty ?? true) ? null : trimmed);
    final pgId = _pgIdForRoom(request.roomId);
    // Notify each tenant living in that room — and only them.
    for (final tenant in _tenantsInRoom(request.roomId)) {
      _notify('Maintenance updated', '${request.title} is now ${status.label.toLowerCase()}.', NotificationType.maintenance,
          scope: NotificationScope.tenant, tenantId: tenant.id, pgId: pgId, relatedEntityId: request.id);
    }
    _persist({'maintenance', 'notifications'});
  }

  void addVisitor({required String name, required String tenantId, required String purpose}) {
    final visitor = Visitor(
      id: _id('v'), tenantId: tenantId, name: name, purpose: purpose,
      status: VisitorStatus.awaitingApproval, expectedAt: DateTime.now(),
    );
    visitors.insert(0, visitor);
    // Managers are alerted to approve; the visit is private to this tenant.
    _notify('Visitor awaiting approval', '$name · $purpose visit for ${tenantName(tenantId)}.', NotificationType.visitor,
        scope: NotificationScope.managers, pgId: _pgIdForTenant(tenantId), tenantId: tenantId, relatedEntityId: visitor.id);
    _persist({'visitors', 'notifications'});
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
    // Only the host tenant is told about their own visitor.
    _notify(title, '${visitor.name} · ${visitor.purpose} visit.', NotificationType.visitor,
        scope: NotificationScope.tenant, tenantId: visitor.tenantId, pgId: _pgIdForTenant(visitor.tenantId), relatedEntityId: visitor.id);
    _persist({'visitors', 'notifications'});
  }

  void publishAnnouncement(String title, String body) {
    final announcement = Announcement(
      id: _id('a'), title: title, body: body,
      author: '$ownerName, ${role.label}', postedAt: DateTime.now(),
    );
    announcements.insert(0, announcement);
    // Announcements are for the whole workspace.
    _notify('New announcement', title, NotificationType.announcement,
        scope: NotificationScope.everyone, relatedEntityId: announcement.id);
    _persist({'announcements', 'notifications'});
  }

  void addUtilityBill({required String roomId, required int previous, required int current}) {
    final bill = UtilityBill(
      id: _id('u'), roomId: roomId, previous: previous, current: current,
      rate: utilityRate, status: BillStatus.generated,
    );
    utilities.insert(0, bill);
    // Each occupant of the room is told their bill is ready — no one else.
    for (final tenant in _tenantsInRoom(roomId)) {
      _notify('Electricity bill ready', 'Room ${roomNumber(roomId)} · your share is due with rent.', NotificationType.payment,
          scope: NotificationScope.tenant, tenantId: tenant.id, pgId: _pgIdForRoom(roomId), relatedEntityId: bill.id);
    }
    _persist({'utilities', 'notifications'});
  }

  AttendanceRecord? get todayAttendance =>
      _firstOrNull(attendance, (a) => a.tenantId == currentTenantId && isSameDay(a.checkIn, DateTime.now()));

  bool get isCheckedIn => todayAttendance?.isIn ?? false;

  void toggleCheckIn() {
    final record = todayAttendance;
    final checkingIn = record == null || !record.isIn;
    if (checkingIn) {
      attendance.insert(0, AttendanceRecord(id: _id('at'), tenantId: currentTenantId, checkIn: DateTime.now()));
    } else {
      final i = attendance.indexWhere((a) => a.id == record.id);
      attendance[i] = record.copyWith(checkOut: DateTime.now());
    }
    // Managers keep an attendance log; tenants act, they don't need telling.
    _notify('Attendance', '${tenantName(currentTenantId)} checked ${checkingIn ? 'in' : 'out'}.', NotificationType.attendance,
        scope: NotificationScope.managers, pgId: _pgIdForTenant(currentTenantId), tenantId: currentTenantId);
    _persist({'attendance', 'notifications'});
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
      // Manager-facing (owner/admin of HSR Layout PG only).
      AppNotification(id: 'n1', title: 'Rent received', body: '₹14,500 received from Ishita Rao.', type: NotificationType.payment, createdAt: now.subtract(const Duration(minutes: 12)), roleScope: NotificationScope.managers, pgId: 'p1', tenantId: 't4', relatedEntityId: 'pay1'),
      AppNotification(id: 'n2', title: 'Visitor awaiting approval', body: 'Maya Singh is waiting at the reception.', type: NotificationType.visitor, createdAt: now.subtract(const Duration(hours: 1)), roleScope: NotificationScope.managers, pgId: 'p1', tenantId: 't2', relatedEntityId: 'v2'),
      // Workspace-wide announcement (everyone).
      AppNotification(id: 'n3', title: 'Water tank cleaning', body: 'Water supply paused 10 AM–12 PM this Sunday.', type: NotificationType.announcement, createdAt: now.subtract(const Duration(hours: 3)), roleScope: NotificationScope.everyone, relatedEntityId: 'a1'),
      // Personal to the demo tenant (t1) — only they see it.
      AppNotification(id: 'n4', title: 'Rent reminder', body: 'Your rent of ₹9,500 is due soon.', type: NotificationType.payment, createdAt: now.subtract(const Duration(hours: 5)), roleScope: NotificationScope.tenant, tenantId: 't1', pgId: 'p1'),
    ];
  }
}

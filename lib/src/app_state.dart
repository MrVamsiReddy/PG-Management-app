import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthException,
        FileOptions,
        FunctionException,
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        PostgrestException,
        RealtimeChannel,
        SupabaseClient,
        User,
        UserAttributes;

import 'access.dart';
import 'format.dart';
import 'l10n.dart';
import 'models.dart';
import 'push.dart';
import 'repositories.dart';
import 'saas_models.dart';
import 'supabase_config.dart';

export 'access.dart' show LoginPortal, adminSetupMessage;
export 'l10n.dart' show AppLanguage;
export 'models.dart';
export 'saas_models.dart';

enum UserRole { owner, tenant, admin }

/// Result of an invite action. [tempPassword] is only ever non-null right
/// after it was (re)generated — passwords are never redisplayed later.
/// [emailSent] reports whether the server delivered the invite email.
typedef InviteResult = ({
  String? error,
  String? tempPassword,
  String? token,
  DateTime? expiresAt,
  String? email,
  bool emailSent
});

InviteResult _inviteFailure(String error) => (
      error: error,
      tempPassword: null,
      token: null,
      expiresAt: null,
      email: null,
      emailSent: false
    );

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
  AppState();

  static const utilityRate = 8; // ₹ per unit

  String currentTenantId = '';

  Repository<Pg>? _pgRepo;
  Repository<Room>? _roomRepo;
  Repository<Tenant>? _tenantRepo;
  Repository<Payment>? _paymentRepo;
  Repository<MaintenanceRequest>? _maintenanceRepo;
  Repository<Visitor>? _visitorRepo;
  Repository<Announcement>? _announcementRepo;
  Repository<AttendanceRecord>? _attendanceRepo;
  Repository<UtilityBill>? _utilityRepo;
  Repository<AppNotification>? _notificationRepo;

  bool isLoggedIn = false;
  UserRole role = UserRole.owner;

  /// Lets the state show a snackbar (e.g. a failed save) without a context.
  /// Each app passes it to its MaterialApp.
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Saves still on their way to the server.
  final Set<Future<void>> _inFlightSaves = {};

  /// Completes once every save started so far has finished.
  Future<void> flushSaves() => Future.wait(_inFlightSaves.toList());

  String? accountEmail;
  String? _cloudName;
  String? _workspaceOwnerId;
  String? _resolvedCustomerId;

  /// A message to show on the login screen after a blocked/rejected sign-in
  /// (disabled customer, wrong portal, session revoked). Cleared on success.
  String? authNotice;

  /// True right after signing in with a temporary password: the app blocks
  /// on the set-password screen until a permanent one is chosen.
  bool mustChangePassword = false;

  /// True after a `passwordRecovery` auth event (the user followed a reset
  /// link): the app blocks on the set-password screen until a new password is
  /// set. Unlike [mustChangePassword] this flow needs no temporary password.
  bool passwordRecovery = false;

  /// The app must block on the set-password screen until the account has a
  /// permanent password — for both first-login and reset-link flows.
  bool get needsPasswordSet => mustChangePassword || passwordRecovery;

  /// Called from the auth listener when a reset link is opened.
  void markPasswordRecovery() {
    passwordRecovery = true;
    notifyListeners();
  }

  String? _activePgId;

  AppLanguage language = AppLanguage.english;
  bool pushEnabled = true;

  Locale get locale => language.locale;

  void _useSupabaseRepos(String workspaceOwnerId) {
    final client = supabaseOrNull!;
    // Tenants never touch app_data directly: they get a server-filtered view
    // of the workspace and server-merged writes (014_tenant_isolation.sql).
    final tenant = role == UserRole.tenant;
    Repository<T> repo<T>(String key,
            {required T Function(Map<String, dynamic>) fromMap,
            required Map<String, dynamic> Function(T) toMap}) =>
        tenant
            ? TenantRepository<T>(client, key,
                workspaceOwnerId: workspaceOwnerId,
                fromMap: fromMap,
                toMap: toMap)
            : SupabaseRepository<T>(client, key,
                workspaceOwnerId: workspaceOwnerId,
                fromMap: fromMap,
                toMap: toMap);
    _pgRepo = repo<Pg>('pgs', fromMap: Pg.fromMap, toMap: (e) => e.toMap());
    _roomRepo =
        repo<Room>('rooms', fromMap: Room.fromMap, toMap: (e) => e.toMap());
    _tenantRepo = repo<Tenant>('tenants',
        fromMap: Tenant.fromMap, toMap: (e) => e.toMap());
    _paymentRepo = repo<Payment>('payments',
        fromMap: Payment.fromMap, toMap: (e) => e.toMap());
    _maintenanceRepo = repo<MaintenanceRequest>('maintenance',
        fromMap: MaintenanceRequest.fromMap, toMap: (e) => e.toMap());
    _visitorRepo = repo<Visitor>('visitors',
        fromMap: Visitor.fromMap, toMap: (e) => e.toMap());
    _announcementRepo = repo<Announcement>('announcements',
        fromMap: Announcement.fromMap, toMap: (e) => e.toMap());
    _attendanceRepo = repo<AttendanceRecord>('attendance',
        fromMap: AttendanceRecord.fromMap, toMap: (e) => e.toMap());
    _utilityRepo = repo<UtilityBill>('utilities',
        fromMap: UtilityBill.fromMap, toMap: (e) => e.toMap());
    _notificationRepo = repo<AppNotification>('notifications',
        fromMap: AppNotification.fromMap, toMap: (e) => e.toMap());
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

  Future<void> _loadAll() async {
    // Tenants get their whole filtered view in one call
    // (016_review_fixes.sql); a database without it falls back to one call
    // per collection.
    Map<String, dynamic>? tenantView;
    final client = supabaseOrNull;
    final owner = _workspaceOwnerId;
    if (role == UserRole.tenant && client != null && owner != null) {
      try {
        final data =
            await client.rpc('tenant_workspace', params: {'p_owner': owner});
        if (data is Map) tenantView = Map<String, dynamic>.from(data);
      } catch (_) {}
    }
    final view = tenantView;
    Future<List<T>> load<T>(String key, Repository<T>? repo) async {
      if (repo == null) return <T>[];
      if (view != null && repo is TenantRepository<T>) {
        return repo.parse(view[key] as List? ?? const []);
      }
      return repo.loadAll();
    }

    // Collections load side by side, not one after another.
    await Future.wait<void>([
      load('pgs', _pgRepo).then((v) {
        pgs = v;
      }),
      load('rooms', _roomRepo).then((v) {
        rooms = v;
      }),
      load('tenants', _tenantRepo).then((v) {
        tenants = v;
      }),
      load('payments', _paymentRepo).then((v) {
        payments = v;
      }),
      load('maintenance', _maintenanceRepo).then((v) {
        maintenance = v;
      }),
      load('visitors', _visitorRepo).then((v) {
        visitors = v;
      }),
      load('announcements', _announcementRepo).then((v) {
        announcements = v;
      }),
      load('attendance', _attendanceRepo).then((v) {
        attendance = v;
      }),
      load('utilities', _utilityRepo).then((v) {
        utilities = v;
      }),
      load('notifications', _notificationRepo).then((v) {
        notifications = v;
      }),
    ]);
    if (role != UserRole.tenant) _deriveOccupancy();
  }

  /// Recomputes the stored bed counters from the tenant list. Two devices
  /// onboarding or removing tenants at once can leave the counters wrong
  /// (each save keeps the last copy of a room); the tenant list is the
  /// truth. A corrected room or PG is written back with its next save.
  void _deriveOccupancy() {
    final perRoom = <String, int>{};
    for (final t in tenants) {
      perRoom[t.roomId] = (perRoom[t.roomId] ?? 0) + 1;
    }
    for (var i = 0; i < rooms.length; i++) {
      final count = perRoom[rooms[i].id] ?? 0;
      if (rooms[i].occupied != count) {
        rooms[i] = rooms[i].copyWith(occupied: count);
      }
    }
    for (var i = 0; i < pgs.length; i++) {
      final pgRooms = rooms.where((r) => r.pgId == pgs[i].id).toList();
      if (pgRooms.isEmpty) continue;
      final beds = pgRooms.fold(0, (sum, r) => sum + r.beds);
      final occupied = pgRooms.fold(0, (sum, r) => sum + r.occupied);
      if (pgs[i].beds != beds || pgs[i].occupied != occupied) {
        pgs[i] = pgs[i].copyWith(beds: beds, occupied: occupied);
      }
    }
  }

  /// Saves only the collections that changed. A failed save is never silent:
  /// the user is told, and the collections are reloaded so the screen shows
  /// what the server actually holds. Completes with false when it failed.
  Future<bool> _persist(Set<String> keys) {
    final run = _persistNow(keys);
    _inFlightSaves.add(run);
    run.whenComplete(() => _inFlightSaves.remove(run));
    return run;
  }

  Future<bool> _persistNow(Set<String> keys) async {
    final saves = <Future<void>>[];
    void save(String key, Repository? repo, List items) {
      if (keys.contains(key) && repo != null) saves.add(repo.saveAll(items));
    }

    save('pgs', _pgRepo, pgs);
    save('rooms', _roomRepo, rooms);
    save('tenants', _tenantRepo, tenants);
    save('payments', _paymentRepo, payments);
    save('maintenance', _maintenanceRepo, maintenance);
    save('visitors', _visitorRepo, visitors);
    save('announcements', _announcementRepo, announcements);
    save('attendance', _attendanceRepo, attendance);
    save('utilities', _utilityRepo, utilities);
    save('notifications', _notificationRepo, notifications);
    var ok = true;
    try {
      await Future.wait(saves);
    } catch (_) {
      ok = false;
      _showSaveFailed();
      try {
        await _loadAll();
      } catch (_) {}
    }
    notifyListeners();
    return ok;
  }

  void _showSaveFailed() {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    final l = AppLocalizations.of(messenger.context);
    messenger.showSnackBar(SnackBar(content: Text(l.t('sync.failed'))));
  }

  Future<void> refresh() async {
    final user = supabaseOrNull?.auth.currentUser;
    if (user != null) {
      final gate = await _fetchAccessGate(user);
      if (gate.error != null && gate.error != 'code:network') {
        await logout();
        authNotice = gate.error;
        notifyListeners();
        return;
      }
    }
    try {
      await _loadAll();
    } catch (_) {}
    // A reload replaces the collections, so a tenant's in-memory due (never
    // persisted owner-wide) must be materialised again or the rent card
    // goes blank after pull-to-refresh.
    if (isLoggedIn) await _ensureMonthlyDuesAtStartup();
    notifyListeners();
  }

  // ---- Session ----

  @visibleForTesting
  void debugSignIn(UserRole selectedRole, {String tenantId = ''}) {
    role = selectedRole;
    currentTenantId = tenantId;
    isLoggedIn = true;
    notifyListeners();
    _ensureMonthlyDuesAtStartup();
  }

  Future<void> logout() async {
    _unsubscribeRealtime();
    // A signed-out device must stop getting this account's notifications
    // (e.g. a shared phone).
    await unregisterPushToken();
    try {
      await supabaseOrNull?.auth.signOut();
    } catch (_) {}
    accountEmail = null;
    _cloudName = null;
    _workspaceOwnerId = null;
    _resolvedCustomerId = null;
    mustChangePassword = false;
    passwordRecovery = false;
    currentTenantId = '';
    _pgRepo = null;
    _roomRepo = null;
    _tenantRepo = null;
    _paymentRepo = null;
    _maintenanceRepo = null;
    _visitorRepo = null;
    _announcementRepo = null;
    _attendanceRepo = null;
    _utilityRepo = null;
    _notificationRepo = null;
    pgs = [];
    rooms = [];
    tenants = [];
    payments = [];
    maintenance = [];
    visitors = [];
    announcements = [];
    attendance = [];
    utilities = [];
    notifications = [];
    submissions = [];
    isLoggedIn = false;
    notifyListeners();
  }

  // ---- Cloud accounts (Supabase) ----

  Future<String?> signInCloud(
      {required String email,
      required String password,
      required LoginPortal portal}) async {
    final client = supabaseOrNull;
    if (client == null) return 'code:network';
    try {
      final result = await client.auth
          .signInWithPassword(email: email, password: password);
      final error = await _enterCloud(result.user!, portal: portal);
      if (error != null) {
        try {
          await client.auth.signOut();
        } catch (_) {}
        return error;
      }
      return null;
    } on AuthException catch (e) {
      return e.message.toLowerCase().contains('invalid login')
          ? 'code:bad_credentials'
          : 'code:generic';
    } catch (_) {
      return 'code:network';
    }
  }

  /// Emails a password-reset link. Returns an error message, or null.
  Future<String?> createAdmin(
      {required String fullName,
      required String email,
      required String password,
      required String setupKey}) async {
    final client = supabaseOrNull;
    if (client == null) {
      return 'Cannot reach the server. Check your connection.';
    }
    try {
      final result = await client.functions.invoke('create-admin', body: {
        'fullName': fullName.trim(),
        'email': email.trim(),
        'password': password,
        'setupKey': setupKey,
      });
      final data = result.data;
      if (data is Map && data['ok'] == true) return null;
      return adminSetupMessage(data is Map ? data['error'] as String? : null);
    } on FunctionException catch (e) {
      final details = e.details;
      return adminSetupMessage(
          details is Map ? details['error'] as String? : null);
    } catch (_) {
      return adminSetupMessage(null);
    }
  }

  Customer _customerFromRow(Map<String, dynamic> r) => Customer(
        id: r['id'] as String,
        businessName: r['business_name'] as String? ?? '',
        ownerName: r['owner_name'] as String? ?? '',
        ownerEmail: r['owner_email'] as String? ?? '',
        phone: r['phone'] as String? ?? '',
        status: CustomerStatus.fromWire(r['status'] as String?),
        plan: r['plan'] as String? ?? 'free',
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
            DateTime.now(),
        disabledAt: r['disabled_at'] == null
            ? null
            : DateTime.tryParse(r['disabled_at'] as String),
        startsAt: r['starts_at'] == null
            ? null
            : DateTime.tryParse(r['starts_at'] as String),
        expiresAt: r['expires_at'] == null
            ? null
            : DateTime.tryParse(r['expires_at'] as String),
      );

  Future<List<Customer>> loadCustomers() async {
    final client = supabaseOrNull;
    if (client == null) return [];
    try {
      final rows = await client
          .from('customers')
          .select()
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => _customerFromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<({String? error, String? tempPassword})> createCustomer(
      {required String businessName,
      required String ownerName,
      required String ownerEmail,
      required String phone,
      String plan = 'free'}) async {
    final client = supabaseOrNull;
    if (client == null) {
      return (
        error: 'Cannot reach the server. Check your connection.',
        tempPassword: null
      );
    }
    try {
      final result = await client.functions.invoke('create-customer', body: {
        'businessName': businessName.trim(),
        'ownerName': ownerName.trim(),
        'ownerEmail': ownerEmail.trim(),
        'phone': phone.trim(),
        'plan': plan,
      });
      final data = result.data;
      if (data is Map && data['ok'] == true) {
        return (error: null, tempPassword: data['tempPassword'] as String?);
      }
      return (
        error: adminSetupMessage(data is Map ? data['error'] as String? : null),
        tempPassword: null
      );
    } on FunctionException catch (e) {
      final details = e.details;
      return (
        error: adminSetupMessage(
            details is Map ? details['error'] as String? : null),
        tempPassword: null
      );
    } catch (_) {
      return (
        error: 'Something went wrong. Please try again.',
        tempPassword: null
      );
    }
  }

  Future<String?> setCustomerStatus(String id, bool enabled) async {
    final client = supabaseOrNull;
    if (client == null) {
      return 'Cannot reach the server. Check your connection.';
    }
    try {
      await client.from('customers').update({
        'status': enabled ? 'enabled' : 'disabled',
        'disabled_at': enabled ? null : DateTime.now().toIso8601String(),
      }).eq('id', id);
      _audit(enabled ? 'customer_enabled' : 'customer_disabled',
          customerId: id, entityType: 'customer', entityId: id);
      return null;
    } catch (_) {
      return 'Could not update the customer.';
    }
  }

  /// Platform-admin only: permanently deletes a customer and everything under
  /// it (owner + tenant accounts, workspace data, relational rows, storage) via
  /// the `delete-customer` Edge Function. Returns an error message, or null.
  Future<String?> deleteCustomer(String id) async {
    final client = supabaseOrNull;
    if (client == null) {
      return 'Cannot reach the server. Check your connection.';
    }
    try {
      final result = await client.functions
          .invoke('delete-customer', body: {'customerId': id});
      final data = result.data;
      if (data is Map && data['ok'] == true) return null;
      return adminSetupMessage(data is Map ? data['error'] as String? : null);
    } on FunctionException catch (e) {
      final details = e.details;
      return adminSetupMessage(
          details is Map ? details['error'] as String? : null);
    } catch (_) {
      return 'Could not delete the customer.';
    }
  }

  void _audit(String action,
      {String? customerId,
      String? entityType,
      String? entityId,
      Map<String, dynamic>? before,
      Map<String, dynamic>? after}) {
    final client = supabaseOrNull;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) return;
    client.from('audit_logs').insert({
      'customer_id': customerId ?? _resolvedCustomerId,
      'actor_user_id': uid,
      'actor_role': role.name,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'before_json': before,
      'after_json': after,
    }).then((_) {}, onError: (_) {});
  }

  Future<List<AuditLog>> loadAuditLogs({int limit = 200}) async {
    final client = supabaseOrNull;
    if (client == null) return [];
    try {
      final rows = await client
          .from('audit_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => AuditLog.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// PG names for a customer, for the admin console. The owner app stores PGs
  /// in the `app_data` blob keyed by the owner's user id (not the relational
  /// `pgs` table), so resolve the owner from the customer's profile, then read
  /// the blob (admins have a read policy on `app_data`).
  Future<String?> _customerOwnerId(
      SupabaseClient client, String customerId) async {
    final prof = await client
        .from('profiles')
        .select('id')
        .eq('customer_id', customerId)
        .eq('role', 'owner')
        .limit(1)
        .maybeSingle();
    return prof?['id'] as String?;
  }

  Future<List<Map>> _ownerCollection(
      SupabaseClient client, String ownerId, String key) async {
    final row = await client
        .from('app_data')
        .select('data')
        .eq('owner_id', ownerId)
        .eq('key', key)
        .maybeSingle();
    return (row?['data'] as List? ?? const []).cast<Map>();
  }

  Future<List<({String id, String name})>> loadCustomerPgs(
      String customerId) async {
    final client = supabaseOrNull;
    if (client == null) return [];
    try {
      final ownerId = await _customerOwnerId(client, customerId);
      if (ownerId == null) return [];
      final data = await _ownerCollection(client, ownerId, 'pgs');
      return [
        for (final e in data)
          if ((e['name'] as String? ?? '').isNotEmpty)
            (id: e['id'] as String? ?? '', name: e['name'] as String)
      ];
    } catch (_) {
      return [];
    }
  }

  /// Platform-admin deletion of a customer's PG, editing the owner's
  /// app_data blob directly (011 grants admins update). Same guard as the
  /// owner path: blocked while tenants live in the property.
  Future<String?> adminRemovePg(
      {required String customerId, required String pgId}) async {
    final client = supabaseOrNull;
    if (client == null) {
      return 'Cannot reach the server. Check your connection.';
    }
    try {
      final ownerId = await _customerOwnerId(client, customerId);
      if (ownerId == null) return 'Owner not found.';
      final pgsData = await _ownerCollection(client, ownerId, 'pgs');
      if (!pgsData.any((p) => p['id'] == pgId)) return 'Property not found.';
      final roomsData = await _ownerCollection(client, ownerId, 'rooms');
      final tenantsData = await _ownerCollection(client, ownerId, 'tenants');
      final roomIds =
          roomsData.where((r) => r['pgId'] == pgId).map((r) => r['id']).toSet();
      if (tenantsData.any((t) => roomIds.contains(t['roomId']))) {
        return 'Cannot delete a property with active tenants.';
      }
      await client
          .from('app_data')
          .update({'data': pgsData.where((p) => p['id'] != pgId).toList()})
          .eq('owner_id', ownerId)
          .eq('key', 'pgs');
      await client
          .from('app_data')
          .update({'data': roomsData.where((r) => r['pgId'] != pgId).toList()})
          .eq('owner_id', ownerId)
          .eq('key', 'rooms');
      _audit('pg_removed',
          customerId: customerId, entityType: 'pg', entityId: pgId);
      return null;
    } catch (_) {
      return 'Something went wrong. Please try again.';
    }
  }

  /// [redirectTo] is the web app the reset link opens: the tenant app by
  /// default, the owner app for owner and admin accounts.
  Future<String?> sendPasswordReset(String email,
      {String redirectTo = appWebUrl}) async {
    final client = supabaseOrNull;
    if (client == null) return 'code:network';
    try {
      // redirectTo returns the reset link to the app, which then fires a
      // passwordRecovery event and shows the set-password screen.
      await client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'code:network';
    }
  }

  /// Sets a new permanent password and clears the set-password gate. For the
  /// first-login flow [currentPassword] (the temporary password) is
  /// re-validated first — access is not granted until it checks out and the
  /// new password is saved. Recovery-link flows pass no [currentPassword].
  Future<String?> changePassword(String password,
      {String? currentPassword}) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) {
      return 'Sign in with an account to change your password.';
    }
    final email = accountEmail;
    if (currentPassword != null) {
      if (email == null) return 'code:generic';
      if (currentPassword.isEmpty) return 'code:temp_wrong';
      try {
        await client.auth
            .signInWithPassword(email: email, password: currentPassword);
      } on AuthException {
        return 'code:temp_wrong';
      } catch (_) {
        return 'code:network';
      }
    }
    if (mustChangePassword) {
      // Through the invite function: it re-verifies the temporary password
      // (or the fresh reset-link sign-in) and clears the temporary-password
      // flag in app_metadata, which the app itself cannot write and the
      // database enforces.
      final serverError = await _serverSetPassword(client,
          tempPassword: currentPassword ?? '', newPassword: password);
      if (serverError != null) return serverError;
    } else {
      try {
        await client.auth.updateUser(UserAttributes(password: password));
      } on AuthException catch (e) {
        return e.message;
      } catch (_) {
        return 'Could not update the password. Check your connection.';
      }
    }
    // Fresh JWT so backend policies (which block writes while the
    // temporary-password claim is set) see the cleared flag immediately.
    try {
      await client.auth.refreshSession();
    } catch (_) {}
    if (role == UserRole.tenant && !passwordRecovery) {
      // First-login onboarding complete — consume the one-time invite token.
      try {
        await client.functions.invoke('invite', body: {'action': 'accept'});
      } catch (_) {}
    }
    mustChangePassword = false;
    passwordRecovery = false;
    notifyListeners();
    return null;
  }

  Future<String?> _serverSetPassword(SupabaseClient client,
      {required String tempPassword, required String newPassword}) async {
    try {
      final result = await client.functions.invoke('invite', body: {
        'action': 'set-password',
        'tempPassword': tempPassword,
        'newPassword': newPassword,
      });
      final data = result.data;
      if (data is Map && data['ok'] == true) return null;
      return data is Map
          ? data['error'] as String? ?? 'code:generic'
          : 'code:generic';
    } on FunctionException catch (e) {
      final details = e.details;
      return details is Map
          ? details['error'] as String? ?? 'code:generic'
          : 'code:generic';
    } catch (_) {
      return 'Could not update the password. Check your connection.';
    }
  }

  Future<void> restoreCloudSession() async {
    final user = supabaseOrNull?.auth.currentSession?.user;
    if (user == null) return;
    try {
      final error = await _enterCloud(user);
      // Offline at startup: keep the session for the next try.
      if (error != null && error != 'code:network') {
        authNotice = error;
        try {
          await supabaseOrNull?.auth.signOut();
        } catch (_) {}
        notifyListeners();
      }
    } catch (_) {}
  }

  /// The server enforces the flag from app_metadata (only the service role
  /// can write it); user_metadata covers accounts invited before that.
  static bool _hasTempPassword(User user) =>
      user.appMetadata['must_change_password'] == true ||
      user.userMetadata?['must_change_password'] == true;

  Future<AccessGate> _fetchAccessGate(User user) async {
    final client = supabaseOrNull;
    if (client == null) return (role: null, customerId: null, error: null);
    Map<String, dynamic>? profile;
    Map<String, dynamic>? customer;
    try {
      profile = await client
          .from('profiles')
          .select('role, customer_id, platform_admin')
          .eq('id', user.id)
          .maybeSingle();
      final linkedCustomer = profile?['customer_id'] as String?;
      if (linkedCustomer != null) {
        customer = await client
            .from('customers')
            .select('status, expires_at')
            .eq('id', linkedCustomer)
            .maybeSingle();
      }
    } catch (_) {
      return (role: null, customerId: null, error: 'code:network');
    }
    return evaluateProfileAccess(profile: profile, customer: customer);
  }

  Future<String?> _enterCloud(User user, {LoginPortal? portal}) async {
    final client = supabaseOrNull!;

    final gate = await _fetchAccessGate(user);
    if (gate.error != null) return gate.error;

    String workspaceOwnerId = user.id;
    String? linkedTenantId;
    // Owners and admins always work in their own account; a membership row
    // naming their email (which someone else could have created) is ignored.
    final managerAccount =
        gate.role == UserRole.owner || gate.role == UserRole.admin;
    if (!managerAccount) {
      try {
        // Oldest link wins, so a later row can't redirect an existing tenant.
        final membership = await client
            .from('members')
            .select('owner_id, tenant_id')
            .eq('member_email', (user.email ?? '').toLowerCase())
            .order('created_at', ascending: true)
            .limit(1)
            .maybeSingle();
        if (membership != null) {
          workspaceOwnerId = membership['owner_id'] as String;
          linkedTenantId = membership['tenant_id'] as String;
        }
      } catch (_) {}
    }

    // Every owner and admin has a profile; tenants have a profile or a
    // workspace link. Anything else was not created by this platform (for
    // example through open sign-up) and gets nothing. The role is never
    // taken from user_metadata, which the user can edit.
    if (gate.role == null && linkedTenantId == null) {
      return 'This account is not linked to any PG business yet. Contact support.';
    }
    final resolvedRole = gate.role ?? UserRole.tenant;

    if (portal != null) {
      final mismatch = portalError(resolvedRole, portal);
      if (mismatch != null) return mismatch;
    }

    // A tenant still on their temporary password is mid-invite: an expired
    // or revoked invite blocks the sign-in (enforced server-side too — the
    // Edge Function owns all lifecycle transitions).
    if (resolvedRole == UserRole.tenant && _hasTempPassword(user)) {
      final inviteError = await _inviteLoginError(client);
      if (inviteError != null) return inviteError;
    }

    role = resolvedRole;
    currentTenantId = linkedTenantId ?? '';
    _cloudName = user.userMetadata?['full_name'] as String?;
    accountEmail = user.email;
    mustChangePassword = _hasTempPassword(user);
    authNotice = null;
    _workspaceOwnerId = workspaceOwnerId;
    _resolvedCustomerId = gate.customerId;
    _useSupabaseRepos(workspaceOwnerId);
    await _loadAll();
    await _ensureMonthlyDuesAtStartup();
    await loadSubmissions();
    _subscribeRealtime(supabaseOrNull!, workspaceOwnerId);
    isLoggedIn = true;
    notifyListeners();
    return null;
  }

  // ---- Live sync: any workspace write refreshes every open app ----

  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounce;

  void _subscribeRealtime(SupabaseClient client, String ownerId) {
    _unsubscribeRealtime();
    // A save writes several rows at once — debounce into one reload.
    void onChange(dynamic _) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 600), () async {
        if (!isLoggedIn) return;
        try {
          await _loadAll();
          await _ensureMonthlyDuesAtStartup();
          await loadSubmissions();
          notifyListeners();
        } catch (_) {}
      });
    }

    try {
      _realtimeChannel = client.channel('workspace-$ownerId')
        ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            // Tenants cannot read app_data rows, so they listen for the
            // workspace's change ping and re-fetch their filtered view.
            table: role == UserRole.tenant ? 'workspace_changes' : 'app_data',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'owner_id',
                value: ownerId),
            callback: onChange)
        ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'upi_submissions',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'owner_id',
                value: ownerId),
            callback: onChange)
        ..subscribe();
    } catch (_) {
      _realtimeChannel = null;
    }
  }

  void _unsubscribeRealtime() {
    _realtimeDebounce?.cancel();
    final channel = _realtimeChannel;
    _realtimeChannel = null;
    if (channel != null) {
      try {
        supabaseOrNull?.removeChannel(channel);
      } catch (_) {}
    }
  }

  /// Creates the tenant's login via the `invite` Edge Function: a temporary
  /// password (forced change at first sign-in), a one-time invite token with
  /// an expiry, and the workspace link. Tenants can never self-register.
  /// The email is the one saved on the tenant record at onboarding.
  /// [tempPassword] is null when the email already had its own password.
  Future<InviteResult> inviteTenant({required String tenantId}) {
    final email = tenantById(tenantId)?.email?.trim() ?? '';
    if (email.isEmpty) {
      return Future.value(_inviteFailure(
          'No email on file for this tenant — add one at onboarding.'));
    }
    return _inviteAction('create', tenantId: tenantId, email: email);
  }

  /// Supersedes the previous invite (status → resent) and issues a fresh
  /// token; the temporary password is regenerated only while the tenant has
  /// never set their own password.
  Future<InviteResult> resendInvite({required String tenantId}) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) {
      return _inviteFailure('Sign in with a cloud account to invite tenants.');
    }
    String? email = tenantById(tenantId)?.email;
    if (email == null || email.isEmpty) {
      try {
        final row = await client
            .from('invites')
            .select('email')
            .eq('tenant_id', tenantId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        email = row?['email'] as String?;
      } catch (_) {}
    }
    if (email == null || email.isEmpty) {
      return _inviteFailure(
          'No previous invite for this tenant — use "Invite to app" first.');
    }
    return _inviteAction('resend', tenantId: tenantId, email: email);
  }

  /// Cancels the pending invite: the token becomes unusable and a never-used
  /// temporary password is scrambled server-side.
  Future<InviteResult> revokeInvite({required String tenantId}) =>
      _inviteAction('revoke', tenantId: tenantId);

  Future<InviteResult> _inviteAction(String action,
      {required String tenantId, String? email}) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) {
      return _inviteFailure('Sign in with a cloud account to invite tenants.');
    }
    final address = email?.trim().toLowerCase();
    final tenant = tenantById(tenantId);
    final room = roomById(tenant?.roomId ?? '');
    // The server reads the tenant from the stored workspace, so a just-added
    // tenant must be saved first.
    await flushSaves();
    try {
      final result = await client.functions.invoke('invite', body: {
        'action': action,
        'tenantId': tenantId,
        if (address != null) 'email': address,
        'tenantName': tenant?.name ?? '',
        'pgName': pgNameForTenant(tenantId),
        'pgId': room?.pgId ?? '',
        'roomId': tenant?.roomId ?? '',
        'bedLabel': tenant?.bed ?? '',
        'lang': language.code,
      });
      final data = result.data;
      if (data is Map && data['ok'] == true) {
        return (
          error: null,
          tempPassword: data['tempPassword'] as String?,
          token: data['token'] as String?,
          expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? ''),
          email: address,
          emailSent: data['emailSent'] == true,
        );
      }
      return _inviteFailure(
          inviteActionMessage(data is Map ? data['error'] as String? : null));
    } on FunctionException catch (e) {
      final details = e.details;
      return _inviteFailure(inviteActionMessage(
          details is Map ? details['error'] as String? : null));
    } catch (_) {
      return _inviteFailure(
          'Could not reach the invite service. Check your connection.');
    }
  }

  /// Server-side invite lifecycle check for a tenant still on a temporary
  /// password: an expired or revoked invite blocks the sign-in. Network
  /// failures never block (parity with the profiles gate).
  Future<String?> _inviteLoginError(SupabaseClient client) async {
    try {
      final result =
          await client.functions.invoke('invite', body: {'action': 'validate'});
      final data = result.data;
      if (data is Map && data['error'] is String) {
        return inviteActionMessage(data['error'] as String);
      }
      return null;
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['error'] as String? : null;
      if (code == 'code:invite_expired' || code == 'code:invite_revoked') {
        return inviteActionMessage(code);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ---- Lookups ----

  Pg? pgById(String id) => _firstOrNull(pgs, (e) => e.id == id);
  Room? roomById(String id) => _firstOrNull(rooms, (e) => e.id == id);
  Tenant? tenantById(String id) => _firstOrNull(tenants, (e) => e.id == id);

  String tenantName(String id) => tenantById(id)?.name ?? 'Former tenant';
  String roomNumber(String roomId) => roomById(roomId)?.number ?? '—';
  String tenantRoomLabel(Tenant tenant) =>
      '${roomNumber(tenant.roomId)}-${tenant.bed}';

  Tenant? get currentTenant => tenantById(currentTenantId);
  String get currentTenantRoomLabel {
    final tenant = currentTenant;
    return tenant == null ? '—' : tenantRoomLabel(tenant);
  }

  /// SaaS scope stamped onto every record this session creates: the resolved
  /// customer when known, else the workspace owner.
  String get customerId => _resolvedCustomerId ?? _workspaceOwnerId ?? '';

  // ---- Active property (multi-PG owners work one property at a time) ----

  Pg? get activePg {
    if (pgs.isEmpty) return null;
    return pgById(_activePgId ?? '') ?? pgs.first;
  }

  void selectPg(String id) {
    _activePgId = id;
    notifyListeners();
  }

  // ---- Preferences (language persists on-device via SharedPreferences) ----

  static const _langKey = 'app_language';
  static const _themeKey = 'app_theme';
  static const _pushKey = 'push_enabled';

  ThemeMode themeMode = ThemeMode.system;

  Future<void> loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_langKey);
      if (code != null) {
        language = AppLanguage.fromCode(code);
      }
      pushEnabled = prefs.getBool(_pushKey) ?? true;
      pushWanted = pushEnabled;
      final theme = prefs.getString(_themeKey);
      if (theme != null) {
        themeMode = ThemeMode.values
            .firstWhere((m) => m.name == theme, orElse: () => ThemeMode.system);
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Called by the bootstrap observer when the OS light/dark setting flips,
  /// so ThemeMode.system apps rebuild with the right theme tokens.
  void systemThemeChanged() => notifyListeners();

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
    try {
      SharedPreferences.getInstance()
          .then((p) => p.setString(_themeKey, mode.name))
          .catchError((_) => false);
    } catch (_) {}
  }

  void setLanguage(AppLanguage lang) {
    language = lang;
    notifyListeners();
    try {
      SharedPreferences.getInstance()
          .then((p) => p.setString(_langKey, lang.code))
          .catchError((_) => false);
    } catch (_) {}
  }

  /// Whether this device receives push notifications. Off removes the
  /// device's token from the server; it never stops this device's actions
  /// from notifying other people.
  void setPushEnabled(bool value) {
    pushEnabled = value;
    pushWanted = value;
    notifyListeners();
    unawaited(value ? registerPushToken() : unregisterPushToken());
    try {
      SharedPreferences.getInstance()
          .then((p) => p.setBool(_pushKey, value))
          .catchError((_) => false);
    } catch (_) {}
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

  List<Visitor> get pgVisitors {
    final ids = _pgTenantIds;
    return visitors.where((v) => ids.contains(v.tenantId)).toList();
  }

  int get pgDueAmount => pgPayments.fold(0, (sum, e) => sum + e.balance);

  int get pgCollectedAmount => _receivedIn(pgPayments, DateTime.now());

  /// Money received in [month] (by the day it arrived, not the rent month
  /// it paid for), so arrears collected today count today.
  static int _receivedIn(Iterable<Payment> pool, DateTime month) => pool
      .where((e) =>
          e.paidDate != null &&
          e.paidDate!.year == month.year &&
          e.paidDate!.month == month.month)
      .fold(0, (sum, e) => sum + e.collected);

  String pgNameForTenant(String tenantId) {
    final room = roomById(tenantById(tenantId)?.roomId ?? '');
    return pgById(room?.pgId ?? '')?.name ?? 'PG Management';
  }

  String pgIdForPayment(Payment p) => _pgIdForTenant(p.tenantId) ?? '';

  Future<String?> proofUrl(String path) async {
    final client = supabaseOrNull;
    if (client == null) return null;
    try {
      return await client.storage
          .from('payment-proofs')
          .createSignedUrl(path, 600);
    } catch (_) {
      return null;
    }
  }

  String get displayName {
    if (role == UserRole.tenant) {
      return currentTenant?.name ?? _cloudName ?? 'Tenant';
    }
    return _cloudName ?? accountEmail?.split('@').first ?? 'Account';
  }

  String get initials => displayName
      .split(' ')
      .where((e) => e.isNotEmpty)
      .map((e) => e[0])
      .take(2)
      .join();

  /// The phone shown on the profile (tenants have one; managers may not).
  String? get profilePhone =>
      role == UserRole.tenant ? currentTenant?.phone : null;

  /// Updates the signed-in person's name (and a tenant's phone). Returns a
  /// user-facing error, or null on success.
  Future<String?> updatePersonalDetails(
      {required String name, String? phone}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return 'Enter your name.';
    if (role == UserRole.tenant) {
      final i = tenants.indexWhere((t) => t.id == currentTenantId);
      if (i != -1) {
        tenants[i] = tenants[i].copyWith(
            name: cleanName, phone: (phone ?? tenants[i].phone).trim());
        _cloudName = cleanName;
        await _persist({'tenants'});
        return null;
      }
      notifyListeners();
      return null;
    }
    try {
      await supabaseOrNull?.auth
          .updateUser(UserAttributes(data: {'full_name': cleanName}));
    } catch (_) {}
    _cloudName = cleanName;
    notifyListeners();
    return null;
  }

  /// Attaches/updates the current tenant's KYC document image.
  Future<void> updateKycDoc(String base64) async {
    final i = tenants.indexWhere((t) => t.id == currentTenantId);
    if (i == -1) return;
    tenants[i] = tenants[i].copyWith(kycDoc: base64, kyc: KycStatus.pending);
    await _persist({'tenants'});
  }

  // ---- Aggregates ----

  int get totalBeds => pgs.fold(0, (sum, e) => sum + e.beds);
  int get occupiedBeds => pgs.fold(0, (sum, e) => sum + e.occupied);

  /// Outstanding rent across all payments — includes the unpaid balance of
  /// partially-settled dues, not just untouched ones.
  int get dueAmount => payments.fold(0, (sum, e) => sum + e.balance);

  int get collectedAmount => _receivedIn(payments, DateTime.now());

  List<({DateTime month, int total})> monthlyRevenue(
      {int months = 6, List<Payment>? source}) {
    final now = DateTime.now();
    final pool = source ?? payments;
    return List.generate(months, (i) {
      final month = DateTime(now.year, now.month - (months - 1 - i));
      return (month: month, total: _receivedIn(pool, month));
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

  int _idSeq = 0;

  // Unique even under a coarse clock: a monotonic counter disambiguates ids
  // created within the same microsecond (e.g. onboarding two tenants quickly).
  String _id(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  void _notify(
    String title,
    String body,
    NotificationType type, {
    NotificationScope scope = NotificationScope.managers,
    String? tenantId,
    String? pgId,
    String? relatedEntityId,
    bool push = true,
  }) {
    notifications.insert(
        0,
        AppNotification(
          id: _id('n'),
          title: title,
          body: body,
          type: type,
          createdAt: DateTime.now(),
          roleScope: scope,
          tenantId: tenantId,
          pgId: pgId,
          relatedEntityId: relatedEntityId,
          customerId: customerId,
        ));
    if (push) {
      _pushToWorkspace(title, body,
          scope: scope, tenantId: tenantId, pgId: pgId);
    }
  }

  /// Fire-and-forget push via the `push` Edge Function. Scope and tenant are
  /// passed so the function can target the right devices; push failures never
  /// block the action itself.
  void _pushToWorkspace(String title, String body,
      {required NotificationScope scope, String? tenantId, String? pgId}) {
    final client = supabaseOrNull;
    final owner = _workspaceOwnerId;
    if (client == null || owner == null) return;
    client.functions.invoke('push', body: {
      'workspaceOwnerId': owner,
      'title': title,
      'body': body,
      'scope': scope.name,
      if (tenantId != null) 'tenantId': tenantId,
      if (pgId != null) 'pgId': pgId,
    }).ignore();
  }

  // Which property a tenant/room belongs to — used to scope notifications.
  String? _pgIdForTenant(String tenantId) =>
      roomById(tenantById(tenantId)?.roomId ?? '')?.pgId;
  String? _pgIdForRoom(String roomId) => roomById(roomId)?.pgId;
  List<Tenant> _tenantsInRoom(String roomId) =>
      tenants.where((t) => t.roomId == roomId).toList();

  /// Notifications the current session is allowed to see. Tenants get only
  /// their own personal notifications plus workspace-wide announcements;
  /// owners/admins get managerial and workspace notifications scoped to the
  /// property they are currently managing.
  List<AppNotification> get visibleNotifications {
    if (role == UserRole.tenant) {
      final id = currentTenantId;
      return notifications
          .where((n) =>
              n.roleScope == NotificationScope.everyone ||
              (n.roleScope == NotificationScope.tenant && n.tenantId == id))
          .toList();
    }
    final pgId = activePg?.id;
    return notifications.where((n) {
      if (n.roleScope == NotificationScope.tenant) {
        return false; // personal to a tenant
      }
      if (n.pgId != null && pgId != null && n.pgId != pgId) {
        return false; // another property
      }
      return true;
    }).toList();
  }

  /// Read state is per reader for shared notifications: a tenant's id, or
  /// `managers` for the owner side.
  String get _readerKey =>
      role == UserRole.tenant ? currentTenantId : 'managers';

  bool isRead(AppNotification n) => n.isReadBy(_readerKey);

  bool get hasUnread => visibleNotifications.any((n) => !isRead(n));

  AppNotification _markedRead(AppNotification n) => n.copyWith(
      read: true,
      readBy: n.roleScope == NotificationScope.everyone &&
              !n.readBy.contains(_readerKey)
          ? [...n.readBy, _readerKey]
          : null);

  void markNotificationRead(String id) {
    final i = notifications.indexWhere((n) => n.id == id);
    if (i == -1) return;
    notifications[i] = _markedRead(notifications[i]);
    _persist({'notifications'});
  }

  void markAllNotificationsRead() {
    // Only clear the ones this session can actually see.
    final visibleIds = visibleNotifications.map((n) => n.id).toSet();
    notifications = notifications
        .map((n) => visibleIds.contains(n.id) ? _markedRead(n) : n)
        .toList();
    _persist({'notifications'});
  }

  void savePg(Pg pg) {
    final stamped = pg.copyWith(customerId: pg.customerId ?? customerId);
    final i = pgs.indexWhere((e) => e.id == stamped.id);
    if (i == -1) {
      pgs.insert(0, stamped);
    } else {
      pgs[i] = stamped;
    }
    _persist({'pgs'});
  }

  /// Adds a room to its PG. Returns an error when the PG already has a room
  /// with that number.
  String? addRoom(Room room) {
    if (room.floor < 0 || room.floor > maxFloor) {
      return 'Pick a floor from Ground to $maxFloor.';
    }
    final number = room.number.trim().toLowerCase();
    if (rooms.any((r) =>
        r.pgId == room.pgId && r.number.trim().toLowerCase() == number)) {
      return 'Room ${room.number.trim()} already exists in this PG.';
    }
    rooms.add(room.copyWith(customerId: room.customerId ?? customerId));
    final p = pgs.indexWhere((e) => e.id == room.pgId);
    if (p != -1) pgs[p] = pgs[p].copyWith(beds: pgs[p].beds + room.beds);
    _persist({'rooms', 'pgs'});
    _audit('room_created',
        entityType: 'room',
        entityId: room.id,
        after: {'number': room.number, 'beds': room.beds});
    return null;
  }

  /// Creates a PG. Rooms/beds/rent are configured later (during onboarding or
  /// on the Rooms & Beds screen), so [specs] is optional — a PG may start with
  /// no rooms.
  String? createProperty(
      {required String name,
      required String address,
      required String amenities,
      List<({String number, int floor, int beds, int rent})> specs =
          const []}) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return 'Enter a property name.';
    final pgId = 'p${DateTime.now().microsecondsSinceEpoch}';
    final totalBeds = specs.fold(0, (s, e) => s + e.beds);
    pgs.insert(
        0,
        Pg(
            id: pgId,
            name: cleanName,
            address: address.trim(),
            beds: totalBeds,
            occupied: 0,
            amenities: amenities.trim(),
            rating: 0,
            customerId: customerId));
    var seq = 0;
    for (final s in specs) {
      rooms.add(Room(
          id: 'r${DateTime.now().microsecondsSinceEpoch}-${seq++}',
          pgId: pgId,
          number: s.number,
          floor: s.floor,
          beds: s.beds,
          occupied: 0,
          rent: s.rent,
          customerId: customerId));
    }
    _activePgId = pgId;
    _persist({'pgs', 'rooms'});
    _audit('pg_created',
        entityType: 'pg',
        entityId: pgId,
        after: {'name': cleanName, 'beds': totalBeds});
    return null;
  }

  int _roomOccupancy(Room room) {
    final tenantCount = tenants.where((t) => t.roomId == room.id).length;
    return tenantCount > room.occupied ? tenantCount : room.occupied;
  }

  /// Removes a room only when empty (its beds go with it). Blocks deletion of
  /// an occupied room and keeps the PG bed count in step.
  String? removeRoom(String roomId) {
    final i = rooms.indexWhere((r) => r.id == roomId);
    if (i == -1) return 'Room not found.';
    if (_roomOccupancy(rooms[i]) > 0) {
      return 'Cannot remove a room with active tenants.';
    }
    final removed = rooms.removeAt(i);
    final p = pgs.indexWhere((e) => e.id == removed.pgId);
    if (p != -1) {
      final beds = pgs[p].beds - removed.beds;
      pgs[p] = pgs[p].copyWith(beds: beds < 0 ? 0 : beds);
    }
    _persist({'rooms', 'pgs'});
    _audit('room_removed',
        entityType: 'room',
        entityId: roomId,
        before: {'number': removed.number, 'beds': removed.beds});
    return null;
  }

  /// Deletes a property and everything scoped to it (rooms, their open
  /// maintenance requests, its announcements). Blocked while any tenant
  /// still lives there — offboard tenants first.
  String? removePg(String pgId) {
    final i = pgs.indexWhere((p) => p.id == pgId);
    if (i == -1) return 'Property not found.';
    final roomIds = rooms.where((r) => r.pgId == pgId).map((r) => r.id).toSet();
    if (tenants.any((t) => roomIds.contains(t.roomId))) {
      return 'Cannot delete a property with active tenants.';
    }
    final removed = pgs.removeAt(i);
    rooms.removeWhere((r) => r.pgId == pgId);
    maintenance.removeWhere((m) => roomIds.contains(m.roomId));
    announcements.removeWhere((a) => a.pgId == pgId);
    if (_activePgId == pgId) _activePgId = null;
    _persist({'pgs', 'rooms', 'maintenance', 'announcements'});
    _audit('pg_removed',
        entityType: 'pg',
        entityId: pgId,
        before: {'name': removed.name, 'rooms': roomIds.length});
    return null;
  }

  /// Edits a room's number and floor. Rejects a duplicate number in the PG.
  String? editRoom(String roomId,
      {required String number, required int floor}) {
    final i = rooms.indexWhere((r) => r.id == roomId);
    if (i == -1) return 'Room not found.';
    final clean = number.trim();
    if (clean.isEmpty) return 'Enter a room number.';
    final r = rooms[i];
    // A room already on a higher floor may keep it.
    if (floor < 0 || (floor > maxFloor && floor != r.floor)) {
      return 'Pick a floor from Ground to $maxFloor.';
    }
    if (rooms.any((o) =>
        o.id != roomId &&
        o.pgId == r.pgId &&
        o.number.trim().toLowerCase() == clean.toLowerCase())) {
      return 'Room $clean already exists in this PG.';
    }
    rooms[i] = Room(
        id: r.id,
        pgId: r.pgId,
        number: clean,
        floor: floor,
        beds: r.beds,
        occupied: r.occupied,
        rent: r.rent,
        customerId: r.customerId);
    _persist({'rooms'});
    _audit('room_edited',
        entityType: 'room',
        entityId: roomId,
        after: {'number': clean, 'floor': floor});
    return null;
  }

  String? setRoomBeds(String roomId, int beds) {
    final i = rooms.indexWhere((r) => r.id == roomId);
    if (i == -1) return 'Room not found.';
    if (beds < _roomOccupancy(rooms[i])) {
      return 'Cannot reduce beds below occupied beds.';
    }
    final r = rooms[i];
    rooms[i] = Room(
        id: r.id,
        pgId: r.pgId,
        number: r.number,
        floor: r.floor,
        beds: beds,
        occupied: r.occupied,
        rent: r.rent,
        customerId: r.customerId);
    _persist({'rooms'});
    _audit('room_beds_changed',
        entityType: 'room',
        entityId: roomId,
        before: {'beds': r.beds},
        after: {'beds': beds});
    return null;
  }

  String? setRoomRent(String roomId, int rent) {
    final i = rooms.indexWhere((r) => r.id == roomId);
    if (i == -1) return 'Room not found.';
    final before = rooms[i].rent;
    rooms[i] = rooms[i].copyWith(rent: rent);
    // Tenants with their own agreed rent keep it.
    final duesChanged = _repriceDues(tenants
        .where((t) => t.roomId == roomId && t.rent == null)
        .map((t) => t.id)
        .toSet());
    _persist({'rooms', if (duesChanged) 'payments'});
    _audit('rent_changed',
        entityType: 'room',
        entityId: roomId,
        before: {'rent': before},
        after: {'rent': rent});
    return null;
  }

  /// The monthly rent a tenant is billed: their own agreed rent, else the
  /// room's rent per bed.
  int rentFor(Tenant tenant) =>
      tenant.rent ?? roomById(tenant.roomId)?.rent ?? 0;

  /// Applies each tenant's current rent ([rentFor]) to their untouched
  /// current and future dues. Anything with money against it — paid,
  /// partial, or a UPI proof under review — keeps its amount, so rent
  /// history is never rewritten. Returns true when a due changed.
  bool _repriceDues(Set<String> tenantIds) {
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final underReview = submissions
        .where((s) => s.status != UpiStatus.rejected)
        .map((s) => s.paymentId)
        .toSet();
    var changed = false;
    for (var p = 0; p < payments.length; p++) {
      final pay = payments[p];
      if (!tenantIds.contains(pay.tenantId)) continue;
      final tenant = tenantById(pay.tenantId);
      if (tenant == null) continue;
      final rent = rentFor(tenant);
      if (pay.status == PaymentStatus.due &&
          pay.paidAmount == 0 &&
          !pay.period.isBefore(month) &&
          !underReview.contains(pay.id) &&
          rent > 0 &&
          pay.amount != rent) {
        payments[p] = Payment(
          id: pay.id,
          tenantId: pay.tenantId,
          period: pay.period,
          amount: rent,
          status: pay.status,
          dueDate: pay.dueDate,
          paidDate: pay.paidDate,
          method: pay.method,
          paidAmount: pay.paidAmount,
          customerId: pay.customerId,
        );
        changed = true;
      }
    }
    return changed;
  }

  /// Sets the monthly rent agreed with one tenant, or with [rent] null puts
  /// them back on the room's rent. Untouched current and future dues follow
  /// at once; paid, part-paid and under-review dues keep their amount.
  /// Returns an error message, or null.
  String? setTenantRent(String tenantId, int? rent) {
    final i = tenants.indexWhere((t) => t.id == tenantId);
    if (i == -1) return 'Tenant not found.';
    if (rent != null && rent <= 0) return 'Enter a rent above zero.';
    final tenant = tenants[i];
    final before = rentFor(tenant);
    tenants[i] = rent == null
        ? tenant.copyWith(useRoomRent: true)
        : tenant.copyWith(rent: rent);
    final after = rentFor(tenants[i]);
    final duesChanged = _repriceDues({tenantId});
    if (after != before) {
      _notify('Rent updated', 'Your monthly rent is now ${inr(after)}.',
          NotificationType.payment,
          scope: NotificationScope.tenant,
          tenantId: tenantId,
          pgId: _pgIdForTenant(tenantId));
    }
    _persist({
      'tenants',
      if (duesChanged) 'payments',
      if (after != before) 'notifications'
    });
    _audit('tenant_rent_changed',
        entityType: 'tenant',
        entityId: tenantId,
        before: {'rent': before, 'custom': tenant.rent != null},
        after: {'rent': after, 'custom': rent != null});
    return null;
  }

  /// True when the room has a free bed.
  bool roomHasVacancy(String roomId) {
    final room = roomById(roomId);
    return room != null && room.occupied < room.beds;
  }

  /// Bed labels already taken in a room (upper-cased for comparison).
  Set<String> takenBeds(String roomId) => tenants
      .where((t) => t.roomId == roomId)
      .map((t) => t.bed.trim().toUpperCase())
      .toSet();

  /// The first free bed letter (A, B, C, …) for a room, or '' if none fit.
  String suggestBed(String roomId) {
    final room = roomById(roomId);
    if (room == null) return '';
    final taken = takenBeds(roomId);
    for (var i = 0; i < room.beds; i++) {
      final label = String.fromCharCode(65 + i); // A, B, C…
      if (!taken.contains(label)) return label;
    }
    return '';
  }

  /// Ensures a room exists in [pgId] with [roomNumber]. Creates it with the
  /// given sharing type (= beds) and current [rent] when missing; otherwise
  /// returns the existing room's id (its stored sharing/rent are inherited).
  /// Used by tenant onboarding, where room pricing is configured.
  String ensureRoom(
      {required String pgId,
      required int floor,
      required String roomNumber,
      required int sharingType,
      required int rent}) {
    final number = roomNumber.trim();
    final existing = _firstOrNull(
        rooms,
        (r) =>
            r.pgId == pgId &&
            r.number.trim().toLowerCase() == number.toLowerCase());
    if (existing != null) return existing.id;
    final room = Room(
      id: _id('r'),
      pgId: pgId,
      number: number,
      floor: floor,
      beds: sharingType,
      occupied: 0,
      rent: rent,
      customerId: customerId,
    );
    rooms.add(room);
    // Keep the PG's bed count in step so occupancy stats stay correct.
    final p = pgs.indexWhere((e) => e.id == pgId);
    if (p != -1) pgs[p] = pgs[p].copyWith(beds: pgs[p].beds + sharingType);
    _persist({'rooms', 'pgs'});
    _audit('room_created',
        entityType: 'room',
        entityId: room.id,
        after: {'number': number, 'beds': sharingType, 'rent': rent});
    return room.id;
  }

  /// Onboards a tenant after validating the inputs. Returns a user-facing
  /// error message, or null on success. Blocks full rooms and duplicate bed
  /// labels, and keeps room/property occupancy in step.
  String? onboardTenant(
      {required String name,
      required String phone,
      required String email,
      required String roomId,
      required String bed,
      String? kycDoc}) {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanBed = bed.trim();
    if (cleanName.isEmpty) return 'Enter the tenant\'s name.';
    if (cleanPhone.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
      return 'Enter a valid 10-digit phone number.';
    }
    if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (cleanBed.isEmpty) return 'Enter a bed label.';
    // The email becomes the tenant's login, so it must be theirs alone.
    if (tenants
        .any((t) => (t.email ?? '').trim().toLowerCase() == cleanEmail)) {
      return 'Another tenant already uses this email.';
    }

    final i = rooms.indexWhere((r) => r.id == roomId);
    if (i == -1) return 'Select a room.';
    final room = rooms[i];
    if (room.occupied >= room.beds) return 'Room ${room.number} is full.';
    if (takenBeds(roomId).contains(cleanBed.toUpperCase())) {
      return 'Bed $cleanBed is already taken in room ${room.number}.';
    }

    tenants.insert(
        0,
        Tenant(
          id: _id('t'),
          name: cleanName,
          phone: cleanPhone,
          email: cleanEmail,
          roomId: roomId,
          bed: cleanBed,
          kyc: KycStatus.pending,
          agreement: AgreementStatus.awaitingSign,
          joinDate: DateTime.now(),
          kycDoc: kycDoc,
          customerId: customerId,
        ));
    rooms[i] = room.copyWith(occupied: room.occupied + 1);
    final p = pgs.indexWhere((e) => e.id == room.pgId);
    if (p != -1 && pgs[p].occupied < pgs[p].beds) {
      pgs[p] = pgs[p].copyWith(occupied: pgs[p].occupied + 1);
    }
    // The new tenant's first due appears immediately in rent collection.
    generateMonthlyDues();
    final assigned = tenants.first;
    _persist({'tenants', 'rooms', 'pgs', 'payments'});
    _audit('tenant_assigned',
        entityType: 'tenant',
        entityId: assigned.id,
        after: {'name': cleanName, 'room_id': roomId, 'bed': cleanBed});
    return null;
  }

  /// Permanently removes a tenant: their record, visitors, notifications
  /// and untouched dues are deleted, their bed is freed, and the
  /// `remove-tenant` Edge Function deletes their login and emails them that
  /// they are no longer part of this PG. Money already received (paid and
  /// part-paid rows) stays in the books.
  Future<({String? error, String? email, bool emailSent})> removeTenant(
      String tenantId) async {
    final i = tenants.indexWhere((t) => t.id == tenantId);
    if (i == -1) {
      return (error: 'Tenant not found.', email: null, emailSent: false);
    }
    final tenant = tenants[i];
    final pgName = pgNameForTenant(tenantId);
    tenants.removeAt(i);
    payments.removeWhere((p) =>
        p.tenantId == tenantId &&
        p.status == PaymentStatus.due &&
        p.collected == 0);
    visitors.removeWhere((v) => v.tenantId == tenantId);
    attendance.removeWhere((a) => a.tenantId == tenantId);
    notifications.removeWhere((n) => n.tenantId == tenantId);
    final r = rooms.indexWhere((room) => room.id == tenant.roomId);
    if (r != -1 && rooms[r].occupied > 0) {
      rooms[r] = rooms[r].copyWith(occupied: rooms[r].occupied - 1);
      final p = pgs.indexWhere((e) => e.id == rooms[r].pgId);
      if (p != -1 && pgs[p].occupied > 0) {
        pgs[p] = pgs[p].copyWith(occupied: pgs[p].occupied - 1);
      }
    }
    final saved = await _persist({
      'tenants',
      'payments',
      'visitors',
      'attendance',
      'notifications',
      'rooms',
      'pgs'
    });
    // The removal didn't reach the server (the tenant is back after the
    // reload): keep their login too.
    if (!saved) {
      return (
        error: 'Could not remove the tenant. Check your connection and try '
            'again.',
        email: null,
        emailSent: false
      );
    }
    _audit('tenant_removed', entityType: 'tenant', entityId: tenantId, before: {
      'name': tenant.name,
      'room_id': tenant.roomId,
      'bed': tenant.bed
    });
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) {
      return (error: null, email: null, emailSent: false);
    }
    try {
      final result = await client.functions.invoke('remove-tenant', body: {
        'tenantId': tenantId,
        'tenantName': tenant.name,
        'pgName': pgName,
        'lang': language.code,
      });
      final data = result.data;
      if (data is Map && data['ok'] == true) {
        return (
          error: null,
          email: data['email'] as String?,
          emailSent: data['emailSent'] == true
        );
      }
    } catch (_) {}
    // The tenant is gone from the PG, but their login may still work: say so
    // instead of reporting a clean removal.
    return (
      error: 'Tenant removed, but their app login could not be deleted, so '
          'they may still be able to sign in. Contact support to remove it.',
      email: null,
      emailSent: false
    );
  }

  /// The current tenant's next unsettled payment (due or partially paid).
  Payment? get tenantDuePayment {
    Payment? oldest;
    for (final p in payments) {
      if (p.tenantId != currentTenantId || p.status == PaymentStatus.paid) {
        continue;
      }
      if (oldest == null || p.period.isBefore(oldest.period)) oldest = p;
    }
    return oldest;
  }

  /// Everything the signed-in tenant still owes, across all months.
  int get tenantOutstanding => _tenantBalance(currentTenantId);

  /// How many of the signed-in tenant's months are still unsettled.
  int get tenantUnpaidMonths => payments
      .where((p) =>
          p.tenantId == currentTenantId && p.status != PaymentStatus.paid)
      .length;

  /// What [tenantId] still owes across all months.
  int balanceOf(String tenantId) => _tenantBalance(tenantId);

  /// The signed-in tenant's own payments — never anyone else's.
  List<Payment> get tenantPayments =>
      payments.where((p) => p.tenantId == currentTenantId).toList();

  /// Rent collection as spreadsheet-ready CSV (newest first, like the UI).
  String paymentsCsv() {
    // Spreadsheets run a cell starting with = + - @ (or tab/CR) as a
    // formula, and tenants choose their own names: prefix those with '.
    String cell(String value) {
      final safe =
          value.isNotEmpty && '=+-@\t\r'.contains(value[0]) ? "'$value" : value;
      return '"${safe.replaceAll('"', '""')}"';
    }

    final rows = <String>[
      'Receipt,Tenant,Month,Amount,Collected,Balance,Status,Due date,Paid date,Method'
    ];
    for (final p in payments) {
      rows.add([
        p.id,
        tenantName(p.tenantId),
        formatMonth(p.period),
        '${p.amount}',
        '${p.collected}',
        '${p.balance}',
        p.displayStatus,
        formatFullDate(p.dueDate),
        p.paidDate == null ? '' : formatFullDate(p.paidDate!),
        p.method ?? '',
      ].map(cell).join(','));
    }
    return rows.join('\n');
  }

  /// Creates the Due payment for every month a tenant has no payment row
  /// for, from the month after their most recent row up to the current
  /// month (any status counts, so a partial or paid entry blocks a
  /// duplicate). A month nobody opened the app in is therefore still billed.
  /// A tenant with no rows at all gets only the current month, so history
  /// is never invented. Deterministic ids keep it idempotent across devices.
  /// Pass [onlyTenantId] to generate a single tenant's dues (used for tenant
  /// sessions, which display but don't persist owner-wide data).
  /// Returns true if anything was added.
  bool generateMonthlyDues({String? onlyTenantId}) {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final fifth = DateTime(now.year, now.month, 5);
    final currentDueDate =
        now.isBefore(fifth) ? fifth : now.add(const Duration(days: 3));
    var added = false;
    for (final tenant in tenants) {
      if (onlyTenantId != null && tenant.id != onlyTenantId) continue;
      final rent = rentFor(tenant);
      if (rent <= 0) continue;
      DateTime? latest;
      for (final p in payments) {
        if (p.tenantId != tenant.id) continue;
        final m = DateTime(p.period.year, p.period.month);
        if (latest == null || m.isAfter(latest)) latest = m;
      }
      var month =
          latest == null ? current : DateTime(latest.year, latest.month + 1);
      final joined = DateTime(tenant.joinDate.year, tenant.joinDate.month);
      if (month.isBefore(joined)) month = joined;
      for (;
          !month.isAfter(current);
          month = DateTime(month.year, month.month + 1)) {
        payments.insert(
            0,
            Payment(
              id: 'pay-${month.year}-${month.month}-${tenant.id}',
              tenantId: tenant.id,
              period: month,
              amount: rent,
              status: PaymentStatus.due,
              dueDate: month == current
                  ? currentDueDate
                  : DateTime(month.year, month.month, 5),
              customerId: customerId,
            ));
        added = true;
      }
      // Money paid in advance settles the dues it covers.
      if (_applyCredit(tenant.id)) added = true;
    }
    return added;
  }

  /// Ensures the current month's dues exist at app startup, for every role.
  /// Managers own the data and persist it; a tenant session only materialises
  /// its own due in memory (for display) and never writes owner-wide rows.
  Future<void> _ensureMonthlyDuesAtStartup() async {
    if (role == UserRole.tenant) {
      if (generateMonthlyDues(onlyTenantId: currentTenantId)) notifyListeners();
    } else if (generateMonthlyDues()) {
      await _persist({'payments'});
    }
  }

  // ---- Manual UPI rent payments (Prompt 9) ----

  String get workspaceId => _workspaceOwnerId ?? '';

  List<UpiSubmission> submissions = [];

  Future<void> loadSubmissions() async {
    final client = supabaseOrNull;
    if (client == null) {
      submissions = [];
      return;
    }
    try {
      final rows = await client
          .from('upi_submissions')
          .select()
          .order('submitted_at', ascending: false);
      submissions = (rows as List)
          .map(
              (r) => UpiSubmission.fromRow(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      submissions = [];
    }
  }

  UpiSubmission? latestSubmissionFor(String paymentId) =>
      _firstOrNull(submissions, (s) => s.paymentId == paymentId);

  /// The status a tenant/owner should see for a due, combining the stored
  /// payment with its latest submission: due · overdue · pending · paid ·
  /// rejected.
  String paymentStatusKey(Payment p) {
    if (p.status == PaymentStatus.paid) return 'paid';
    final sub = latestSubmissionFor(p.id);
    if (sub != null) {
      switch (sub.status) {
        case UpiStatus.pendingConfirmation:
          return 'pending';
        case UpiStatus.confirmed:
          // A confirmed short payment leaves the due part-paid.
          return p.status == PaymentStatus.partial ? 'due' : 'paid';
        case UpiStatus.rejected:
          return 'rejected';
      }
    }
    return p.isOverdue ? 'overdue' : 'due';
  }

  /// A tenant may submit when the due is unpaid and not already awaiting
  /// confirmation (a rejected submission can be resubmitted, and the rest of
  /// a confirmed short payment can be paid).
  bool canSubmit(Payment p) {
    if (p.status == PaymentStatus.paid) return false;
    final sub = latestSubmissionFor(p.id);
    return sub == null ||
        sub.status == UpiStatus.rejected ||
        (sub.status == UpiStatus.confirmed &&
            p.status == PaymentStatus.partial);
  }

  Future<UpiSettings?> loadUpiSettings(String pgId) async {
    final client = supabaseOrNull;
    if (client == null) return null;
    try {
      final row = await client
          .from('pg_upi_settings')
          .select()
          .eq('owner_id', workspaceId)
          .eq('pg_id', pgId)
          .maybeSingle();
      return row == null
          ? null
          : UpiSettings.fromRow(Map<String, dynamic>.from(row));
    } catch (_) {
      return null;
    }
  }

  /// Saves a PG's UPI details. [qrImage] is the owner's own UPI QR picture
  /// (base64); null leaves the stored one as it is, '' removes it.
  Future<String?> saveUpiSettings(String pgId,
      {required String upiId,
      required String payeeName,
      required bool enabled,
      String? qrImage}) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) return 'Sign in to save UPI settings.';
    try {
      await client.from('pg_upi_settings').upsert({
        'owner_id': workspaceId,
        'pg_id': pgId,
        'upi_id': upiId.trim(),
        'payee_name': payeeName.trim(),
        'enabled': enabled,
        if (qrImage != null) 'qr_image': qrImage.isEmpty ? null : qrImage,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'owner_id,pg_id');
      return null;
    } catch (_) {
      return 'Could not save UPI settings. Check your connection.';
    }
  }

  /// Tenant submits proof of a UPI payment: status becomes
  /// pending_confirmation. Returning from the UPI app does NOT mark anything
  /// paid — only the owner can confirm.
  Future<String?> submitPayment(
      {required Payment payment,
      required String utr,
      required int paidAmount,
      String note = '',
      Uint8List? screenshot}) async {
    // Proof is the payment screenshot, the UTR, or both. Some UPI apps
    // bury the UTR, so a screenshot alone is enough.
    final ref = utr.replaceAll(RegExp(r'\s'), '');
    if (ref.isEmpty && screenshot == null) {
      return 'Attach the payment screenshot or enter the 12-digit UTR.';
    }
    if (ref.isNotEmpty && !RegExp(r'^\d{12}$').hasMatch(ref)) {
      return 'Enter the 12-digit UPI reference (UTR).';
    }
    if (paidAmount <= 0) return 'Enter the amount you paid.';
    // One live submission per due: wait for the owner's decision first.
    if (!canSubmit(payment)) {
      return 'This payment is already submitted and awaiting review.';
    }
    // A UTR is unique per transaction — a repeat is a mistake or a re-use.
    if (ref.isNotEmpty &&
        submissions
            .any((s) => s.utr == ref && s.status != UpiStatus.rejected)) {
      return 'This UTR was already submitted. Check the reference number.';
    }
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) return 'Sign in to submit a payment.';
    final pgId = pgIdForPayment(payment);
    try {
      String? path;
      if (screenshot != null) {
        path =
            '$workspaceId/$pgId/${payment.tenantId}/${payment.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          await client.storage.from('payment-proofs').uploadBinary(
              path, screenshot,
              fileOptions: const FileOptions(contentType: 'image/jpeg'));
        } catch (_) {
          // Never file a submission without the proof the tenant attached.
          return 'Could not upload the screenshot. Check your connection and try again.';
        }
      }
      await client.from('upi_submissions').insert({
        'owner_id': workspaceId,
        'customer_id': _resolvedCustomerId,
        'pg_id': pgId,
        'tenant_id': payment.tenantId,
        'member_email': (accountEmail ?? '').toLowerCase(),
        'payment_id': payment.id,
        'period': payment.period.toIso8601String(),
        'amount': paidAmount,
        'utr': ref.isEmpty ? null : ref,
        'note': note.trim().isEmpty ? null : note.trim(),
        'screenshot_path': path,
      });
      // Audited by the database (017_review_fixes_2.sql): tenants can't
      // write audit_logs themselves.
      await loadSubmissions();
      notifyListeners();
      return null;
    } on PostgrestException catch (e) {
      // upi_submissions_utr_idx: the UTR is already used in this workspace.
      if (e.code == '23505') {
        return 'This UTR was already submitted. Check the reference number.';
      }
      return 'Could not submit the payment. Check your connection.';
    } catch (_) {
      return 'Could not submit the payment. Check your connection.';
    }
  }

  /// Owner-side: another submission in this workspace already used the same
  /// amount + UTR. A warning, not a block.
  UpiSubmission? duplicateOf(UpiSubmission s) => _firstOrNull(
      submissions,
      (o) =>
          o.id != s.id &&
          s.utr.isNotEmpty &&
          o.utr == s.utr &&
          o.amount == s.amount);

  List<UpiSubmission> get pendingSubmissions => submissions
      .where((s) => s.status == UpiStatus.pendingConfirmation)
      .toList();

  Future<String?> confirmSubmission(UpiSubmission s) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) return 'Sign in to confirm payments.';
    // The due has to be in the books before the submission is confirmed, or
    // the money would be confirmed but never recorded.
    if (!payments.any((p) => p.id == s.paymentId && p.tenantId == s.tenantId)) {
      return 'This rent due is no longer in the books. Refresh and try again.';
    }
    final repo = _paymentRepo;
    if (repo is SupabaseRepository<Payment>) {
      // One server transaction marks the submission confirmed and saves the
      // rent record: both happen or neither does (018_payments.sql).
      final before = List<Payment>.of(payments);
      final touched = _applyReceipt(
          tenantId: s.tenantId,
          amount: s.amount,
          method: 'UPI',
          dueId: s.paymentId);
      try {
        await repo.saveAllVia(
            'owner_confirm_submission', payments, {'p_submission': s.id});
      } on PostgrestException catch (e) {
        payments = before;
        if (e.code == 'PGRST202') {
          // Database without 018: the older two-step confirm.
          return _confirmSubmissionLegacy(client, s);
        }
        await loadSubmissions();
        notifyListeners();
        return e.message.contains('already reviewed')
            ? 'This payment was already reviewed.'
            : 'Could not confirm the payment. Check your connection.';
      } catch (_) {
        payments = before;
        notifyListeners();
        return 'Could not confirm the payment. Check your connection.';
      }
      _notifyReceipt(s.tenantId, s.amount, touched,
          managerSettled: 'Rent received',
          managerPartial: 'Part payment received',
          tenantSettled: 'Payment confirmed',
          tenantPartial: 'Payment confirmed');
      _persist({'notifications'});
      _audit('payment_confirmed',
          entityType: 'payment',
          entityId: s.paymentId,
          after: {'utr': s.utr, 'amount': s.amount});
      await loadSubmissions();
      notifyListeners();
      return null;
    }
    return _confirmSubmissionLegacy(client, s);
  }

  /// Confirm for a database without `owner_confirm_submission`: the
  /// submission and the rent record are saved one after the other.
  Future<String?> _confirmSubmissionLegacy(
      SupabaseClient client, UpiSubmission s) async {
    try {
      // Only a pending submission can be confirmed (not one rejected from
      // another screen in the meantime).
      final updated = await client
          .from('upi_submissions')
          .update({
            'status': 'confirmed',
            'confirmed_by': client.auth.currentUser?.id,
            'confirmed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', s.id)
          .eq('status', 'pending_confirmation')
          .select('id');
      if ((updated as List).isEmpty) {
        await loadSubmissions();
        notifyListeners();
        return 'This payment was already reviewed.';
      }
      final saved = await _markConfirmedPaid(s);
      _audit('payment_confirmed',
          entityType: 'payment',
          entityId: s.paymentId,
          after: {'utr': s.utr, 'amount': s.amount});
      await loadSubmissions();
      notifyListeners();
      if (!saved) {
        return 'The payment is confirmed, but the rent record could not be '
            'saved. Refresh; if the due still shows unpaid, use Record '
            'payment for ${inr(s.amount)}.';
      }
      return null;
    } catch (_) {
      return 'Could not confirm the payment. Check your connection.';
    }
  }

  /// Owner-side undo for a payment recorded by mistake: the due goes back
  /// to unpaid (an advance row is removed), a confirmed UPI submission for
  /// it is marked rejected so the tenant can submit again, and the tenant
  /// is told. Returns an error message, or null.
  Future<String?> reversePayment(String paymentId) async {
    if (role == UserRole.tenant) return 'Only the owner can reverse payments.';
    final i = payments.indexWhere((p) => p.id == paymentId);
    if (i == -1) return 'Payment not found.';
    final p = payments[i];
    if (p.collected == 0) return 'Nothing has been received for this due.';
    if (p.advance) {
      payments.removeAt(i);
    } else {
      payments[i] = Payment(
        id: p.id,
        tenantId: p.tenantId,
        period: p.period,
        amount: p.amount,
        status: PaymentStatus.due,
        dueDate: p.dueDate,
        customerId: p.customerId,
      );
    }
    final client = supabaseOrNull;
    if (client != null && isLoggedIn) {
      for (final sub in submissions.where(
          (x) => x.paymentId == paymentId && x.status == UpiStatus.confirmed)) {
        try {
          await client.from('upi_submissions').update({
            'status': 'rejected',
            'rejection_reason': 'Payment reversed by the owner',
          }).eq('id', sub.id);
        } catch (_) {}
      }
      await loadSubmissions();
    }
    _notify(
        'Payment reversed',
        p.advance
            ? 'An advance of ${inr(p.collected)} was removed from your account.'
            : 'The ${inr(p.collected)} recorded for ${formatMonthName(p.period)} rent was reversed. Contact your PG owner if this is wrong.',
        NotificationType.payment,
        scope: NotificationScope.tenant,
        tenantId: p.tenantId,
        pgId: _pgIdForTenant(p.tenantId),
        relatedEntityId: p.id);
    final saved = await _persist({'payments', 'notifications'});
    _audit('payment_reversed',
        entityType: 'payment',
        entityId: paymentId,
        before: {
          'collected': p.collected,
          'method': p.method,
          'advance': p.advance
        });
    return saved ? null : 'Could not save. Check your connection.';
  }

  Future<String?> rejectSubmission(UpiSubmission s, String reason) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) return 'Sign in to reject payments.';
    if (reason.trim().isEmpty) return 'Enter a reason for rejecting.';
    try {
      final updated = await client
          .from('upi_submissions')
          .update({
            'status': 'rejected',
            'rejection_reason': reason.trim(),
          })
          .eq('id', s.id)
          .eq('status', 'pending_confirmation')
          .select('id');
      if ((updated as List).isEmpty) {
        await loadSubmissions();
        notifyListeners();
        return 'This payment was already reviewed.';
      }
      // The due stays unpaid; tell the tenant why so they can resubmit.
      _notify(
          'Payment rejected',
          'Your payment of ${inr(s.amount)} was rejected: ${reason.trim()}',
          NotificationType.payment,
          scope: NotificationScope.tenant,
          tenantId: s.tenantId,
          pgId: _pgIdForTenant(s.tenantId),
          relatedEntityId: s.paymentId);
      _persist({'notifications'});
      _audit('payment_rejected',
          entityType: 'payment',
          entityId: s.paymentId,
          after: {'utr': s.utr, 'reason': reason.trim()});
      await loadSubmissions();
      notifyListeners();
      return null;
    } catch (_) {
      return 'Could not reject the payment. Check your connection.';
    }
  }

  /// Applies money received from a tenant to their unsettled dues: [dueId]
  /// first when given, then the oldest month first. Whatever is left after
  /// every due is settled becomes a standalone paid row (an advance) for the
  /// current month, so no rupee is dropped. Returns the rows it touched, in
  /// order.
  List<Payment> _applyReceipt(
      {required String tenantId,
      required int amount,
      required String method,
      String? dueId}) {
    final now = DateTime.now();
    final open = [
      for (var i = 0; i < payments.length; i++)
        if (payments[i].tenantId == tenantId &&
            payments[i].status != PaymentStatus.paid)
          i
    ]..sort((a, b) {
        if (payments[a].id == dueId) return -1;
        if (payments[b].id == dueId) return 1;
        return payments[a].period.compareTo(payments[b].period);
      });
    final touched = <Payment>[];
    var left = amount;
    for (final i in open) {
      if (left <= 0) break;
      final due = payments[i];
      final take = left < due.balance ? left : due.balance;
      left -= take;
      final collected = due.collected + take;
      final settled = collected >= due.amount;
      touched.add(payments[i] = due.copyWith(
          status: settled ? PaymentStatus.paid : PaymentStatus.partial,
          paidAmount: settled ? due.amount : collected,
          paidDate: now,
          method: method));
    }
    if (left > 0) {
      final advance = Payment(
        id: _id('pay'),
        tenantId: tenantId,
        period: DateTime(now.year, now.month),
        amount: left,
        status: PaymentStatus.paid,
        paidAmount: left,
        dueDate: DateTime(now.year, now.month, 5),
        paidDate: now,
        method: method,
        customerId: customerId,
        advance: true,
      );
      payments.insert(0, advance);
      touched.add(advance);
    }
    return touched;
  }

  /// Uses a tenant's unused advance money (oldest first) to settle their
  /// unsettled dues (oldest first). The settled due keeps the day the money
  /// actually arrived and is marked as paid from advance; the advance row
  /// shrinks by what was used and disappears when empty, so no rupee is
  /// counted twice. Returns true when anything changed.
  bool _applyCredit(String tenantId) {
    var changed = false;
    while (true) {
      final credits = payments
          .where((p) => p.tenantId == tenantId && p.advance && p.amount > 0)
          .toList()
        ..sort((a, b) =>
            (a.paidDate ?? a.period).compareTo(b.paidDate ?? b.period));
      final open = payments
          .where((p) =>
              p.tenantId == tenantId &&
              !p.advance &&
              p.status != PaymentStatus.paid &&
              // Nothing left to pay: never "open", or the loop below
              // could spin on it forever.
              p.balance > 0)
          .toList()
        ..sort((a, b) => a.period.compareTo(b.period));
      if (credits.isEmpty || open.isEmpty) return changed;
      final credit = credits.first;
      final due = open.first;
      final take = credit.amount < due.balance ? credit.amount : due.balance;
      final collected = due.collected + take;
      final settled = collected >= due.amount;
      payments[payments.indexOf(due)] = due.copyWith(
          status: settled ? PaymentStatus.paid : PaymentStatus.partial,
          paidAmount: settled ? due.amount : collected,
          paidDate: credit.paidDate,
          method: 'Advance');
      final left = credit.amount - take;
      final ci = payments.indexOf(credit);
      if (left <= 0) {
        payments.removeAt(ci);
      } else {
        payments[ci] = Payment(
          id: credit.id,
          tenantId: credit.tenantId,
          period: credit.period,
          amount: left,
          status: PaymentStatus.paid,
          paidAmount: left,
          dueDate: credit.dueDate,
          paidDate: credit.paidDate,
          method: credit.method,
          customerId: credit.customerId,
          advance: true,
        );
      }
      changed = true;
    }
  }

  /// Unused advance money a tenant has.
  int creditOf(String tenantId) => payments
      .where((p) => p.tenantId == tenantId && p.advance)
      .fold(0, (sum, p) => sum + p.amount);

  /// What a tenant still owes across all their dues.
  int _tenantBalance(String tenantId) => payments
      .where((p) => p.tenantId == tenantId)
      .fold(0, (sum, p) => sum + p.balance);

  /// Tells the managers and the tenant about money applied by
  /// [_applyReceipt].
  void _notifyReceipt(String tenantId, int amount, List<Payment> touched,
      {required String managerSettled,
      required String managerPartial,
      required String tenantSettled,
      required String tenantPartial}) {
    final settled = touched.every((p) => p.status == PaymentStatus.paid);
    final remaining = _tenantBalance(tenantId);
    final first = touched.first;
    final pgId = _pgIdForTenant(tenantId);
    final name = tenantName(tenantId);
    _notify(
      settled ? managerSettled : managerPartial,
      settled
          ? '${inr(amount)} from $name marked as received.'
          : '${inr(amount)} from $name · ${inr(remaining)} balance remaining.',
      NotificationType.payment,
      scope: NotificationScope.managers,
      pgId: pgId,
      tenantId: tenantId,
      relatedEntityId: first.id,
    );
    _notify(
      settled ? tenantSettled : tenantPartial,
      !settled
          ? '${inr(amount)} received · ${inr(remaining)} still due.'
          : touched.length == 1
              ? 'Your ${formatMonthName(first.period)} rent of ${inr(first.amount)} is settled.'
              : '${inr(amount)} received · ${touched.length} months settled.',
      NotificationType.payment,
      scope: NotificationScope.tenant,
      tenantId: tenantId,
      pgId: pgId,
      relatedEntityId: first.id,
    );
  }

  /// Records a confirmed UPI submission: its amount goes to the due it was
  /// paid against, any extra to the tenant's other dues. Completes with
  /// false when the books could not be saved.
  Future<bool> _markConfirmedPaid(UpiSubmission s) {
    final touched = _applyReceipt(
        tenantId: s.tenantId,
        amount: s.amount,
        method: 'UPI',
        dueId: s.paymentId);
    _notifyReceipt(s.tenantId, s.amount, touched,
        managerSettled: 'Rent received',
        managerPartial: 'Part payment received',
        tenantSettled: 'Payment confirmed',
        tenantPartial: 'Payment confirmed');
    return _persist({'payments', 'notifications'});
  }

  /// Records money received from a tenant against their unsettled dues,
  /// oldest month first, so arrears are cleared before the current month.
  /// Only money beyond every due creates a new (advance) row.
  void recordPayment(
      {required String tenantId, required int amount, required String method}) {
    if (amount <= 0) return;
    final touched =
        _applyReceipt(tenantId: tenantId, amount: amount, method: method);
    _notifyReceipt(tenantId, amount, touched,
        managerSettled: 'Payment recorded',
        managerPartial: 'Part payment recorded',
        tenantSettled: 'Rent received',
        tenantPartial: 'Part payment received');
    _persist({'payments', 'notifications'});
    _audit('payment_recorded',
        entityType: 'payment',
        entityId: touched.first.id,
        after: {'tenant_id': tenantId, 'amount': amount, 'method': method});
  }

  void addMaintenanceRequest(
      {required String title,
      required String roomId,
      required String category,
      required Priority priority,
      String? photo}) {
    final request = MaintenanceRequest(
      id: _id('m'),
      roomId: roomId,
      title: title,
      category: category,
      status: MaintenanceStatus.open,
      priority: priority,
      createdAt: DateTime.now(),
      photo: photo,
      customerId: customerId,
    );
    maintenance.insert(0, request);
    // Managers are alerted to the new request; it also appears in the raising
    // tenant's own "My requests" list.
    _notify('New maintenance request', '$title · Room ${roomNumber(roomId)}',
        NotificationType.maintenance,
        scope: NotificationScope.managers,
        pgId: _pgIdForRoom(roomId),
        relatedEntityId: request.id);
    _persist({'maintenance', 'notifications'});
  }

  void setMaintenanceStatus(String id, MaintenanceStatus status,
      {String? assignee}) {
    final i = maintenance.indexWhere((e) => e.id == id);
    if (i == -1) return;
    final trimmed = assignee?.trim();
    final request = maintenance[i] = maintenance[i].copyWith(
        status: status, assignee: (trimmed?.isEmpty ?? true) ? null : trimmed);
    final pgId = _pgIdForRoom(request.roomId);
    // Notify each tenant living in that room — and only them.
    for (final tenant in _tenantsInRoom(request.roomId)) {
      _notify(
          'Maintenance updated',
          '${request.title} is now ${status.label.toLowerCase()}.',
          NotificationType.maintenance,
          scope: NotificationScope.tenant,
          tenantId: tenant.id,
          pgId: pgId,
          relatedEntityId: request.id);
    }
    _persist({'maintenance', 'notifications'});
  }

  void addVisitor(
      {required String name,
      required String tenantId,
      required String purpose}) {
    final visitor = Visitor(
      id: _id('v'),
      tenantId: tenantId,
      name: name,
      purpose: purpose,
      status: VisitorStatus.awaitingApproval,
      expectedAt: DateTime.now(),
      customerId: customerId,
    );
    visitors.insert(0, visitor);
    // Managers are alerted to approve; the visit is private to this tenant.
    _notify(
        'Visitor awaiting approval',
        '$name · $purpose visit for ${tenantName(tenantId)}.',
        NotificationType.visitor,
        scope: NotificationScope.managers,
        pgId: _pgIdForTenant(tenantId),
        tenantId: tenantId,
        relatedEntityId: visitor.id);
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
    _notify(title, '${visitor.name} · ${visitor.purpose} visit.',
        NotificationType.visitor,
        scope: NotificationScope.tenant,
        tenantId: visitor.tenantId,
        pgId: _pgIdForTenant(visitor.tenantId),
        relatedEntityId: visitor.id);
    _persist({'visitors', 'notifications'});
  }

  /// Publishes an announcement. [pgId] null targets every property (all
  /// tenants); a value targets that property only. [sendPush] decides
  /// whether a push is attempted.
  void publishAnnouncement(String title, String body,
      {String? pgId, bool sendPush = true}) {
    final announcement = Announcement(
      id: _id('a'),
      title: title,
      body: body,
      author: '$displayName, ${role.label}',
      postedAt: DateTime.now(),
      pgId: pgId,
      customerId: customerId,
    );
    announcements.insert(0, announcement);
    _notify('New announcement', title, NotificationType.announcement,
        scope: NotificationScope.everyone,
        pgId: pgId,
        relatedEntityId: announcement.id,
        push: sendPush);
    _persist({'announcements', 'notifications'});
  }

  /// Announcements the current session may see: workspace-wide ones plus any
  /// targeted at the relevant property. Tenants only ever see their own PG's.
  List<Announcement> get visibleAnnouncements {
    if (role == UserRole.tenant) {
      final myPg = roomById(currentTenant?.roomId ?? '')?.pgId;
      return announcements
          .where((a) => a.pgId == null || a.pgId == myPg)
          .toList();
    }
    final pgId = activePg?.id;
    return announcements
        .where((a) => a.pgId == null || a.pgId == pgId)
        .toList();
  }
}

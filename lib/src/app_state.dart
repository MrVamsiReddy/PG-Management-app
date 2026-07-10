import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthException,
        FileOptions,
        FunctionException,
        SupabaseClient,
        User,
        UserAttributes;

import 'access.dart';
import 'format.dart';
import 'l10n.dart';
import 'models.dart';
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
typedef InviteResult = ({
  String? error,
  String? tempPassword,
  String? token,
  DateTime? expiresAt,
  String? email
});

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
    _pgRepo = SupabaseRepository<Pg>(client, 'pgs',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: Pg.fromMap,
        toMap: (e) => e.toMap());
    _roomRepo = SupabaseRepository<Room>(client, 'rooms',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: Room.fromMap,
        toMap: (e) => e.toMap());
    _tenantRepo = SupabaseRepository<Tenant>(client, 'tenants',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: Tenant.fromMap,
        toMap: (e) => e.toMap());
    _paymentRepo = SupabaseRepository<Payment>(client, 'payments',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: Payment.fromMap,
        toMap: (e) => e.toMap());
    _maintenanceRepo = SupabaseRepository<MaintenanceRequest>(
        client, 'maintenance',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: MaintenanceRequest.fromMap,
        toMap: (e) => e.toMap());
    _visitorRepo = SupabaseRepository<Visitor>(client, 'visitors',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: Visitor.fromMap,
        toMap: (e) => e.toMap());
    _announcementRepo = SupabaseRepository<Announcement>(
        client, 'announcements',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: Announcement.fromMap,
        toMap: (e) => e.toMap());
    _attendanceRepo = SupabaseRepository<AttendanceRecord>(client, 'attendance',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: AttendanceRecord.fromMap,
        toMap: (e) => e.toMap());
    _utilityRepo = SupabaseRepository<UtilityBill>(client, 'utilities',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: UtilityBill.fromMap,
        toMap: (e) => e.toMap());
    _notificationRepo = SupabaseRepository<AppNotification>(
        client, 'notifications',
        workspaceOwnerId: workspaceOwnerId,
        fromMap: AppNotification.fromMap,
        toMap: (e) => e.toMap());
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
    pgs = await _pgRepo?.loadAll() ?? [];
    rooms = await _roomRepo?.loadAll() ?? [];
    tenants = await _tenantRepo?.loadAll() ?? [];
    payments = await _paymentRepo?.loadAll() ?? [];
    maintenance = await _maintenanceRepo?.loadAll() ?? [];
    visitors = await _visitorRepo?.loadAll() ?? [];
    announcements = await _announcementRepo?.loadAll() ?? [];
    attendance = await _attendanceRepo?.loadAll() ?? [];
    utilities = await _utilityRepo?.loadAll() ?? [];
    notifications = await _notificationRepo?.loadAll() ?? [];
  }

  /// Saves only the collections that changed. Persistence is best-effort: a
  /// transient cloud error surfaces the in-memory change without corrupting
  /// state, and there is no local fallback store to write to.
  Future<void> _persist(Set<String> keys) async {
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
    try {
      await Future.wait(saves);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refresh() async {
    final user = supabaseOrNull?.auth.currentUser;
    if (user != null) {
      final gate = await _fetchAccessGate(user);
      if (gate.error != null) {
        await logout();
        authNotice = gate.error;
        notifyListeners();
        return;
      }
    }
    try {
      await _loadAll();
    } catch (_) {}
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

  Future<List<String>> loadCustomerPgNames(String customerId) async {
    final client = supabaseOrNull;
    if (client == null) return [];
    try {
      final rows =
          await client.from('pgs').select('name').eq('customer_id', customerId);
      return (rows as List).map((r) => r['name'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    final client = supabaseOrNull;
    if (client == null) return 'code:network';
    try {
      // redirectTo returns the reset link to the app, which then fires a
      // passwordRecovery event and shows the set-password screen.
      await client.auth.resetPasswordForEmail(email, redirectTo: appWebUrl);
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
      try {
        await client.auth
            .signInWithPassword(email: email, password: currentPassword);
      } on AuthException {
        return 'code:bad_credentials'; // wrong temporary password
      } catch (_) {
        return 'code:network';
      }
    }
    try {
      await client.auth.updateUser(UserAttributes(
          password: password, data: {'must_change_password': false}));
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
    } on AuthException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not update the password. Check your connection.';
    }
  }

  Future<void> restoreCloudSession() async {
    final user = supabaseOrNull?.auth.currentSession?.user;
    if (user == null) return;
    try {
      final error = await _enterCloud(user);
      if (error != null) {
        authNotice = error;
        try {
          await supabaseOrNull?.auth.signOut();
        } catch (_) {}
        notifyListeners();
      }
    } catch (_) {}
  }

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
            .select('status')
            .eq('id', linkedCustomer)
            .maybeSingle();
      }
    } catch (_) {
      return (role: null, customerId: null, error: null);
    }
    return evaluateProfileAccess(profile: profile, customer: customer);
  }

  Future<String?> _enterCloud(User user, {LoginPortal? portal}) async {
    final client = supabaseOrNull!;

    final gate = await _fetchAccessGate(user);
    if (gate.error != null) return gate.error;

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
    } catch (_) {}

    UserRole resolvedRole;
    if (linkedTenantId != null) {
      resolvedRole = UserRole.tenant;
    } else {
      final metaRole = user.userMetadata?['role'] as String?;
      resolvedRole = UserRole.values
          .firstWhere((e) => e.name == metaRole, orElse: () => UserRole.owner);
    }
    if (gate.role != null) resolvedRole = gate.role!;

    if (portal != null) {
      final mismatch = portalError(resolvedRole, portal);
      if (mismatch != null) return mismatch;
    }

    // A tenant still on their temporary password is mid-invite: an expired
    // or revoked invite blocks the sign-in (enforced server-side too — the
    // Edge Function owns all lifecycle transitions).
    if (resolvedRole == UserRole.tenant &&
        user.userMetadata?['must_change_password'] == true) {
      final inviteError = await _inviteLoginError(client);
      if (inviteError != null) return inviteError;
    }

    role = resolvedRole;
    currentTenantId = linkedTenantId ?? '';
    _cloudName = user.userMetadata?['full_name'] as String?;
    accountEmail = user.email;
    mustChangePassword = user.userMetadata?['must_change_password'] == true;
    authNotice = null;
    _workspaceOwnerId = workspaceOwnerId;
    _resolvedCustomerId = gate.customerId;
    _useSupabaseRepos(workspaceOwnerId);
    await _loadAll();
    await _ensureMonthlyDuesAtStartup();
    await loadSubmissions();
    isLoggedIn = true;
    notifyListeners();
    return null;
  }

  /// Creates the tenant's login via the `invite` Edge Function: a temporary
  /// password (forced change at first sign-in), a one-time invite token with
  /// an expiry, and the workspace link. Tenants can never self-register.
  /// [tempPassword] is null when the email already had its own password.
  Future<InviteResult> inviteTenant(
          {required String tenantId, required String email}) =>
      _inviteAction('create', tenantId: tenantId, email: email);

  /// Supersedes the previous invite (status → resent) and issues a fresh
  /// token; the temporary password is regenerated only while the tenant has
  /// never set their own password.
  Future<InviteResult> resendInvite({required String tenantId}) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) {
      return (
        error: 'Sign in with a cloud account to invite tenants.',
        tempPassword: null,
        token: null,
        expiresAt: null,
        email: null
      );
    }
    String? email;
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
    if (email == null) {
      return (
        error:
            'No previous invite for this tenant — use "Invite to app" first.',
        tempPassword: null,
        token: null,
        expiresAt: null,
        email: null
      );
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
      return (
        error: 'Sign in with a cloud account to invite tenants.',
        tempPassword: null,
        token: null,
        expiresAt: null,
        email: null
      );
    }
    final address = email?.trim().toLowerCase();
    final tenant = tenantById(tenantId);
    final room = roomById(tenant?.roomId ?? '');
    try {
      final result = await client.functions.invoke('invite', body: {
        'action': action,
        'tenantId': tenantId,
        if (address != null) 'email': address,
        'tenantName': tenant?.name ?? '',
        'pgId': room?.pgId ?? '',
        'roomId': tenant?.roomId ?? '',
        'bedLabel': tenant?.bed ?? '',
      });
      final data = result.data;
      if (data is Map && data['ok'] == true) {
        return (
          error: null,
          tempPassword: data['tempPassword'] as String?,
          token: data['token'] as String?,
          expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? ''),
          email: address,
        );
      }
      return (
        error:
            inviteActionMessage(data is Map ? data['error'] as String? : null),
        tempPassword: null,
        token: null,
        expiresAt: null,
        email: null
      );
    } on FunctionException catch (e) {
      final details = e.details;
      return (
        error: inviteActionMessage(
            details is Map ? details['error'] as String? : null),
        tempPassword: null,
        token: null,
        expiresAt: null,
        email: null
      );
    } catch (_) {
      return (
        error: 'Could not reach the invite service. Check your connection.',
        tempPassword: null,
        token: null,
        expiresAt: null,
        email: null
      );
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

  Future<void> loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_langKey);
      if (code != null) {
        language = AppLanguage.fromCode(code);
        notifyListeners();
      }
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

  void setPushEnabled(bool value) {
    pushEnabled = value;
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

  List<Visitor> get pgVisitors {
    final ids = _pgTenantIds;
    return visitors.where((v) => ids.contains(v.tenantId)).toList();
  }

  int get pgDueAmount => pgPayments.fold(0, (sum, e) => sum + e.balance);

  int get pgCollectedAmount {
    final now = DateTime.now();
    return pgPayments
        .where((e) => e.period.year == now.year && e.period.month == now.month)
        .fold(0, (sum, e) => sum + e.collected);
  }

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
    tenants[i] = tenants[i].copyWith(kycDoc: base64);
    await _persist({'tenants'});
  }

  // ---- Aggregates ----

  int get totalBeds => pgs.fold(0, (sum, e) => sum + e.beds);
  int get occupiedBeds => pgs.fold(0, (sum, e) => sum + e.occupied);

  /// Outstanding rent across all payments — includes the unpaid balance of
  /// partially-settled dues, not just untouched ones.
  int get dueAmount => payments.fold(0, (sum, e) => sum + e.balance);

  int get collectedAmount {
    final now = DateTime.now();
    return payments
        .where((e) => e.period.year == now.year && e.period.month == now.month)
        .fold(0, (sum, e) => sum + e.collected);
  }

  List<({DateTime month, int total})> monthlyRevenue(
      {int months = 6, List<Payment>? source}) {
    final now = DateTime.now();
    final pool = source ?? payments;
    return List.generate(months, (i) {
      final month = DateTime(now.year, now.month - (months - 1 - i));
      final total = pool
          .where((e) =>
              e.period.year == month.year && e.period.month == month.month)
          .fold(0, (sum, e) => sum + e.collected);
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
    if (push) _pushToWorkspace(title, body, scope: scope, tenantId: tenantId);
  }

  /// Fire-and-forget push via the `push` Edge Function. Scope and tenant are
  /// passed so the function can target the right devices; push failures never
  /// block the action itself.
  void _pushToWorkspace(String title, String body,
      {required NotificationScope scope, String? tenantId}) {
    final client = supabaseOrNull;
    final owner = _workspaceOwnerId;
    if (client == null || owner == null || !pushEnabled) return;
    client.functions.invoke('push', body: {
      'workspaceOwnerId': owner,
      'title': title,
      'body': body,
      'scope': scope.name,
      if (tenantId != null) 'tenantId': tenantId,
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
    notifications = notifications
        .map((n) => visibleIds.contains(n.id) ? n.copyWith(read: true) : n)
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

  void addRoom(Room room) {
    rooms.add(room.copyWith(customerId: room.customerId ?? customerId));
    _persist({'rooms'});
    _audit('room_created',
        entityType: 'room',
        entityId: room.id,
        after: {'number': room.number, 'beds': room.beds});
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

  String? removeRoom(String roomId) {
    final i = rooms.indexWhere((r) => r.id == roomId);
    if (i == -1) return 'Room not found.';
    if (_roomOccupancy(rooms[i]) > 0) {
      return 'Cannot remove a room with active tenants.';
    }
    final removed = rooms.removeAt(i);
    _persist({'rooms'});
    _audit('room_removed',
        entityType: 'room',
        entityId: roomId,
        before: {'number': removed.number, 'beds': removed.beds});
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
    _persist({'rooms'});
    _audit('rent_changed',
        entityType: 'room',
        entityId: roomId,
        before: {'rent': before},
        after: {'rent': rent});
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
      required String roomId,
      required String bed,
      String? kycDoc}) {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final cleanBed = bed.trim();
    if (cleanName.isEmpty) return 'Enter the tenant\'s name.';
    if (cleanPhone.replaceAll(RegExp(r'[^0-9]'), '').length < 10) {
      return 'Enter a valid 10-digit phone number.';
    }
    if (cleanBed.isEmpty) return 'Enter a bed label.';

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

  /// The current tenant's next unsettled payment (due or partially paid).
  Payment? get tenantDuePayment => _firstOrNull(payments,
      (p) => p.tenantId == currentTenantId && p.status != PaymentStatus.paid);

  /// The signed-in tenant's own payments — never anyone else's.
  List<Payment> get tenantPayments =>
      payments.where((p) => p.tenantId == currentTenantId).toList();

  /// Rent collection as spreadsheet-ready CSV (newest first, like the UI).
  String paymentsCsv() {
    String cell(String value) => '"${value.replaceAll('"', '""')}"';
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

  /// Creates this month's Due payment for tenants who don't already have a
  /// payment row for the month (any status counts, so a partial or paid entry
  /// blocks a duplicate). Deterministic ids keep it idempotent across devices.
  /// Pass [onlyTenantId] to generate a single tenant's due (used for tenant
  /// sessions, which display but don't persist owner-wide data).
  /// Returns true if anything was added.
  bool generateMonthlyDues({String? onlyTenantId}) {
    final now = DateTime.now();
    final period = DateTime(now.year, now.month);
    final fifth = DateTime(now.year, now.month, 5);
    final dueDate =
        now.isBefore(fifth) ? fifth : now.add(const Duration(days: 3));
    var added = false;
    for (final tenant in tenants) {
      if (onlyTenantId != null && tenant.id != onlyTenantId) continue;
      final exists = payments.any((p) =>
          p.tenantId == tenant.id &&
          p.period.year == period.year &&
          p.period.month == period.month);
      if (exists) continue;
      final rent = roomById(tenant.roomId)?.rent ?? 0;
      if (rent <= 0) continue;
      payments.insert(
          0,
          Payment(
            id: 'pay-${period.year}-${period.month}-${tenant.id}',
            tenantId: tenant.id,
            period: period,
            amount: rent,
            status: PaymentStatus.due,
            dueDate: dueDate,
            customerId: customerId,
          ));
      added = true;
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
          return 'paid';
        case UpiStatus.rejected:
          return 'rejected';
      }
    }
    return p.isOverdue ? 'overdue' : 'due';
  }

  /// A tenant may submit when the due is unpaid and not already awaiting
  /// confirmation (a rejected submission can be resubmitted).
  bool canSubmit(Payment p) {
    if (p.status == PaymentStatus.paid) return false;
    final sub = latestSubmissionFor(p.id);
    return sub == null || sub.status == UpiStatus.rejected;
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

  Future<String?> saveUpiSettings(String pgId,
      {required String upiId,
      required String payeeName,
      required bool enabled}) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) return 'Sign in to save UPI settings.';
    try {
      await client.from('pg_upi_settings').upsert({
        'owner_id': workspaceId,
        'pg_id': pgId,
        'upi_id': upiId.trim(),
        'payee_name': payeeName.trim(),
        'enabled': enabled,
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
      Uint8List? screenshot}) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) return 'Sign in to submit a payment.';
    final ref = utr.trim();
    if (ref.length < 6) return 'Enter the 12-digit UPI reference (UTR).';
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
          path = null;
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
        'amount': payment.balance,
        'utr': ref,
        'screenshot_path': path,
      });
      _audit('payment_submitted',
          entityType: 'payment',
          entityId: payment.id,
          after: {'utr': ref, 'amount': payment.balance});
      await loadSubmissions();
      notifyListeners();
      return null;
    } catch (_) {
      return 'Could not submit the payment. Check your connection.';
    }
  }

  /// Owner-side: another submission in this workspace already used the same
  /// amount + UTR. A warning, not a block.
  UpiSubmission? duplicateOf(UpiSubmission s) => _firstOrNull(submissions,
      (o) => o.id != s.id && o.utr == s.utr && o.amount == s.amount);

  List<UpiSubmission> get pendingSubmissions => submissions
      .where((s) => s.status == UpiStatus.pendingConfirmation)
      .toList();

  Future<String?> confirmSubmission(UpiSubmission s) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) return 'Sign in to confirm payments.';
    try {
      await client.from('upi_submissions').update({
        'status': 'confirmed',
        'confirmed_by': client.auth.currentUser?.id,
        'confirmed_at': DateTime.now().toIso8601String(),
      }).eq('id', s.id);
      _markConfirmedPaid(s);
      _audit('payment_confirmed',
          entityType: 'payment',
          entityId: s.paymentId,
          after: {'utr': s.utr, 'amount': s.amount});
      await loadSubmissions();
      notifyListeners();
      return null;
    } catch (_) {
      return 'Could not confirm the payment. Check your connection.';
    }
  }

  Future<String?> rejectSubmission(UpiSubmission s, String reason) async {
    final client = supabaseOrNull;
    if (client == null || !isLoggedIn) return 'Sign in to reject payments.';
    if (reason.trim().isEmpty) return 'Enter a reason for rejecting.';
    try {
      await client.from('upi_submissions').update({
        'status': 'rejected',
        'rejection_reason': reason.trim(),
      }).eq('id', s.id);
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

  void _markConfirmedPaid(UpiSubmission s) {
    final i = payments.indexWhere((p) => p.id == s.paymentId);
    if (i == -1) return;
    final paid = payments[i] = payments[i].copyWith(
        status: PaymentStatus.paid,
        paidAmount: payments[i].amount,
        paidDate: DateTime.now(),
        method: 'UPI');
    final pgId = _pgIdForTenant(paid.tenantId);
    _notify(
        'Rent received',
        '${inr(paid.amount)} received from ${tenantName(paid.tenantId)}.',
        NotificationType.payment,
        scope: NotificationScope.managers,
        pgId: pgId,
        tenantId: paid.tenantId,
        relatedEntityId: paid.id);
    _notify(
        'Payment confirmed',
        'Your ${formatMonthName(paid.period)} rent of ${inr(paid.amount)} is confirmed.',
        NotificationType.payment,
        scope: NotificationScope.tenant,
        tenantId: paid.tenantId,
        pgId: pgId,
        relatedEntityId: paid.id);
    _persist({'payments', 'notifications'});
  }

  /// Records money received from a tenant. When an unsettled due exists for
  /// the current month it is settled in place (fully -> paid, otherwise
  /// -> partial), so no duplicate row is created. Only advance payments,
  /// adjustments, or payments with no matching due create a new row.
  void recordPayment(
      {required String tenantId, required int amount, required String method}) {
    if (amount <= 0) return;
    final now = DateTime.now();
    final period = DateTime(now.year, now.month);
    final i = payments.indexWhere((p) =>
        p.tenantId == tenantId &&
        p.status != PaymentStatus.paid &&
        p.period.year == period.year &&
        p.period.month == period.month);

    final Payment payment;
    final bool settled;
    if (i != -1) {
      final existing = payments[i];
      final collected = existing.collected + amount;
      settled = collected >= existing.amount;
      payment = payments[i] = existing.copyWith(
        status: settled ? PaymentStatus.paid : PaymentStatus.partial,
        paidAmount: settled ? existing.amount : collected,
        paidDate: now,
        method: method,
      );
    } else {
      // Advance / adjustment / no matching due -> a new standalone paid row.
      settled = true;
      payment = Payment(
        id: _id('pay'),
        tenantId: tenantId,
        period: period,
        amount: amount,
        status: PaymentStatus.paid,
        paidAmount: amount,
        dueDate: DateTime(now.year, now.month, 5),
        paidDate: now,
        method: method,
        customerId: customerId,
      );
      payments.insert(0, payment);
    }

    final pgId = _pgIdForTenant(tenantId);
    final name = tenantName(tenantId);
    _notify(
      settled ? 'Payment recorded' : 'Part payment recorded',
      settled
          ? '${inr(amount)} from $name marked as received.'
          : '${inr(amount)} from $name · ${inr(payment.balance)} balance remaining.',
      NotificationType.payment,
      scope: NotificationScope.managers,
      pgId: pgId,
      tenantId: tenantId,
      relatedEntityId: payment.id,
    );
    _notify(
      settled ? 'Rent received' : 'Part payment received',
      settled
          ? 'Your ${formatMonthName(payment.period)} rent of ${inr(payment.amount)} is settled.'
          : '${inr(amount)} received · ${inr(payment.balance)} still due.',
      NotificationType.payment,
      scope: NotificationScope.tenant,
      tenantId: tenantId,
      pgId: pgId,
      relatedEntityId: payment.id,
    );
    _persist({'payments', 'notifications'});
    _audit('payment_recorded',
        entityType: 'payment',
        entityId: payment.id,
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
  /// tenants); a value targets that property only. [sendPush] and the global
  /// [pushEnabled] preference together decide whether a push is attempted.
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

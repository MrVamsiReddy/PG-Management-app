import 'package:supabase_flutter/supabase_flutter.dart';

/// Storage seam between [AppState] and Supabase. The app only ever talks to
/// this interface; the cloud is the single source of truth — there is no local
/// store or offline cache.
abstract class Repository<T> {
  Future<List<T>> loadAll();
  Future<void> saveAll(List<T> items);
}

/// Cloud store: one JSONB row per (workspace, collection) in the `app_data`
/// table. [workspaceOwnerId] is the account that owns the data — the signed-in
/// user for owners, or the inviting owner's id for linked tenants. Row-level
/// security enforces who may touch what (see supabase/schema.sql).
class SupabaseRepository<T> implements Repository<T> {
  SupabaseRepository(this.client, this.key,
      {required this.workspaceOwnerId,
      required this.fromMap,
      required this.toMap});

  final SupabaseClient client;
  final String key;
  final String workspaceOwnerId;
  final T Function(Map<String, dynamic> map) fromMap;
  final Map<String, dynamic> Function(T item) toMap;

  /// The collection as this device last loaded or saved it. A save sends it
  /// along so the server applies only this device's own changes.
  List<Map<String, dynamic>> _base = const [];

  @override
  Future<List<T>> loadAll() async {
    final row = await client
        .from('app_data')
        .select('data')
        .eq('owner_id', workspaceOwnerId)
        .eq('key', key)
        .maybeSingle();
    final items = parseItems(row?['data'] as List? ?? const [], fromMap);
    // The base holds only what this app version understood. An item it
    // couldn't parse (e.g. written by a newer version) is then neither in the
    // base nor in a save, so `owner_save` leaves it alone instead of reading
    // its absence as a delete.
    _base = items.map(toMap).toList();
    return items;
  }

  /// Like [saveAll], through [function]: a server function taking the same
  /// owner/key/base/items arguments plus [extra], for a save that must
  /// succeed or fail together with another change (e.g. confirming a UPI
  /// submission and recording its money, 018_payments.sql).
  Future<void> saveAllVia(
      String function, List<T> items, Map<String, dynamic> extra) async {
    final base = _base;
    final mine = items.map(toMap).toList();
    _base = mine;
    try {
      await client.rpc(function, params: {
        'p_owner': workspaceOwnerId,
        'p_key': key,
        'p_base': base,
        'p_items': mine,
        ...extra,
      });
    } catch (_) {
      _base = base;
      rethrow;
    }
  }

  /// Merges instead of replacing: `owner_save` applies the items this device
  /// added, edited or deleted since [_base] onto the stored list under a row
  /// lock, so a concurrent save from another device or a tenant is kept
  /// (supabase/015_security_hardening.sql).
  @override
  Future<void> saveAll(List<T> items) async {
    final base = _base;
    final mine = items.map(toMap).toList();
    _base = mine;
    try {
      await client.rpc('owner_save', params: {
        'p_owner': workspaceOwnerId,
        'p_key': key,
        'p_base': base,
        'p_items': mine,
      });
    } catch (_) {
      _base = base;
      rethrow;
    }
  }
}

/// Parses stored items, skipping any that don't match the model, so one bad
/// row can't make the whole workspace fail to load.
List<T> parseItems<T>(
    List<dynamic> data, T Function(Map<String, dynamic>) fromMap) {
  final items = <T>[];
  for (final e in data) {
    try {
      items.add(fromMap(Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      // Malformed item: leave it out of the in-memory list.
    }
  }
  return items;
}

/// Tenant view of the owner's workspace. Tenants have no direct access to
/// `app_data`: reads go through the `tenant_collection` RPC, which returns
/// only the items this tenant may see, and writes through `tenant_save`,
/// which merges the tenant's own changes into the stored collection on the
/// server (see supabase/014_tenant_isolation.sql). Collections a tenant may
/// not write are never sent.
class TenantRepository<T> implements Repository<T> {
  TenantRepository(this.client, this.key,
      {required this.workspaceOwnerId,
      required this.fromMap,
      required this.toMap});

  /// Collections the server accepts tenant writes for.
  static const writableKeys = {
    'tenants',
    'maintenance',
    'visitors',
    'attendance',
    'notifications',
  };

  final SupabaseClient client;
  final String key;
  final String workspaceOwnerId;
  final T Function(Map<String, dynamic> map) fromMap;
  final Map<String, dynamic> Function(T item) toMap;

  @override
  Future<List<T>> loadAll() async {
    final data = await client.rpc('tenant_collection',
        params: {'p_owner': workspaceOwnerId, 'p_key': key});
    return parse(data as List? ?? const []);
  }

  /// Parses this collection out of a `tenant_workspace` result.
  List<T> parse(List<dynamic> data) => parseItems(data, fromMap);

  @override
  Future<void> saveAll(List<T> items) async {
    if (!writableKeys.contains(key)) return;
    await client.rpc('tenant_save', params: {
      'p_owner': workspaceOwnerId,
      'p_key': key,
      'p_items': items.map(toMap).toList(),
    });
  }
}

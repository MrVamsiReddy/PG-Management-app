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

  @override
  Future<List<T>> loadAll() async {
    final row = await client
        .from('app_data')
        .select('data')
        .eq('owner_id', workspaceOwnerId)
        .eq('key', key)
        .maybeSingle();
    final data = row?['data'] as List? ?? const [];
    return data
        .map((e) => fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<void> saveAll(List<T> items) async {
    await client.from('app_data').upsert({
      'owner_id': workspaceOwnerId,
      'key': key,
      'data': items.map(toMap).toList(),
    }, onConflict: 'owner_id,key');
  }
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
    return (data as List? ?? const [])
        .map((e) => fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

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

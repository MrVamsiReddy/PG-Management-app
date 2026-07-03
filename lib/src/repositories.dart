import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Storage seam between [AppState] and any backend. The app only ever talks
/// to this interface; swapping Hive for a remote store means providing a new
/// implementation, not touching screens or state logic.
abstract class Repository<T> {
  Future<List<T>> loadAll();
  Future<void> saveAll(List<T> items);
}

class HiveRepository<T> implements Repository<T> {
  HiveRepository(this.box, this.key, {required this.fromMap, required this.toMap});

  final Box<dynamic> box;
  final String key;
  final T Function(Map<String, dynamic> map) fromMap;
  final Map<String, dynamic> Function(T item) toMap;

  @override
  Future<List<T>> loadAll() async {
    final raw = box.get(key, defaultValue: <dynamic>[]) as List;
    return raw.map((e) => fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<void> saveAll(List<T> items) => box.put(key, items.map(toMap).toList());
}

/// Cloud store: one JSONB row per (user, collection) in the `app_data` table,
/// mirroring the Hive layout. Row-level security limits every query to the
/// signed-in user's rows (see supabase/schema.sql).
class SupabaseRepository<T> implements Repository<T> {
  SupabaseRepository(this.client, this.key, {required this.fromMap, required this.toMap});

  final SupabaseClient client;
  final String key;
  final T Function(Map<String, dynamic> map) fromMap;
  final Map<String, dynamic> Function(T item) toMap;

  @override
  Future<List<T>> loadAll() async {
    final row = await client.from('app_data').select('data').eq('key', key).maybeSingle();
    final data = row?['data'] as List? ?? const [];
    return data.map((e) => fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<void> saveAll(List<T> items) async {
    await client.from('app_data').upsert({
      'owner_id': client.auth.currentUser!.id,
      'key': key,
      'data': items.map(toMap).toList(),
    }, onConflict: 'owner_id,key');
  }
}

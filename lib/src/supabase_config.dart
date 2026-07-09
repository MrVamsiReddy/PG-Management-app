import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase project coordinates. The publishable key is designed to ship in
/// client apps — data access is enforced server-side by row-level security
/// (see supabase/schema.sql). Never put the secret/service_role key here.
const supabaseUrl = 'https://trtinltbnuscjhswhfdp.supabase.co';
const supabasePublishableKey = 'sb_publishable_AbpcjS3ZRxowxBSdkvu5PA_Yto9Teob';

/// Public web build — shown in tenant invites.
const appWebUrl = 'https://mrvamsireddy.github.io/PG-Management-app/';

/// Always points at the newest published APK (GitHub release asset).
const apkDownloadUrl = 'https://github.com/MrVamsiReddy/PG-Management-app/releases/latest/download/PG-Management.apk';

/// Set by main() once Supabase.initialize succeeds. False in tests and when
/// offline at startup.
bool supabaseReady = false;

SupabaseClient? get supabaseOrNull => supabaseReady ? Supabase.instance.client : null;

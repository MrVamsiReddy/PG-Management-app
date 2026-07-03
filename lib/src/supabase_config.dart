import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase project coordinates. The publishable key is designed to ship in
/// client apps — data access is enforced server-side by row-level security
/// (see supabase/schema.sql). Never put the secret/service_role key here.
const supabaseUrl = 'https://trtinltbnuscjhswhfdp.supabase.co';
const supabasePublishableKey = 'sb_publishable_AbpcjS3ZRxowxBSdkvu5PA_Yto9Teob';

/// Public web build — shown in tenant invites.
const appWebUrl = 'https://mrvamsireddy.github.io/PG-Management-app/';

/// Set by main() once Supabase.initialize succeeds. Stays false in tests and
/// when offline at startup, in which case the app runs in local demo mode.
bool supabaseReady = false;

SupabaseClient? get supabaseOrNull => supabaseReady ? Supabase.instance.client : null;

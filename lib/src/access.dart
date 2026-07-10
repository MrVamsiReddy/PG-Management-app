library;

import 'app_state.dart' show UserRole;

enum LoginPortal {
  owner('Owner'),
  tenant('Tenant'),
  admin('Admin');

  const LoginPortal(this.label);
  final String label;
}

typedef AccessGate = ({UserRole? role, String? customerId, String? error});

AccessGate evaluateProfileAccess({
  required Map<String, dynamic>? profile,
  required Map<String, dynamic>? customer,
}) {
  if (profile == null) return (role: null, customerId: null, error: null);

  final isAdmin =
      profile['platform_admin'] == true || profile['role'] == 'admin';
  if (isAdmin) {
    return (
      role: UserRole.admin,
      customerId: profile['customer_id'] as String?,
      error: null
    );
  }

  final customerId = profile['customer_id'] as String?;
  if (customerId == null) {
    return (
      role: null,
      customerId: null,
      error:
          'This account is not linked to any PG business yet. Contact support.',
    );
  }
  if (customer == null || customer['status'] != 'enabled') {
    return (
      role: null,
      customerId: null,
      error:
          'This account has been disabled. Please contact your administrator.',
    );
  }
  final expiresAt = customer['expires_at'] as String?;
  if (expiresAt != null) {
    final expiry = DateTime.tryParse(expiresAt);
    if (expiry != null && DateTime.now().isAfter(expiry)) {
      return (
        role: null,
        customerId: null,
        error:
            'This subscription has expired. Please contact your administrator to renew.',
      );
    }
  }
  return (
    role: profile['role'] == 'tenant' ? UserRole.tenant : UserRole.owner,
    customerId: customerId,
    error: null,
  );
}

String adminSetupMessage(String? code) => switch (code) {
      'code:rate_limited' =>
        'Too many attempts. Please wait a few minutes and try again.',
      'code:key_expired' =>
        'The admin setup key has expired. Request a new key.',
      'code:invalid_key' => 'Invalid setup key.',
      'code:weak_password' => 'Use at least 8 characters for the password.',
      'code:missing_fields' => 'Please fill in all fields.',
      'code:create_failed' =>
        'Could not create the admin account. The email may already be in use.',
      'code:not_admin' => 'Only a platform admin can do this.',
      'code:email_in_use' => 'That owner email is already in use.',
      'code:unauthorized' => 'Please sign in again.',
      _ => 'Something went wrong. Please try again.',
    };

/// `code:*` errors returned by the `invite` Edge Function (Prompt 7).
String inviteActionMessage(String? code) => switch (code) {
      'code:invite_expired' =>
        'This invite has expired. Ask your PG owner to resend it.',
      'code:invite_revoked' =>
        'This invite was revoked. Ask your PG owner for a new invite.',
      'code:invite_used' =>
        'This invite was already used. Sign in with the password you set.',
      'code:invite_not_found' => 'No pending invite found for this tenant.',
      'code:missing_fields' => 'Please fill in all fields.',
      'code:unauthorized' => 'Please sign in again.',
      _ => 'Something went wrong. Please try again.',
    };

String? portalError(UserRole resolved, LoginPortal portal) {
  final matches = switch (portal) {
    LoginPortal.owner => resolved == UserRole.owner,
    LoginPortal.tenant => resolved == UserRole.tenant,
    LoginPortal.admin => resolved == UserRole.admin,
  };
  if (matches) return null;
  final actual = switch (resolved) {
    UserRole.owner => 'an owner',
    UserRole.tenant => 'a tenant',
    UserRole.admin => 'a platform admin',
  };
  final destination = switch (resolved) {
    UserRole.owner => 'Owner login',
    UserRole.tenant => 'Tenant login',
    UserRole.admin => 'Admin login',
  };
  return 'This is $actual account — please use the $destination instead. You have been signed out.';
}

/// The invite message an owner shares with a tenant (roadmap Prompt 7).
///
/// Pure so tests can assert its contents. Contains everything the tenant
/// needs: their email, the temporary password (only when one was just
/// generated — passwords are never redisplayed), the APK download link, the
/// tenant web login link, the one-time invite link and the password-change
/// instructions.
library;

import 'format.dart';
import 'supabase_config.dart';

/// The one-time invite link for a token (web login with the token attached).
String inviteLink(String token) => '$appWebUrl?invite=$token';

String buildInviteMessage({
  required String tenantName,
  required String pgName,
  required String email,
  String? tempPassword,
  String? inviteToken,
  DateTime? expiresAt,
}) {
  final firstName = tenantName.split(' ').first;
  final lines = <String>[
    'Hi $firstName! Your room at $pgName is now on PG Management.',
    '',
    'Download the app (Android): $apkDownloadUrl',
    'Or sign in on the web: $appWebUrl',
    if (inviteToken != null && inviteToken.isNotEmpty)
      'Your invite link: ${inviteLink(inviteToken)}',
    '',
  ];
  if (tempPassword != null) {
    lines.addAll([
      'Sign in with:',
      'Email: $email',
      'Temporary password: $tempPassword',
      '',
      'You will be asked to set your own password the first time you sign '
          'in. The temporary password stops working after that.',
    ]);
  } else {
    lines.addAll([
      'Sign in with your existing password using this email: $email',
      'You will see your room, rent and requests as soon as you sign in.',
    ]);
  }
  if (expiresAt != null) {
    lines.addAll(['', 'This invite expires on ${formatFullDate(expiresAt)}.']);
  }
  return lines.join('\n');
}

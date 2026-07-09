/// SaaS entity models mirroring supabase/004_saas_core.sql (roadmap Prompt 1).
///
/// These are the customer-scoped entities of the multi-tenant data model.
/// They are not wired into the UI yet — later roadmap steps (admin customer
/// management, PG setup wizard, invites, UPI confirmation) build on them.
/// Wire names match the SQL check constraints exactly.
///
/// The existing app models in models.dart map onto this schema as follows:
/// Pg→pgs, Room→rooms(+floors/beds), Tenant→tenants, Payment→payment_dues,
/// MaintenanceRequest→complaints, Announcement→notices, Visitor→visitors.
library;

enum CustomerStatus {
  enabled('enabled'),
  disabled('disabled');

  const CustomerStatus(this.wire);
  final String wire;
  static CustomerStatus fromWire(String? wire) => values
      .firstWhere((e) => e.wire == wire, orElse: () => CustomerStatus.enabled);
}

enum InviteStatus {
  pending('pending'),
  accepted('accepted'),
  expired('expired'),
  revoked('revoked');

  const InviteStatus(this.wire);
  final String wire;
  static InviteStatus fromWire(String? wire) => values
      .firstWhere((e) => e.wire == wire, orElse: () => InviteStatus.pending);
}

enum SubmissionStatus {
  pendingConfirmation('pending_confirmation'),
  confirmed('confirmed'),
  rejected('rejected');

  const SubmissionStatus(this.wire);
  final String wire;
  static SubmissionStatus fromWire(String? wire) =>
      values.firstWhere((e) => e.wire == wire,
          orElse: () => SubmissionStatus.pendingConfirmation);
}

/// A PG business account. Created only by the platform admin; every business
/// record in the system belongs to exactly one customer.
class Customer {
  const Customer({
    required this.id,
    required this.businessName,
    this.ownerName = '',
    this.ownerEmail = '',
    this.phone = '',
    this.status = CustomerStatus.enabled,
    this.plan = 'free',
    required this.createdAt,
    this.disabledAt,
  });

  final String id;
  final String businessName;
  final String ownerName;
  final String ownerEmail;
  final String phone;
  final CustomerStatus status;
  final String plan;
  final DateTime createdAt;
  final DateTime? disabledAt;

  bool get enabled => status == CustomerStatus.enabled;

  Map<String, dynamic> toMap() => {
        'id': id,
        'businessName': businessName,
        'ownerName': ownerName,
        'ownerEmail': ownerEmail,
        'phone': phone,
        'status': status.wire,
        'plan': plan,
        'createdAt': createdAt.toIso8601String(),
        'disabledAt': disabledAt?.toIso8601String(),
      };

  static Customer fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'] as String,
        businessName: map['businessName'] as String,
        ownerName: map['ownerName'] as String? ?? '',
        ownerEmail: map['ownerEmail'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        status: CustomerStatus.fromWire(map['status'] as String?),
        plan: map['plan'] as String? ?? 'free',
        createdAt: DateTime.parse(map['createdAt'] as String),
        disabledAt: map['disabledAt'] == null
            ? null
            : DateTime.parse(map['disabledAt'] as String),
      );
}

/// A login's identity row: role plus the customer it belongs to (null for
/// platform admins).
class Profile {
  const Profile({
    required this.id,
    this.customerId,
    this.role = 'owner',
    this.platformAdmin = false,
    this.fullName = '',
    this.phone = '',
  });

  final String id; // auth.users id
  final String? customerId;
  final String role; // 'admin' | 'owner' | 'tenant'
  final bool platformAdmin;
  final String fullName;
  final String phone;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'role': role,
        'platformAdmin': platformAdmin,
        'fullName': fullName,
        'phone': phone,
      };

  static Profile fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        customerId: map['customerId'] as String?,
        role: map['role'] as String? ?? 'owner',
        platformAdmin: map['platformAdmin'] as bool? ?? false,
        fullName: map['fullName'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
      );
}

class Floor {
  const Floor({
    required this.id,
    required this.customerId,
    required this.pgId,
    required this.number,
    this.name = '',
  });

  final String id;
  final String customerId;
  final String pgId;
  final int number;
  final String name;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'pgId': pgId,
        'number': number,
        'name': name
      };

  static Floor fromMap(Map<String, dynamic> map) => Floor(
        id: map['id'] as String,
        customerId: map['customerId'] as String,
        pgId: map['pgId'] as String,
        number: map['number'] as int,
        name: map['name'] as String? ?? '',
      );
}

class Bed {
  const Bed({
    required this.id,
    required this.customerId,
    required this.pgId,
    required this.roomId,
    required this.label,
    this.occupied = false,
  });

  final String id;
  final String customerId;
  final String pgId;
  final String roomId;
  final String label;
  final bool occupied;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'pgId': pgId,
        'roomId': roomId,
        'label': label,
        'occupied': occupied,
      };

  static Bed fromMap(Map<String, dynamic> map) => Bed(
        id: map['id'] as String,
        customerId: map['customerId'] as String,
        pgId: map['pgId'] as String,
        roomId: map['roomId'] as String,
        label: map['label'] as String,
        occupied: map['occupied'] as bool? ?? false,
      );
}

/// Rent by sharing type. History is preserved by inserting new rules with a
/// later [effectiveFrom] — existing dues keep their snapshotted amount.
class RentRule {
  const RentRule({
    required this.id,
    required this.customerId,
    required this.pgId,
    required this.sharingType,
    required this.amount,
    required this.effectiveFrom,
  });

  final String id;
  final String customerId;
  final String pgId;
  final int sharingType; // beds per room: 1 = single, 2 = double…
  final int amount;
  final DateTime effectiveFrom;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'pgId': pgId,
        'sharingType': sharingType,
        'amount': amount,
        'effectiveFrom': effectiveFrom.toIso8601String(),
      };

  static RentRule fromMap(Map<String, dynamic> map) => RentRule(
        id: map['id'] as String,
        customerId: map['customerId'] as String,
        pgId: map['pgId'] as String,
        sharingType: map['sharingType'] as int,
        amount: map['amount'] as int,
        effectiveFrom: DateTime.parse(map['effectiveFrom'] as String),
      );
}

class PgPaymentSettings {
  const PgPaymentSettings({
    required this.id,
    required this.customerId,
    required this.pgId,
    this.upiId = '',
    this.payeeName = '',
    this.upiEnabled = false,
  });

  final String id;
  final String customerId;
  final String pgId;
  final String upiId;
  final String payeeName;
  final bool upiEnabled;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'pgId': pgId,
        'upiId': upiId,
        'payeeName': payeeName,
        'upiEnabled': upiEnabled,
      };

  static PgPaymentSettings fromMap(Map<String, dynamic> map) =>
      PgPaymentSettings(
        id: map['id'] as String,
        customerId: map['customerId'] as String,
        pgId: map['pgId'] as String,
        upiId: map['upiId'] as String? ?? '',
        payeeName: map['payeeName'] as String? ?? '',
        upiEnabled: map['upiEnabled'] as bool? ?? false,
      );
}

/// A tenant's manual UPI payment proof. Only owner-side users may confirm or
/// reject; a tenant can never flip a due to paid.
class PaymentSubmission {
  const PaymentSubmission({
    required this.id,
    required this.customerId,
    required this.pgId,
    required this.tenantId,
    required this.dueId,
    required this.amount,
    required this.utr,
    this.note = '',
    this.status = SubmissionStatus.pendingConfirmation,
    this.rejectionReason,
    required this.submittedAt,
    this.confirmedBy,
    this.confirmedAt,
  });

  final String id;
  final String customerId;
  final String pgId;
  final String tenantId;
  final String dueId;
  final int amount;
  final String utr;
  final String note;
  final SubmissionStatus status;
  final String? rejectionReason;
  final DateTime submittedAt;
  final String? confirmedBy;
  final DateTime? confirmedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'pgId': pgId,
        'tenantId': tenantId,
        'dueId': dueId,
        'amount': amount,
        'utr': utr,
        'note': note,
        'status': status.wire,
        'rejectionReason': rejectionReason,
        'submittedAt': submittedAt.toIso8601String(),
        'confirmedBy': confirmedBy,
        'confirmedAt': confirmedAt?.toIso8601String(),
      };

  static PaymentSubmission fromMap(Map<String, dynamic> map) =>
      PaymentSubmission(
        id: map['id'] as String,
        customerId: map['customerId'] as String,
        pgId: map['pgId'] as String,
        tenantId: map['tenantId'] as String,
        dueId: map['dueId'] as String,
        amount: map['amount'] as int,
        utr: map['utr'] as String,
        note: map['note'] as String? ?? '',
        status: SubmissionStatus.fromWire(map['status'] as String?),
        rejectionReason: map['rejectionReason'] as String?,
        submittedAt: DateTime.parse(map['submittedAt'] as String),
        confirmedBy: map['confirmedBy'] as String?,
        confirmedAt: map['confirmedAt'] == null
            ? null
            : DateTime.parse(map['confirmedAt'] as String),
      );
}

class PaymentProofFile {
  const PaymentProofFile({
    required this.id,
    required this.customerId,
    required this.submissionId,
    required this.storagePath,
  });

  final String id;
  final String customerId;
  final String submissionId;

  /// payment-proofs/{customer_id}/{pg_id}/{tenant_id}/{due_id}/{filename}
  final String storagePath;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'submissionId': submissionId,
        'storagePath': storagePath,
      };

  static PaymentProofFile fromMap(Map<String, dynamic> map) => PaymentProofFile(
        id: map['id'] as String,
        customerId: map['customerId'] as String,
        submissionId: map['submissionId'] as String,
        storagePath: map['storagePath'] as String,
      );
}

class TenantInvite {
  const TenantInvite({
    required this.id,
    required this.customerId,
    required this.tenantId,
    required this.email,
    required this.token,
    this.status = InviteStatus.pending,
    required this.expiresAt,
    this.acceptedAt,
    this.revokedAt,
  });

  final String id;
  final String customerId;
  final String tenantId;
  final String email;
  final String token;
  final InviteStatus status;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime? revokedAt;

  bool get usable =>
      status == InviteStatus.pending && DateTime.now().isBefore(expiresAt);

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'tenantId': tenantId,
        'email': email,
        'token': token,
        'status': status.wire,
        'expiresAt': expiresAt.toIso8601String(),
        'acceptedAt': acceptedAt?.toIso8601String(),
        'revokedAt': revokedAt?.toIso8601String(),
      };

  static TenantInvite fromMap(Map<String, dynamic> map) => TenantInvite(
        id: map['id'] as String,
        customerId: map['customerId'] as String,
        tenantId: map['tenantId'] as String,
        email: map['email'] as String,
        token: map['token'] as String,
        status: InviteStatus.fromWire(map['status'] as String?),
        expiresAt: DateTime.parse(map['expiresAt'] as String),
        acceptedAt: map['acceptedAt'] == null
            ? null
            : DateTime.parse(map['acceptedAt'] as String),
        revokedAt: map['revokedAt'] == null
            ? null
            : DateTime.parse(map['revokedAt'] as String),
      );
}

/// Append-only audit trail. [customerId] is null for platform-level actions
/// (e.g. an admin creating a customer).
class AuditLog {
  const AuditLog({
    required this.id,
    this.customerId,
    required this.actorUserId,
    required this.actorRole,
    required this.action,
    this.entityType,
    this.entityId,
    this.beforeJson,
    this.afterJson,
    required this.createdAt,
  });

  final String id;
  final String? customerId;
  final String actorUserId;
  final String actorRole;
  final String action;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic>? beforeJson;
  final Map<String, dynamic>? afterJson;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'actorUserId': actorUserId,
        'actorRole': actorRole,
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'beforeJson': beforeJson,
        'afterJson': afterJson,
        'createdAt': createdAt.toIso8601String(),
      };

  static AuditLog fromMap(Map<String, dynamic> map) => AuditLog(
        id: map['id'] as String,
        customerId: map['customerId'] as String?,
        actorUserId: map['actorUserId'] as String,
        actorRole: map['actorRole'] as String,
        action: map['action'] as String,
        entityType: map['entityType'] as String?,
        entityId: map['entityId'] as String?,
        beforeJson: (map['beforeJson'] as Map?)?.cast<String, dynamic>(),
        afterJson: (map['afterJson'] as Map?)?.cast<String, dynamic>(),
        createdAt: DateTime.parse(map['createdAt'] as String),
      );
}

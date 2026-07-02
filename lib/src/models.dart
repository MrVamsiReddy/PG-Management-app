/// Typed domain models. Persisted as plain maps (Hive today, shaped to move
/// to a document store later), linked by IDs — never by display strings.
library;

enum PaymentStatus { due, paid }

enum MaintenanceStatus {
  open('Open'),
  inProgress('In progress'),
  resolved('Resolved');

  const MaintenanceStatus(this.label);
  final String label;
}

enum Priority {
  low('Low'),
  medium('Medium'),
  high('High');

  const Priority(this.label);
  final String label;
}

enum VisitorStatus {
  awaitingApproval('Awaiting approval'),
  inside('Inside'),
  checkedOut('Checked out'),
  declined('Declined');

  const VisitorStatus(this.label);
  final String label;
}

enum KycStatus {
  pending('Pending'),
  verified('Verified');

  const KycStatus(this.label);
  final String label;
}

enum AgreementStatus {
  awaitingSign('Awaiting sign'),
  signed('Signed');

  const AgreementStatus(this.label);
  final String label;
}

enum BillStatus {
  pendingReading('Pending reading'),
  generated('Generated');

  const BillStatus(this.label);
  final String label;
}

enum NotificationType { payment, visitor, maintenance, announcement }

class Pg {
  const Pg({
    required this.id,
    required this.name,
    required this.address,
    required this.beds,
    required this.occupied,
    required this.amenities,
    required this.rating,
  });

  final String id;
  final String name;
  final String address;
  final int beds;
  final int occupied;
  final String amenities;
  final double rating;

  Pg copyWith({String? name, String? address, int? beds, int? occupied, String? amenities, double? rating}) => Pg(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
        beds: beds ?? this.beds,
        occupied: occupied ?? this.occupied,
        amenities: amenities ?? this.amenities,
        rating: rating ?? this.rating,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'name': name, 'address': address, 'beds': beds,
        'occupied': occupied, 'amenities': amenities, 'rating': rating,
      };

  static Pg fromMap(Map<String, dynamic> map) => Pg(
        id: map['id'] as String,
        name: map['name'] as String,
        address: map['address'] as String,
        beds: map['beds'] as int,
        occupied: map['occupied'] as int,
        amenities: map['amenities'] as String,
        rating: (map['rating'] as num).toDouble(),
      );
}

class Room {
  const Room({
    required this.id,
    required this.pgId,
    required this.number,
    required this.floor,
    required this.beds,
    required this.occupied,
    required this.rent,
  });

  final String id;
  final String pgId;
  final String number;
  final int floor;
  final int beds;
  final int occupied;
  final int rent;

  String get type => switch (beds) { 1 => 'Single', 2 => 'Double sharing', _ => 'Triple sharing' };

  Room copyWith({int? occupied, int? rent}) => Room(
        id: id, pgId: pgId, number: number, floor: floor, beds: beds,
        occupied: occupied ?? this.occupied,
        rent: rent ?? this.rent,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'pgId': pgId, 'number': number, 'floor': floor,
        'beds': beds, 'occupied': occupied, 'rent': rent,
      };

  static Room fromMap(Map<String, dynamic> map) => Room(
        id: map['id'] as String,
        pgId: map['pgId'] as String,
        number: map['number'] as String,
        floor: map['floor'] as int,
        beds: map['beds'] as int,
        occupied: map['occupied'] as int,
        rent: map['rent'] as int,
      );
}

class Tenant {
  const Tenant({
    required this.id,
    required this.name,
    required this.phone,
    required this.roomId,
    required this.bed,
    required this.kyc,
    required this.agreement,
    required this.joinDate,
  });

  final String id;
  final String name;
  final String phone;
  final String roomId;
  final String bed; // bed label within the room, e.g. 'A'
  final KycStatus kyc;
  final AgreementStatus agreement;
  final DateTime joinDate;

  String get initials => name.split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join();

  Tenant copyWith({KycStatus? kyc, AgreementStatus? agreement}) => Tenant(
        id: id, name: name, phone: phone, roomId: roomId, bed: bed,
        kyc: kyc ?? this.kyc,
        agreement: agreement ?? this.agreement,
        joinDate: joinDate,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'name': name, 'phone': phone, 'roomId': roomId, 'bed': bed,
        'kyc': kyc.name, 'agreement': agreement.name,
        'joinDate': joinDate.toIso8601String(),
      };

  static Tenant fromMap(Map<String, dynamic> map) => Tenant(
        id: map['id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String,
        roomId: map['roomId'] as String,
        bed: map['bed'] as String,
        kyc: KycStatus.values.byName(map['kyc'] as String),
        agreement: AgreementStatus.values.byName(map['agreement'] as String),
        joinDate: DateTime.parse(map['joinDate'] as String),
      );
}

class Payment {
  const Payment({
    required this.id,
    required this.tenantId,
    required this.period,
    required this.amount,
    required this.status,
    required this.dueDate,
    this.paidDate,
    this.method,
  });

  final String id;
  final String tenantId;
  final DateTime period; // first day of the rent month
  final int amount;
  final PaymentStatus status;
  final DateTime dueDate;
  final DateTime? paidDate;
  final String? method;

  bool get isOverdue => status == PaymentStatus.due && DateTime.now().isAfter(dueDate);
  String get displayStatus => status == PaymentStatus.paid ? 'Paid' : (isOverdue ? 'Overdue' : 'Due');

  Payment copyWith({PaymentStatus? status, DateTime? paidDate, String? method}) => Payment(
        id: id, tenantId: tenantId, period: period, amount: amount, dueDate: dueDate,
        status: status ?? this.status,
        paidDate: paidDate ?? this.paidDate,
        method: method ?? this.method,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'tenantId': tenantId, 'period': period.toIso8601String(),
        'amount': amount, 'status': status.name,
        'dueDate': dueDate.toIso8601String(),
        'paidDate': paidDate?.toIso8601String(), 'method': method,
      };

  static Payment fromMap(Map<String, dynamic> map) => Payment(
        id: map['id'] as String,
        tenantId: map['tenantId'] as String,
        period: DateTime.parse(map['period'] as String),
        amount: map['amount'] as int,
        status: PaymentStatus.values.byName(map['status'] as String),
        dueDate: DateTime.parse(map['dueDate'] as String),
        paidDate: map['paidDate'] == null ? null : DateTime.parse(map['paidDate'] as String),
        method: map['method'] as String?,
      );
}

class MaintenanceRequest {
  const MaintenanceRequest({
    required this.id,
    required this.roomId,
    required this.title,
    required this.category,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.assignee,
  });

  final String id;
  final String roomId;
  final String title;
  final String category;
  final MaintenanceStatus status;
  final Priority priority;
  final DateTime createdAt;
  final String? assignee;

  MaintenanceRequest copyWith({MaintenanceStatus? status, String? assignee}) => MaintenanceRequest(
        id: id, roomId: roomId, title: title, category: category,
        priority: priority, createdAt: createdAt,
        status: status ?? this.status,
        assignee: assignee ?? this.assignee,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'roomId': roomId, 'title': title, 'category': category,
        'status': status.name, 'priority': priority.name,
        'createdAt': createdAt.toIso8601String(), 'assignee': assignee,
      };

  static MaintenanceRequest fromMap(Map<String, dynamic> map) => MaintenanceRequest(
        id: map['id'] as String,
        roomId: map['roomId'] as String,
        title: map['title'] as String,
        category: map['category'] as String,
        status: MaintenanceStatus.values.byName(map['status'] as String),
        priority: Priority.values.byName(map['priority'] as String),
        createdAt: DateTime.parse(map['createdAt'] as String),
        assignee: map['assignee'] as String?,
      );
}

class Visitor {
  const Visitor({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.purpose,
    required this.status,
    required this.expectedAt,
  });

  final String id;
  final String tenantId;
  final String name;
  final String purpose;
  final VisitorStatus status;
  final DateTime expectedAt;

  Visitor copyWith({VisitorStatus? status}) => Visitor(
        id: id, tenantId: tenantId, name: name, purpose: purpose, expectedAt: expectedAt,
        status: status ?? this.status,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'tenantId': tenantId, 'name': name, 'purpose': purpose,
        'status': status.name, 'expectedAt': expectedAt.toIso8601String(),
      };

  static Visitor fromMap(Map<String, dynamic> map) => Visitor(
        id: map['id'] as String,
        tenantId: map['tenantId'] as String,
        name: map['name'] as String,
        purpose: map['purpose'] as String,
        status: VisitorStatus.values.byName(map['status'] as String),
        expectedAt: DateTime.parse(map['expectedAt'] as String),
      );
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.postedAt,
  });

  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime postedAt;

  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'body': body, 'author': author,
        'postedAt': postedAt.toIso8601String(),
      };

  static Announcement fromMap(Map<String, dynamic> map) => Announcement(
        id: map['id'] as String,
        title: map['title'] as String,
        body: map['body'] as String,
        author: map['author'] as String,
        postedAt: DateTime.parse(map['postedAt'] as String),
      );
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.tenantId,
    required this.checkIn,
    this.checkOut,
  });

  final String id;
  final String tenantId;
  final DateTime checkIn;
  final DateTime? checkOut;

  bool get isIn => checkOut == null;

  AttendanceRecord copyWith({DateTime? checkOut}) => AttendanceRecord(
        id: id, tenantId: tenantId, checkIn: checkIn,
        checkOut: checkOut ?? this.checkOut,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'tenantId': tenantId,
        'checkIn': checkIn.toIso8601String(),
        'checkOut': checkOut?.toIso8601String(),
      };

  static AttendanceRecord fromMap(Map<String, dynamic> map) => AttendanceRecord(
        id: map['id'] as String,
        tenantId: map['tenantId'] as String,
        checkIn: DateTime.parse(map['checkIn'] as String),
        checkOut: map['checkOut'] == null ? null : DateTime.parse(map['checkOut'] as String),
      );
}

class UtilityBill {
  const UtilityBill({
    required this.id,
    required this.roomId,
    required this.previous,
    required this.current,
    required this.rate,
    required this.status,
  });

  final String id;
  final String roomId;
  final int previous;
  final int current;
  final int rate; // ₹ per unit, captured per bill so rate changes don't rewrite history
  final BillStatus status;

  int get units => current - previous;
  int get amount => units * rate;

  Map<String, dynamic> toMap() => {
        'id': id, 'roomId': roomId, 'previous': previous, 'current': current,
        'rate': rate, 'status': status.name,
      };

  static UtilityBill fromMap(Map<String, dynamic> map) => UtilityBill(
        id: map['id'] as String,
        roomId: map['roomId'] as String,
        previous: map['previous'] as int,
        current: map['current'] as int,
        rate: map['rate'] as int,
        status: BillStatus.values.byName(map['status'] as String),
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime createdAt;
  final bool read;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id, title: title, body: body, type: type, createdAt: createdAt,
        read: read ?? this.read,
      );

  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'body': body, 'type': type.name,
        'createdAt': createdAt.toIso8601String(), 'read': read,
      };

  static AppNotification fromMap(Map<String, dynamic> map) => AppNotification(
        id: map['id'] as String,
        title: map['title'] as String,
        body: map['body'] as String,
        type: NotificationType.values.byName(map['type'] as String),
        createdAt: DateTime.parse(map['createdAt'] as String),
        read: map['read'] as bool,
      );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'invite_message.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

class PgListingsScreen extends StatelessWidget {
  const PgListingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ManagerOnly(
        child: Scaffold(
      appBar: AppBar(title: const Text('PG properties')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editPg(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Add PG')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        itemCount: state.pgs.length,
        itemBuilder: (context, index) {
          final pg = state.pgs[index];
          final occupancy =
              pg.beds == 0 ? 0 : (pg.occupied / pg.beds * 100).round();
          final active = state.activePg?.id == pg.id;
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: active
                  ? null
                  : () {
                      state.selectPg(pg.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Now managing ${pg.name}')));
                    },
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 140,
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Color(0xFF195F59), Color(0xFF45A497)])),
                      child: Stack(children: [
                        if (pg.photo != null)
                          Positioned.fill(child: base64Image(pg.photo!))
                        else
                          const Positioned(
                              right: 20,
                              bottom: -18,
                              child: Icon(Icons.apartment_rounded,
                                  size: 150, color: Colors.white10)),
                        Positioned(
                            left: 17,
                            top: 17,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(15)),
                                child: Row(children: [
                                  const Icon(Icons.star,
                                      color: warning, size: 15),
                                  const SizedBox(width: 3),
                                  Text('${pg.rating}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12))
                                ]))),
                        Positioned(
                            right: 10,
                            top: 9,
                            child: Row(children: [
                              IconButton(
                                  onPressed: () =>
                                      _editPg(context, state, existing: pg),
                                  icon: const Icon(Icons.edit_outlined,
                                      color: Colors.white),
                                  style: IconButton.styleFrom(
                                      backgroundColor: Colors.black26)),
                              const SizedBox(width: 6),
                              IconButton(
                                  tooltip: 'Delete PG',
                                  onPressed: () =>
                                      _deletePg(context, state, pg),
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.white),
                                  style: IconButton.styleFrom(
                                      backgroundColor: Colors.black26)),
                            ])),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(17),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pg.name,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 5),
                            Row(children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 16, color: Colors.black45),
                              const SizedBox(width: 4),
                              Expanded(
                                  child: Text(pg.address,
                                      style: const TextStyle(fontSize: 12)))
                            ]),
                            const SizedBox(height: 14),
                            LinearProgressIndicator(
                                value: occupancy / 100,
                                minHeight: 7,
                                borderRadius: BorderRadius.circular(8),
                                backgroundColor: primarySoft),
                            const SizedBox(height: 7),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('$occupancy% occupied',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                  Text('${pg.occupied} of ${pg.beds} beds',
                                      style: const TextStyle(fontSize: 12))
                                ]),
                            const Divider(height: 26),
                            Row(children: [
                              Expanded(
                                  child: Text(pg.amenities,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54))),
                              if (active)
                                const StatusPill('Managing')
                              else
                                const Text('Tap to manage',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: primary,
                                        fontWeight: FontWeight.w700)),
                            ]),
                          ]),
                    ),
                  ]),
            ),
          );
        },
      ),
    ));
  }

  void _deletePg(BuildContext context, AppState state, Pg pg) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${pg.name}?'),
        content: const Text(
            'This removes the property, its rooms and its announcements. It is blocked while tenants live there. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: coral),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = state.removePg(pg.id);
    messenger
        .showSnackBar(SnackBar(content: Text(error ?? '${pg.name} deleted.')));
  }

  void _editPg(BuildContext context, AppState state, {Pg? existing}) {
    final name = TextEditingController(text: existing?.name);
    final address = TextEditingController(text: existing?.address);
    final beds = TextEditingController(text: '${existing?.beds ?? 24}');
    final amenities = TextEditingController(
        text: existing?.amenities ?? 'Wi-Fi • Food • Laundry');
    String? photo = existing?.photo;
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const SheetHandle(),
                      Text(
                          existing == null
                              ? 'Add a PG property'
                              : 'Edit property',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const FormLabel('Property name'),
                      TextField(
                          controller: name,
                          decoration: const InputDecoration(
                              hintText: 'e.g. Indiranagar PG')),
                      const FormLabel('Full address'),
                      TextField(
                          controller: address,
                          maxLines: 2,
                          decoration: const InputDecoration(
                              hintText: 'Street, area and city')),
                      const FormLabel('Total beds'),
                      TextField(
                          controller: beds,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.bed_outlined))),
                      const FormLabel('Amenities'),
                      TextField(controller: amenities, maxLines: 2),
                      const SizedBox(height: 14),
                      if (photo != null) ...[
                        ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: base64Image(photo!, height: 120)),
                        const SizedBox(height: 10),
                      ],
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await pickImageBase64(context);
                          if (picked != null) {
                            setModalState(() => photo = picked);
                          }
                        },
                        icon: Icon(photo == null
                            ? Icons.add_a_photo_outlined
                            : Icons.check_circle_outline),
                        label: Text(photo == null
                            ? 'Add property photo'
                            : 'Photo added · tap to change'),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                          onPressed: () {
                            if (name.text.trim().isEmpty ||
                                address.text.trim().isEmpty) {
                              return;
                            }
                            final base = existing ??
                                Pg(
                                    id: 'p${DateTime.now().microsecondsSinceEpoch}',
                                    name: '',
                                    address: '',
                                    beds: 0,
                                    occupied: 0,
                                    amenities: '',
                                    rating: 4.5);
                            state.savePg(base.copyWith(
                              name: name.text.trim(),
                              address: address.text.trim(),
                              beds: int.tryParse(beds.text) ?? 24,
                              amenities: amenities.text.trim(),
                              photo: photo,
                            ));
                            Navigator.pop(context);
                          },
                          child: Text(existing == null
                              ? 'Create property'
                              : 'Save changes')),
                    ]))));
  }
}

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});
  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  int floor = 1;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final floors = state.pgRooms.map((r) => r.floor).toSet().toList()..sort();
    final selected =
        floors.contains(floor) ? floor : (floors.isEmpty ? 1 : floors.first);
    final rooms = state.pgRooms.where((e) => e.floor == selected).toList();
    return ManagerOnly(
        child: Scaffold(
      appBar: AppBar(title: const Text('Rooms & beds')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addRoom(context, state),
          icon: const Icon(Icons.add),
          label: const Text('Add room')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            const PageHeader(
                title: 'Bed occupancy',
                subtitle: 'Live floor-wise availability'),
            const SizedBox(height: 18),
            if (floors.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: floors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ChoiceChip(
                    label: Text('Floor ${floors[i]}'),
                    selected: selected == floors[i],
                    onSelected: (_) => setState(() => floor = floors[i]),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            ...rooms.map((room) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                RoomDetailsScreen(roomId: room.id))),
                    child: Padding(
                      padding: const EdgeInsets.all(17),
                      child: Row(children: [
                        Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: primarySoft,
                                borderRadius: BorderRadius.circular(13)),
                            child: Text(room.number,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: primary))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(room.type,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(
                                  '${inr(room.rent)} / bed · ${room.occupied}/${room.beds} filled'),
                            ])),
                        RoomMenuButton(room: room),
                      ]),
                    ),
                  ),
                )),
            if (rooms.isEmpty)
              const EmptyState(
                  icon: Icons.meeting_room_outlined,
                  title: 'No rooms on this floor'),
          ]),
    ));
  }

  void _addRoom(BuildContext context, AppState state) {
    final pg = state.activePg;
    if (pg == null) return;
    final number = TextEditingController();
    final rent = TextEditingController(text: '9000');
    final pgId = pg.id;
    var roomFloor = floor;
    var beds = 2;
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const SheetHandle(),
                      Text('Add a room',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 6),
                      Text('In ${pg.name} — switch property from the top bar.',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                      const FormLabel('Room number'),
                      TextField(
                          controller: number,
                          decoration:
                              const InputDecoration(hintText: 'e.g. 204')),
                      const FormLabel('Floor'),
                      DropdownButtonFormField<int>(
                          initialValue: roomFloor,
                          items: [1, 2, 3, 4, 5]
                              .map((e) => DropdownMenuItem(
                                  value: e, child: Text('Floor $e')))
                              .toList(),
                          onChanged: (v) =>
                              setModalState(() => roomFloor = v!)),
                      const FormLabel('Sharing type'),
                      DropdownButtonFormField<int>(
                          initialValue: beds,
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Single')),
                            DropdownMenuItem(
                                value: 2, child: Text('Double sharing')),
                            DropdownMenuItem(
                                value: 3, child: Text('Triple sharing'))
                          ],
                          onChanged: (v) => setModalState(() => beds = v!)),
                      const FormLabel('Monthly rent per bed'),
                      TextField(
                          controller: rent,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(prefixText: '₹ ')),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: () {
                            if (number.text.trim().isEmpty) return;
                            state.addRoom(Room(
                              id: 'r${DateTime.now().microsecondsSinceEpoch}',
                              pgId: pgId,
                              number: number.text.trim(),
                              floor: roomFloor,
                              beds: beds,
                              occupied: 0,
                              rent: int.tryParse(rent.text) ?? 9000,
                            ));
                            setState(() => floor = roomFloor);
                            Navigator.pop(context);
                          },
                          child: const Text('Add room')),
                    ]))));
  }
}

/// The ⋮ menu shared by the room card and the Room Details app bar.
class RoomMenuButton extends StatelessWidget {
  const RoomMenuButton({super.key, required this.room, this.onDeleted});
  final Room room;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Room options',
      onSelected: (v) {
        switch (v) {
          case 'edit':
            _editRoomDialog(context, state, room);
          case 'sharing':
            _editSharingDialog(context, state, room);
          case 'rent':
            _editRentDialog(context, state, room);
          case 'delete':
            _deleteRoom(context, state, room, onDeleted);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit room')),
        PopupMenuItem(value: 'sharing', child: Text('Edit sharing type')),
        PopupMenuItem(value: 'rent', child: Text('Edit current rent')),
        PopupMenuItem(
            value: 'delete',
            child: Text('Delete room', style: TextStyle(color: coral))),
      ],
    );
  }
}

void _editRoomDialog(BuildContext context, AppState state, Room room) {
  final number = TextEditingController(text: room.number);
  var floor = room.floor;
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit room'),
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FormLabel('Room number'),
              TextField(controller: number),
              const FormLabel('Floor'),
              TextField(
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: '$floor'),
                onChanged: (v) => floor = int.tryParse(v) ?? floor,
              ),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () {
              final error =
                  state.editRoom(room.id, number: number.text, floor: floor);
              Navigator.pop(dialogContext);
              if (error != null) {
                messenger.showSnackBar(SnackBar(content: Text(error)));
              }
            },
            child: const Text('Save')),
      ],
    ),
  );
}

void _editSharingDialog(BuildContext context, AppState state, Room room) {
  var beds = room.beds;
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit sharing type'),
      content: StatefulBuilder(
        builder: (context, setLocal) => DropdownButtonFormField<int>(
          initialValue: beds,
          items: const [
            DropdownMenuItem(value: 1, child: Text('Single')),
            DropdownMenuItem(value: 2, child: Text('Double sharing')),
            DropdownMenuItem(value: 3, child: Text('Triple sharing')),
            DropdownMenuItem(value: 4, child: Text('Four sharing')),
          ],
          onChanged: (v) => setLocal(() => beds = v ?? beds),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () {
              final error = state.setRoomBeds(room.id, beds);
              Navigator.pop(dialogContext);
              if (error != null) {
                messenger.showSnackBar(SnackBar(content: Text(error)));
              }
            },
            child: const Text('Save')),
      ],
    ),
  );
}

void _editRentDialog(BuildContext context, AppState state, Room room) {
  final rent = TextEditingController(text: '${room.rent}');
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit current rent'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: rent,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(prefixText: '₹ ')),
        const SizedBox(height: 8),
        const Text(
            'Only future dues use the new rent; past payments keep theirs.',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () {
              final value = int.tryParse(rent.text) ?? 0;
              if (value <= 0) return;
              state.setRoomRent(room.id, value);
              Navigator.pop(dialogContext);
              messenger
                  .showSnackBar(const SnackBar(content: Text('Rent updated.')));
            },
            child: const Text('Save')),
      ],
    ),
  );
}

void _deleteRoom(BuildContext context, AppState state, Room room,
    VoidCallback? onDeleted) async {
  final messenger = ScaffoldMessenger.of(context);
  if (room.occupied > 0 || state.takenBeds(room.id).isNotEmpty) {
    messenger.showSnackBar(SnackBar(
        content: Text(
            'Room ${room.number} has tenants — move them out before deleting.')));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete room ${room.number}?'),
      content: const Text(
          'This removes the room and its empty beds. This cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: coral),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete')),
      ],
    ),
  );
  if (confirmed != true) return;
  final error = state.removeRoom(room.id);
  messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'Room ${room.number} deleted.')));
  if (error == null) onDeleted?.call();
}

class RoomDetailsScreen extends StatelessWidget {
  const RoomDetailsScreen({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final room = state.roomById(roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
            icon: Icons.meeting_room_outlined, title: 'Room not found'),
      );
    }
    final occupants = state.tenants.where((t) => t.roomId == roomId).toList();
    final free = room.beds - room.occupied;
    return ManagerOnly(
        child: Scaffold(
      appBar: AppBar(
        title: Text('Room ${room.number}'),
        actions: [
          RoomMenuButton(room: room, onDeleted: () => Navigator.pop(context)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detail('Floor', 'Floor ${room.floor}'),
                    _detail('Sharing type', room.type),
                    _detail('Current rent', '${inr(room.rent)} / bed / month'),
                    _detail('Beds', '${room.beds}'),
                    _detail('Occupancy',
                        '${room.occupied} filled · $free available'),
                  ]),
            ),
          ),
          const SizedBox(height: 18),
          Text('Assigned tenants',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (occupants.isEmpty)
            const EmptyState(
                icon: Icons.person_outline, title: 'No tenants in this room')
          else
            ...occupants.map((t) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                        backgroundColor: primarySoft,
                        child: Text(t.initials,
                            style: const TextStyle(
                                color: primary, fontWeight: FontWeight.w800))),
                    title: Text(t.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Bed ${t.bed} · ${t.phone}'),
                    trailing: StatusPill(t.kyc.label),
                  ),
                )),
        ],
      ),
    ));
  }

  Widget _detail(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]));
}

class TenantsScreen extends StatefulWidget {
  const TenantsScreen({super.key});
  @override
  State<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends State<TenantsScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final needle = query.trim().toLowerCase();
    final results = needle.isEmpty
        ? state.pgTenants
        : state.pgTenants
            .where((e) => '${e.name} ${state.tenantRoomLabel(e)} ${e.phone}'
                .toLowerCase()
                .contains(needle))
            .toList();
    return ManagerOnly(
        child: Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _onboard(context, state),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Onboard')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            PageHeader(
                title: '${state.pgTenants.length} active tenants',
                subtitle:
                    '${state.pgTenants.where((e) => e.kyc == KycStatus.pending).length} KYC pending · ${state.activePg?.name ?? ''}'),
            const SizedBox(height: 18),
            TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, room or phone')),
            const SizedBox(height: 14),
            if (results.isEmpty)
              const EmptyState(
                  icon: Icons.person_search_outlined,
                  title: 'No tenants match your search'),
            ...results.map((tenant) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    shape: const Border(),
                    leading: CircleAvatar(
                        backgroundColor: primarySoft,
                        child: Text(tenant.initials,
                            style: const TextStyle(
                                color: primary, fontWeight: FontWeight.w800))),
                    title: Text(tenant.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        'Room ${state.tenantRoomLabel(tenant)} · ${tenant.phone}'),
                    trailing: StatusPill(tenant.kyc.label),
                    children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(children: [
                            const Divider(),
                            _detail(Icons.calendar_today_outlined, 'Joined',
                                formatFullDate(tenant.joinDate)),
                            _detail(Icons.verified_user_outlined, 'KYC',
                                tenant.kyc.label),
                            const SizedBox(height: 10),
                            if (tenant.kycDoc != null) ...[
                              SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _viewKycDoc(context, tenant),
                                      icon: const Icon(Icons.badge_outlined),
                                      label: const Text('View KYC document'))),
                              const SizedBox(height: 8),
                            ],
                            OutlinedButton.icon(
                                onPressed: () => _call(tenant.phone),
                                icon: const Icon(Icons.call_outlined),
                                label: const Text('Call tenant')),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                  child: FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _invite(context, state, tenant),
                                      icon: const Icon(Icons.send_outlined),
                                      label: Text(AppLocalizations.of(context)
                                          .t('inv.inviteToApp')))),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                tooltip: AppLocalizations.of(context)
                                    .t('inv.options'),
                                onSelected: (value) {
                                  if (value == 'resend') {
                                    _resendInvite(context, state, tenant);
                                  } else if (value == 'revoke') {
                                    _revokeInvite(context, state, tenant);
                                  } else {
                                    _removeTenant(context, state, tenant);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                      value: 'resend',
                                      child: ListTile(
                                          leading: const Icon(Icons.refresh),
                                          title: Text(
                                              AppLocalizations.of(context)
                                                  .t('inv.resend')),
                                          contentPadding: EdgeInsets.zero)),
                                  PopupMenuItem(
                                      value: 'revoke',
                                      child: ListTile(
                                          leading: const Icon(Icons.link_off),
                                          title: Text(
                                              AppLocalizations.of(context)
                                                  .t('inv.revoke')),
                                          contentPadding: EdgeInsets.zero)),
                                  PopupMenuItem(
                                      value: 'remove',
                                      child: ListTile(
                                          leading: const Icon(
                                              Icons.person_remove_outlined,
                                              color: coral),
                                          title: Text(
                                              AppLocalizations.of(context)
                                                  .t('rem.remove'),
                                              style: const TextStyle(
                                                  color: coral)),
                                          contentPadding: EdgeInsets.zero)),
                                ],
                              ),
                            ]),
                          ]))
                    ],
                  ),
                )),
          ]),
    ));
  }

  Widget _detail(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 17, color: Colors.black45),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 12)),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))
      ]));

  void _call(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    launchUrl(Uri(scheme: 'tel', path: digits));
  }

  void _invite(BuildContext context, AppState state, Tenant tenant) {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final address = tenant.email?.trim() ?? '';
    if (address.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.t('inv.noEmail'))));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            '${l.t('inv.add')} ${tenant.name.split(' ').first} ${l.t('inv.toApp')}'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.t('inv.desc'), style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.mail_outline, size: 18, color: primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(address,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 10),
              Text(l.t('inv.next'),
                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l.t('common.cancel'))),
          FilledButton.icon(
              onPressed: () async {
                final result = await state.inviteTenant(tenantId: tenant.id);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (result.error != null) {
                  messenger
                      .showSnackBar(SnackBar(content: Text(result.error!)));
                  return;
                }
                if (result.emailSent) {
                  messenger.showSnackBar(SnackBar(
                      content: Text('${l.t('inv.emailed')} $address')));
                } else {
                  await _shareInvite(messenger, state, tenant, address, result);
                }
              },
              icon: const Icon(Icons.send_outlined),
              label: Text(l.t('inv.createShare'))),
        ],
      ),
    );
  }

  void _resendInvite(
      BuildContext context, AppState state, Tenant tenant) async {
    final messenger = ScaffoldMessenger.of(context);
    final emailed = AppLocalizations.of(context).t('inv.emailed');
    final result = await state.resendInvite(tenantId: tenant.id);
    if (result.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    if (result.emailSent) {
      messenger
          .showSnackBar(SnackBar(content: Text('$emailed ${result.email}')));
    } else {
      await _shareInvite(messenger, state, tenant, result.email ?? '', result);
    }
  }

  void _revokeInvite(
      BuildContext context, AppState state, Tenant tenant) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.t('inv.revokeTitle')),
        content: Text(l.t('inv.revokeBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.t('common.cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.t('inv.revoke'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await state.revokeInvite(tenantId: tenant.id);
    messenger.showSnackBar(
        SnackBar(content: Text(result.error ?? l.t('inv.revokeDone'))));
  }

  void _removeTenant(
      BuildContext context, AppState state, Tenant tenant) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${l.t('rem.remove')} — ${tenant.name}?'),
        content: Text(l.t('rem.body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.t('common.cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: coral),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.t('rem.remove'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await state.removeTenant(tenant.id);
    if (result.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    final note = result.emailSent
        ? '${l.t('rem.done')} ${l.t('rem.emailSent')}'
        : '${l.t('rem.done')} ${l.t('rem.noEmail')}';
    messenger.showSnackBar(SnackBar(content: Text(note)));
  }

  Future<void> _shareInvite(ScaffoldMessengerState messenger, AppState state,
      Tenant tenant, String email, InviteResult result) async {
    final copied = AppLocalizations.of(messenger.context).t('inv.copied');
    final message = buildInviteMessage(
      tenantName: tenant.name,
      pgName: state.pgNameForTenant(tenant.id),
      email: email,
      tempPassword: result.tempPassword,
      inviteToken: result.token,
      expiresAt: result.expiresAt,
    );
    try {
      await SharePlus.instance.share(
          ShareParams(text: message, subject: 'Your PG Management login'));
    } catch (_) {
      // Share sheet unavailable (e.g. desktop browser): copy instead.
      await Clipboard.setData(ClipboardData(text: message));
      messenger.showSnackBar(SnackBar(content: Text(copied)));
    }
  }

  void _viewKycDoc(BuildContext context, Tenant tenant) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            base64Image(tenant.kycDoc!, fit: BoxFit.contain),
            Padding(
                padding: const EdgeInsets.all(10),
                child: Text('${tenant.name} · identity document',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12))),
          ]),
        ),
      );

  void _onboard(BuildContext context, AppState state) {
    final messenger = ScaffoldMessenger.of(context);
    if (state.pgs.isEmpty) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Create a PG first.')));
      return;
    }

    const newRoom = '__new__';
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final roomNumber = TextEditingController();
    final floorCtl = TextEditingController(text: '1');
    final rent = TextEditingController(text: '9000');
    final bed = TextEditingController(text: 'A');
    var pgId = (state.activePg ?? state.pgs.first).id;
    var roomChoice = newRoom; // room id, or the "new room" sentinel
    var sharing = 2;
    String? kycDoc;

    List<Room> roomsFor(String pg) =>
        state.rooms.where((r) => r.pgId == pg).toList();

    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) {
      final pgRooms = roomsFor(pgId);
      final isNew = roomChoice == newRoom;
      final selected = isNew
          ? null
          : state.rooms
              .where((r) => r.id == roomChoice)
              .cast<Room?>()
              .firstWhere((_) => true, orElse: () => null);
      return SingleChildScrollView(
        child: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetHandle(),
            Text('Onboard tenant',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            const Text(
                'Select the room and set its sharing type and rent — the tenant inherits them.'),
            const FormLabel('Full name'),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter the tenant\'s name'
                  : null,
            ),
            const FormLabel('Phone number'),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  (v == null || v.replaceAll(RegExp(r'[^0-9]'), '').length < 10)
                      ? 'Enter a valid 10-digit number'
                      : null,
            ),
            const FormLabel('Email address'),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration:
                  const InputDecoration(hintText: 'Used for their app invite'),
              validator: (v) {
                final e = (v ?? '').trim();
                return e.contains('@') && e.contains('.')
                    ? null
                    : 'Enter a valid email address';
              },
            ),
            const FormLabel('PG'),
            DropdownButtonFormField<String>(
              initialValue: pgId,
              items: state.pgs
                  .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
              onChanged: (v) => setModalState(() {
                pgId = v!;
                roomChoice = newRoom;
              }),
            ),
            const FormLabel('Room'),
            DropdownButtonFormField<String>(
              initialValue: roomChoice,
              items: [
                ...pgRooms.map((r) {
                  final free = r.beds - r.occupied;
                  final full = free <= 0;
                  return DropdownMenuItem(
                    value: r.id,
                    enabled: !full,
                    child: Text(
                        'Room ${r.number} · Floor ${r.floor} · ${r.type} · ${full ? 'Full' : '$free free'}',
                        style: full
                            ? const TextStyle(color: Colors.black38)
                            : null),
                  );
                }),
                const DropdownMenuItem(
                    value: newRoom, child: Text('＋ New room')),
              ],
              onChanged: (v) => setModalState(() {
                roomChoice = v!;
                if (v != newRoom) {
                  bed.text = state.suggestBed(v);
                }
              }),
            ),
            if (isNew) ...[
              const FormLabel('Room number'),
              TextFormField(
                controller: roomNumber,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a room number'
                    : null,
              ),
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const FormLabel('Floor'),
                      TextFormField(
                          controller: floorCtl,
                          keyboardType: TextInputType.number),
                    ])),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const FormLabel('Sharing type'),
                      DropdownButtonFormField<int>(
                        initialValue: sharing,
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Single')),
                          DropdownMenuItem(value: 2, child: Text('Double')),
                          DropdownMenuItem(value: 3, child: Text('Triple')),
                          DropdownMenuItem(value: 4, child: Text('Four')),
                        ],
                        onChanged: (v) => setModalState(() => sharing = v ?? 2),
                      ),
                    ])),
              ]),
              const FormLabel('Current room rent'),
              TextFormField(
                controller: rent,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(prefixText: '₹ '),
              ),
            ] else if (selected != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: primarySoft,
                    borderRadius: BorderRadius.circular(12)),
                child: Text(
                    '${selected.type} · ${inr(selected.rent)} / bed / month (inherited)',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primary)),
              ),
            ],
            const FormLabel('Bed label'),
            TextFormField(
              controller: bed,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. B'),
              validator: (v) {
                final b = (v ?? '').trim();
                if (b.isEmpty) return 'Enter a bed label';
                if (!isNew &&
                    state.takenBeds(roomChoice).contains(b.toUpperCase())) {
                  return 'That bed is already taken in this room';
                }
                return null;
              },
            ),
            const FormLabel('Identity document'),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await pickImageBase64(context);
                if (picked != null) {
                  setModalState(() => kycDoc = picked);
                }
              },
              icon: Icon(kycDoc == null
                  ? Icons.upload_file_outlined
                  : Icons.check_circle_outline),
              label: Text(kycDoc == null
                  ? 'Upload Aadhaar / passport'
                  : 'Document attached · tap to change'),
            ),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (kycDoc == null) {
                    messenger.showSnackBar(const SnackBar(
                        content:
                            Text('Upload the identity document to continue.')));
                    return;
                  }
                  final roomId = isNew
                      ? state.ensureRoom(
                          pgId: pgId,
                          floor: int.tryParse(floorCtl.text) ?? 1,
                          roomNumber: roomNumber.text,
                          sharingType: sharing,
                          rent: int.tryParse(rent.text) ?? 0)
                      : roomChoice;
                  final error = state.onboardTenant(
                      name: name.text,
                      phone: phone.text,
                      email: email.text,
                      roomId: roomId,
                      bed: bed.text,
                      kycDoc: kycDoc);
                  if (error != null) {
                    messenger.showSnackBar(SnackBar(content: Text(error)));
                    return;
                  }
                  Navigator.pop(context);
                  messenger.showSnackBar(SnackBar(
                      content: Text(
                          '${name.text.trim()} onboarded to room ${state.roomNumber(roomId)}.')));
                  // The invite is created and emailed automatically; the
                  // share sheet stays as the fallback when email delivery
                  // is unavailable.
                  final tenant = state.tenants.first;
                  final result = await state.inviteTenant(tenantId: tenant.id);
                  if (result.error != null) {
                    messenger
                        .showSnackBar(SnackBar(content: Text(result.error!)));
                    return;
                  }
                  if (result.emailSent) {
                    messenger.showSnackBar(SnackBar(
                        content: Text('Invite emailed to ${result.email}.')));
                  } else {
                    await _shareInvite(
                        messenger, state, tenant, result.email ?? '', result);
                  }
                },
                child: const Text('Onboard tenant')),
          ]),
        ),
      );
    }));
  }
}

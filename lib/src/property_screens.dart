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
      appBar: AppBar(title: Text(AppLocalizations.of(context).t('pg.title'))),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editPg(context, state),
          icon: const Icon(Icons.add),
          label: Text(AppLocalizations.of(context).t('pg.addShort'))),
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
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              '${AppLocalizations.of(context).t('pg.nowManaging')} ${pg.name}')));
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
                                      backgroundColor: faint)),
                              const SizedBox(width: 6),
                              IconButton(
                                  tooltip: AppLocalizations.of(context)
                                      .t('pg.deleteTip'),
                                  onPressed: () =>
                                      _deletePg(context, state, pg),
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.white),
                                  style: IconButton.styleFrom(
                                      backgroundColor: faint)),
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
                              Icon(Icons.location_on_outlined,
                                  size: 16, color: subtle),
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
                                backgroundColor: softTint),
                            const SizedBox(height: 7),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                      '$occupancy% ${AppLocalizations.of(context).t('pg.occupiedWord')}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12)),
                                  Text(
                                      '${pg.occupied}/${pg.beds} ${AppLocalizations.of(context).t('dash.beds')}',
                                      style: const TextStyle(fontSize: 12))
                                ]),
                            const Divider(height: 26),
                            Row(children: [
                              Expanded(
                                  child: Text(pg.amenities,
                                      style: TextStyle(
                                          fontSize: 12, color: subtle))),
                              if (active)
                                const StatusPill('Managing')
                              else
                                Text(
                                    AppLocalizations.of(context)
                                        .t('pg.tapManage'),
                                    style: const TextStyle(
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
    final deletedWord = AppLocalizations.of(context).t('common.deleted');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            '${AppLocalizations.of(context).t('common.delete')} ${pg.name}?'),
        content: Text(AppLocalizations.of(context).t('pg.deleteBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppLocalizations.of(context).t('common.cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: coral),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppLocalizations.of(context).t('common.delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = state.removePg(pg.id);
    messenger.showSnackBar(
        SnackBar(content: Text(error ?? '${pg.name} $deletedWord')));
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
                              ? AppLocalizations.of(context).t('pg.add')
                              : AppLocalizations.of(context).t('pg.edit'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      FormLabel(AppLocalizations.of(context).t('pg.name')),
                      TextField(
                          controller: name,
                          decoration: const InputDecoration(
                              hintText: 'e.g. Indiranagar PG')),
                      FormLabel(AppLocalizations.of(context).t('pg.address')),
                      TextField(
                          controller: address,
                          maxLines: 2,
                          decoration: const InputDecoration(
                              hintText: 'Street, area and city')),
                      FormLabel(AppLocalizations.of(context).t('pg.totalBeds')),
                      TextField(
                          controller: beds,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.bed_outlined))),
                      FormLabel(AppLocalizations.of(context).t('pg.amenities')),
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
                            ? AppLocalizations.of(context).t('pg.addPhoto')
                            : AppLocalizations.of(context).t('pg.photoAdded')),
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
                              ? AppLocalizations.of(context).t('pg.create')
                              : AppLocalizations.of(context).t('common.save'))),
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
      appBar: AppBar(title: Text(AppLocalizations.of(context).t('room.title'))),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addRoom(context, state),
          icon: const Icon(Icons.add),
          label: Text(AppLocalizations.of(context).t('room.add'))),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            PageHeader(
                title: AppLocalizations.of(context).t('room.occupancy'),
                subtitle:
                    AppLocalizations.of(context).t('room.liveAvailability')),
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
                                color: softTint,
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
              EmptyState(
                  icon: Icons.meeting_room_outlined,
                  title: AppLocalizations.of(context).t('room.noneFloor')),
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
                      Text(AppLocalizations.of(context).t('room.addTitle'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 6),
                      Text('In ${pg.name} — switch property from the top bar.',
                          style: TextStyle(fontSize: 12, color: subtle)),
                      FormLabel(AppLocalizations.of(context).t('room.number')),
                      TextField(
                          controller: number,
                          decoration:
                              const InputDecoration(hintText: 'e.g. 204')),
                      FormLabel(AppLocalizations.of(context).t('room.floor')),
                      DropdownButtonFormField<int>(
                          initialValue: roomFloor,
                          items: [1, 2, 3, 4, 5]
                              .map((e) => DropdownMenuItem(
                                  value: e,
                                  child: Text(
                                      '${AppLocalizations.of(context).t('room.floor')} $e')))
                              .toList(),
                          onChanged: (v) =>
                              setModalState(() => roomFloor = v!)),
                      FormLabel(AppLocalizations.of(context).t('room.sharing')),
                      DropdownButtonFormField<int>(
                          initialValue: beds,
                          items: [
                            DropdownMenuItem(
                                value: 1,
                                child: Text(AppLocalizations.of(context)
                                    .t('share.single'))),
                            DropdownMenuItem(
                                value: 2,
                                child: Text(AppLocalizations.of(context)
                                    .t('share.double'))),
                            DropdownMenuItem(
                                value: 3,
                                child: Text(AppLocalizations.of(context)
                                    .t('share.triple')))
                          ],
                          onChanged: (v) => setModalState(() => beds = v!)),
                      FormLabel(
                          AppLocalizations.of(context).t('room.rentPerBed')),
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
                          child:
                              Text(AppLocalizations.of(context).t('room.add'))),
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
      tooltip: AppLocalizations.of(context).t('room.options'),
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
      itemBuilder: (_) => [
        PopupMenuItem(
            value: 'edit',
            child: Text(AppLocalizations.of(context).t('room.editRoom'))),
        PopupMenuItem(
            value: 'sharing',
            child: Text(AppLocalizations.of(context).t('room.editSharing'))),
        PopupMenuItem(
            value: 'rent',
            child: Text(AppLocalizations.of(context).t('room.editRent'))),
        PopupMenuItem(
            value: 'delete',
            child: Text(AppLocalizations.of(context).t('room.delete'),
                style: const TextStyle(color: coral))),
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
      title: Text(AppLocalizations.of(context).t('room.editRoom')),
      content: StatefulBuilder(
        builder: (context, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormLabel(AppLocalizations.of(context).t('room.number')),
              TextField(controller: number),
              FormLabel(AppLocalizations.of(context).t('room.floor')),
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
            child: Text(AppLocalizations.of(context).t('common.cancel'))),
        FilledButton(
            onPressed: () {
              final error =
                  state.editRoom(room.id, number: number.text, floor: floor);
              Navigator.pop(dialogContext);
              if (error != null) {
                messenger.showSnackBar(SnackBar(content: Text(error)));
              }
            },
            child: Text(AppLocalizations.of(context).t('common.save'))),
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
      title: Text(AppLocalizations.of(context).t('room.editSharing')),
      content: StatefulBuilder(
        builder: (context, setLocal) => DropdownButtonFormField<int>(
          initialValue: beds,
          items: [
            DropdownMenuItem(
                value: 1,
                child: Text(AppLocalizations.of(context).t('share.single'))),
            DropdownMenuItem(
                value: 2,
                child: Text(AppLocalizations.of(context).t('share.double'))),
            DropdownMenuItem(
                value: 3,
                child: Text(AppLocalizations.of(context).t('share.triple'))),
            DropdownMenuItem(
                value: 4,
                child: Text(AppLocalizations.of(context).t('share.four'))),
          ],
          onChanged: (v) => setLocal(() => beds = v ?? beds),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context).t('common.cancel'))),
        FilledButton(
            onPressed: () {
              final error = state.setRoomBeds(room.id, beds);
              Navigator.pop(dialogContext);
              if (error != null) {
                messenger.showSnackBar(SnackBar(content: Text(error)));
              }
            },
            child: Text(AppLocalizations.of(context).t('common.save'))),
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
      title: Text(AppLocalizations.of(context).t('room.editRent')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: rent,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(prefixText: '₹ ')),
        const SizedBox(height: 8),
        Text('Only future dues use the new rent; past payments keep theirs.',
            style: TextStyle(fontSize: 11, color: subtle)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context).t('common.cancel'))),
        FilledButton(
            onPressed: () {
              final value = int.tryParse(rent.text) ?? 0;
              if (value <= 0) return;
              state.setRoomRent(room.id, value);
              Navigator.pop(dialogContext);
              messenger
                  .showSnackBar(const SnackBar(content: Text('Rent updated.')));
            },
            child: Text(AppLocalizations.of(context).t('common.save'))),
      ],
    ),
  );
}

void _deleteRoom(BuildContext context, AppState state, Room room,
    VoidCallback? onDeleted) async {
  final messenger = ScaffoldMessenger.of(context);
  final roomWord = AppLocalizations.of(context).t('common.room');
  final deletedWord = AppLocalizations.of(context).t('common.deleted');
  if (room.occupied > 0 || state.takenBeds(room.id).isNotEmpty) {
    messenger.showSnackBar(SnackBar(
        content: Text(
            'Room ${room.number} has tenants — move them out before deleting.')));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
          '${AppLocalizations.of(context).t('room.delete')} ${room.number}?'),
      content: Text(AppLocalizations.of(context).t('room.deleteBody')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppLocalizations.of(context).t('common.cancel'))),
        FilledButton(
            style: FilledButton.styleFrom(backgroundColor: coral),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppLocalizations.of(context).t('common.delete'))),
      ],
    ),
  );
  if (confirmed != true) return;
  final error = state.removeRoom(room.id);
  messenger.showSnackBar(SnackBar(
      content: Text(error ?? '$roomWord ${room.number} $deletedWord')));
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
        body: EmptyState(
            icon: Icons.meeting_room_outlined,
            title: AppLocalizations.of(context).t('room.notFound')),
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
                    _detail(AppLocalizations.of(context).t('room.floor'),
                        '${AppLocalizations.of(context).t('room.floor')} ${room.floor}'),
                    _detail(AppLocalizations.of(context).t('room.sharing'),
                        room.type),
                    _detail(AppLocalizations.of(context).t('room.currentRent'),
                        '${inr(room.rent)} ${AppLocalizations.of(context).t('room.perBedMonth')}'),
                    _detail(AppLocalizations.of(context).t('dash.beds'),
                        '${room.beds}'),
                    _detail(AppLocalizations.of(context).t('dash.occupancy'),
                        '${room.occupied} filled · $free available'),
                  ]),
            ),
          ),
          const SizedBox(height: 18),
          Text(AppLocalizations.of(context).t('room.assigned'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (occupants.isEmpty)
            EmptyState(
                icon: Icons.person_outline,
                title: AppLocalizations.of(context).t('room.noTenants'))
          else
            ...occupants.map((t) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                        backgroundColor: softTint,
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
        Text(label, style: TextStyle(color: subtle)),
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
      appBar: AppBar(title: Text(AppLocalizations.of(context).t('ten.title'))),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _onboard(context, state),
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(AppLocalizations.of(context).t('ten.onboard'))),
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
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText:
                        AppLocalizations.of(context).t('ten.searchHint'))),
            const SizedBox(height: 14),
            if (results.isEmpty)
              EmptyState(
                  icon: Icons.person_search_outlined,
                  title: AppLocalizations.of(context).t('ten.noMatch')),
            ...results.map((tenant) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ExpansionTile(
                    shape: const Border(),
                    leading: CircleAvatar(
                        backgroundColor: softTint,
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
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Divider(height: 1),
                                const SizedBox(height: 10),
                                if ((tenant.email ?? '').isNotEmpty)
                                  _detail(
                                      Icons.mail_outline,
                                      AppLocalizations.of(context)
                                          .t('ten.email'),
                                      tenant.email!),
                                _detail(
                                    Icons.call_outlined,
                                    AppLocalizations.of(context)
                                        .t('form.phone'),
                                    tenant.phone),
                                _detail(
                                    Icons.calendar_today_outlined,
                                    AppLocalizations.of(context)
                                        .t('ten.joined'),
                                    formatFullDate(tenant.joinDate)),
                                _detail(Icons.verified_user_outlined, 'KYC',
                                    tenant.kyc.label),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                      child: OutlinedButton.icon(
                                          onPressed: () => _call(tenant.phone),
                                          icon: const Icon(Icons.call_outlined,
                                              size: 18),
                                          label: Text(
                                              AppLocalizations.of(context)
                                                  .t('ten.call')))),
                                  if (tenant.kycDoc != null) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _viewKycDoc(context, tenant),
                                            icon: const Icon(
                                                Icons.badge_outlined,
                                                size: 18),
                                            label: const Text('KYC'))),
                                  ],
                                  const SizedBox(width: 8),
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
                                              leading:
                                                  const Icon(Icons.refresh),
                                              title: Text(
                                                  AppLocalizations.of(context)
                                                      .t('inv.resend')),
                                              contentPadding: EdgeInsets.zero)),
                                      PopupMenuItem(
                                          value: 'revoke',
                                          child: ListTile(
                                              leading:
                                                  const Icon(Icons.link_off),
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
        Icon(icon, size: 17, color: subtle),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 12)),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))
      ]));

  void _call(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    launchUrl(Uri(scheme: 'tel', path: digits));
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
      messenger.showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).t('ten.pgFirst'))));
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
            Text(AppLocalizations.of(context).t('ten.onboardTitle'),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(AppLocalizations.of(context).t('ten.onboardSub')),
            FormLabel(AppLocalizations.of(context).t('form.fullName')),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter the tenant\'s name'
                  : null,
            ),
            FormLabel(AppLocalizations.of(context).t('form.phone')),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  (v == null || v.replaceAll(RegExp(r'[^0-9]'), '').length < 10)
                      ? AppLocalizations.of(context).t('form.phoneInvalid')
                      : null,
            ),
            FormLabel(AppLocalizations.of(context).t('ten.email')),
            TextFormField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).t('ten.emailHint')),
              validator: (v) {
                final e = (v ?? '').trim();
                return e.contains('@') && e.contains('.')
                    ? null
                    : AppLocalizations.of(context).t('form.emailInvalid');
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
            FormLabel(AppLocalizations.of(context).t('common.room')),
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
                        style: full ? TextStyle(color: subtle) : null),
                  );
                }),
                DropdownMenuItem(
                    value: newRoom,
                    child: Text(
                        '＋ ${AppLocalizations.of(context).t('room.add')}')),
              ],
              onChanged: (v) => setModalState(() {
                roomChoice = v!;
                if (v != newRoom) {
                  bed.text = state.suggestBed(v);
                }
              }),
            ),
            if (isNew) ...[
              FormLabel(AppLocalizations.of(context).t('room.number')),
              TextFormField(
                controller: roomNumber,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? AppLocalizations.of(context).t('room.numberReq')
                    : null,
              ),
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      FormLabel(AppLocalizations.of(context).t('room.floor')),
                      TextFormField(
                          controller: floorCtl,
                          keyboardType: TextInputType.number),
                    ])),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      FormLabel(AppLocalizations.of(context).t('room.sharing')),
                      DropdownButtonFormField<int>(
                        initialValue: sharing,
                        items: [
                          DropdownMenuItem(
                              value: 1,
                              child: Text(AppLocalizations.of(context)
                                  .t('share.single'))),
                          DropdownMenuItem(
                              value: 2,
                              child: Text(AppLocalizations.of(context)
                                  .t('share.double'))),
                          DropdownMenuItem(
                              value: 3,
                              child: Text(AppLocalizations.of(context)
                                  .t('share.triple'))),
                          DropdownMenuItem(
                              value: 4,
                              child: Text(AppLocalizations.of(context)
                                  .t('share.four'))),
                        ],
                        onChanged: (v) => setModalState(() => sharing = v ?? 2),
                      ),
                    ])),
              ]),
              FormLabel(AppLocalizations.of(context).t('room.currentRent')),
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
                    color: softTint, borderRadius: BorderRadius.circular(12)),
                child: Text(
                    '${selected.type} · ${inr(selected.rent)} / bed / month (inherited)',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: primary)),
              ),
            ],
            FormLabel(AppLocalizations.of(context).t('ten.bed')),
            TextFormField(
              controller: bed,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'e.g. B'),
              validator: (v) {
                final b = (v ?? '').trim();
                if (b.isEmpty) {
                  return AppLocalizations.of(context).t('ten.bedReq');
                }
                if (!isNew &&
                    state.takenBeds(roomChoice).contains(b.toUpperCase())) {
                  return AppLocalizations.of(context).t('ten.bedTaken');
                }
                return null;
              },
            ),
            FormLabel(AppLocalizations.of(context).t('ten.kycDoc')),
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
                  ? AppLocalizations.of(context).t('ten.uploadKyc')
                  : AppLocalizations.of(context).t('ten.kycAttached')),
            ),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () async {
                  final emailedWord =
                      AppLocalizations.of(context).t('inv.emailed');
                  if (!formKey.currentState!.validate()) return;
                  if (kycDoc == null) {
                    messenger.showSnackBar(SnackBar(
                        content: Text(AppLocalizations.of(context)
                            .t('ten.kycRequired'))));
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
                          '${name.text.trim()} ${AppLocalizations.of(context).t('ten.onboardedTo')} ${state.roomNumber(roomId)}.')));
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
                        content: Text('$emailedWord ${result.email}')));
                  } else {
                    await _shareInvite(
                        messenger, state, tenant, result.email ?? '', result);
                  }
                },
                child:
                    Text(AppLocalizations.of(context).t('ten.onboardTitle'))),
          ]),
        ),
      );
    }));
  }
}

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class PgListingsScreen extends StatelessWidget {
  const PgListingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('PG properties')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _editPg(context, state), icon: const Icon(Icons.add), label: const Text('Add PG')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        itemCount: state.pgs.length,
        itemBuilder: (context, index) {
          final pg = state.pgs[index];
          final occupancy = pg.beds == 0 ? 0 : (pg.occupied / pg.beds * 100).round();
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 140,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF195F59), Color(0xFF45A497)])),
                child: Stack(children: [
                  const Positioned(right: 20, bottom: -18, child: Icon(Icons.apartment_rounded, size: 150, color: Colors.white10)),
                  Positioned(left: 17, top: 17, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Row(children: [const Icon(Icons.star, color: warning, size: 15), const SizedBox(width: 3), Text('${pg.rating}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))]))),
                  Positioned(right: 10, top: 9, child: IconButton(onPressed: () => _editPg(context, state, existing: pg), icon: const Icon(Icons.edit_outlined, color: Colors.white))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(17),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pg.name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 5),
                  Row(children: [const Icon(Icons.location_on_outlined, size: 16, color: Colors.black45), const SizedBox(width: 4), Expanded(child: Text(pg.address, style: const TextStyle(fontSize: 12)))]),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: occupancy / 100, minHeight: 7, borderRadius: BorderRadius.circular(8), backgroundColor: primarySoft),
                  const SizedBox(height: 7),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('$occupancy% occupied', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), Text('${pg.occupied} of ${pg.beds} beds', style: const TextStyle(fontSize: 12))]),
                  const Divider(height: 26),
                  Text(pg.amenities, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _editPg(BuildContext context, AppState state, {Pg? existing}) {
    final name = TextEditingController(text: existing?.name);
    final address = TextEditingController(text: existing?.address);
    final beds = TextEditingController(text: '${existing?.beds ?? 24}');
    final amenities = TextEditingController(text: existing?.amenities ?? 'Wi-Fi • Food • Laundry');
    showAppSheet(context, SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(),
      Text(existing == null ? 'Add a PG property' : 'Edit property', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Property name'), TextField(controller: name, decoration: const InputDecoration(hintText: 'e.g. Indiranagar PG')),
      const FormLabel('Full address'), TextField(controller: address, maxLines: 2, decoration: const InputDecoration(hintText: 'Street, area and city')),
      const FormLabel('Total beds'), TextField(controller: beds, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixIcon: Icon(Icons.bed_outlined))),
      const FormLabel('Amenities'), TextField(controller: amenities, maxLines: 2),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add property photos')),
      const SizedBox(height: 18),
      FilledButton(onPressed: () {
        if (name.text.trim().isEmpty || address.text.trim().isEmpty) return;
        final base = existing ?? Pg(id: 'p${DateTime.now().microsecondsSinceEpoch}', name: '', address: '', beds: 0, occupied: 0, amenities: '', rating: 4.5);
        state.savePg(base.copyWith(
          name: name.text.trim(),
          address: address.text.trim(),
          beds: int.tryParse(beds.text) ?? 24,
          amenities: amenities.text.trim(),
        ));
        Navigator.pop(context);
      }, child: Text(existing == null ? 'Create property' : 'Save changes')),
    ])));
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
    final floors = state.rooms.map((r) => r.floor).toSet().toList()..sort();
    final selected = floors.contains(floor) ? floor : (floors.isEmpty ? 1 : floors.first);
    final rooms = state.rooms.where((e) => e.floor == selected).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Rooms & beds')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addRoom(context, state), icon: const Icon(Icons.add), label: const Text('Add room')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        const PageHeader(title: 'Bed occupancy', subtitle: 'Live floor-wise availability'),
        const SizedBox(height: 18),
        if (floors.isNotEmpty)
          SegmentedButton<int>(
            segments: floors.map((f) => ButtonSegment(value: f, label: Text('Floor $f'))).toList(),
            selected: {selected},
            onSelectionChanged: (value) => setState(() => floor = value.first),
          ),
        const SizedBox(height: 18),
        ...rooms.map((room) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(13)), child: Text(room.number, style: const TextStyle(fontWeight: FontWeight.w800, color: primary))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(room.type, style: Theme.of(context).textTheme.titleMedium), Text('${inr(room.rent)} / bed / month')])),
                IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
              ]),
              const Divider(height: 25),
              Row(children: [
                for (var bed = 0; bed < room.beds; bed++)
                  Expanded(child: Container(
                    margin: EdgeInsets.only(right: bed == room.beds - 1 ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: bed < room.occupied ? primarySoft : const Color(0xFFF1F2F2), borderRadius: BorderRadius.circular(11), border: Border.all(color: bed < room.occupied ? primary.withValues(alpha: .25) : Colors.black12)),
                    child: Column(children: [Icon(Icons.bed_rounded, color: bed < room.occupied ? primary : Colors.black26), const SizedBox(height: 3), Text(bed < room.occupied ? 'Occupied' : 'Available', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: bed < room.occupied ? primary : Colors.black45))]),
                  )),
              ]),
            ]),
          ),
        )),
        if (rooms.isEmpty) const EmptyState(icon: Icons.meeting_room_outlined, title: 'No rooms on this floor'),
      ]),
    );
  }

  void _addRoom(BuildContext context, AppState state) {
    if (state.pgs.isEmpty) return;
    final number = TextEditingController();
    final rent = TextEditingController(text: '9000');
    var pgId = state.pgs.first.id;
    var roomFloor = floor;
    var beds = 2;
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Add a room', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Property'), DropdownButtonFormField<String>(initialValue: pgId, items: state.pgs.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))).toList(), onChanged: (v) => setModalState(() => pgId = v!)),
      const FormLabel('Room number'), TextField(controller: number, decoration: const InputDecoration(hintText: 'e.g. 204')),
      const FormLabel('Floor'), DropdownButtonFormField<int>(initialValue: roomFloor, items: [1, 2, 3, 4, 5].map((e) => DropdownMenuItem(value: e, child: Text('Floor $e'))).toList(), onChanged: (v) => setModalState(() => roomFloor = v!)),
      const FormLabel('Sharing type'), DropdownButtonFormField<int>(initialValue: beds, items: const [DropdownMenuItem(value: 1, child: Text('Single')), DropdownMenuItem(value: 2, child: Text('Double sharing')), DropdownMenuItem(value: 3, child: Text('Triple sharing'))], onChanged: (v) => setModalState(() => beds = v!)),
      const FormLabel('Monthly rent per bed'), TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
      const SizedBox(height: 20), FilledButton(onPressed: () {
        if (number.text.trim().isEmpty) return;
        state.addRoom(Room(
          id: 'r${DateTime.now().microsecondsSinceEpoch}', pgId: pgId,
          number: number.text.trim(), floor: roomFloor, beds: beds, occupied: 0,
          rent: int.tryParse(rent.text) ?? 9000,
        ));
        setState(() => floor = roomFloor);
        Navigator.pop(context);
      }, child: const Text('Add room')),
    ]))));
  }
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
        ? state.tenants
        : state.tenants.where((e) => '${e.name} ${state.tenantRoomLabel(e)} ${e.phone}'.toLowerCase().contains(needle)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _onboard(context, state), icon: const Icon(Icons.person_add_alt_1), label: const Text('Onboard')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        PageHeader(title: '${state.tenants.length} active tenants', subtitle: '${state.tenants.where((e) => e.kyc == KycStatus.pending).length} KYC pending'),
        const SizedBox(height: 18),
        TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name, room or phone')),
        const SizedBox(height: 14),
        if (results.isEmpty) const EmptyState(icon: Icons.person_search_outlined, title: 'No tenants match your search'),
        ...results.map((tenant) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            shape: const Border(),
            leading: CircleAvatar(backgroundColor: primarySoft, child: Text(tenant.initials, style: const TextStyle(color: primary, fontWeight: FontWeight.w800))),
            title: Text(tenant.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Room ${state.tenantRoomLabel(tenant)} · ${tenant.phone}'),
            trailing: StatusPill(tenant.kyc.label),
            children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Column(children: [
              const Divider(),
              _detail(Icons.calendar_today_outlined, 'Joined', formatFullDate(tenant.joinDate)),
              _detail(Icons.description_outlined, 'Agreement', tenant.agreement.label),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.call_outlined), label: const Text('Call'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: () => _agreement(context, state, tenant), icon: const Icon(Icons.draw_outlined), label: const Text('Agreement')))]),
            ]))],
          ),
        )),
      ]),
    );
  }

  Widget _detail(IconData icon, String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Icon(icon, size: 17, color: Colors.black45), const SizedBox(width: 8), Text('$label: ', style: const TextStyle(fontSize: 12)), Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))]));

  void _onboard(BuildContext context, AppState state) {
    if (state.rooms.isEmpty) return;
    final name = TextEditingController();
    final phone = TextEditingController();
    final bed = TextEditingController(text: 'A');
    var roomId = state.rooms.first.id;
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Onboard tenant', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6), const Text('Capture details, verify KYC and send the rental agreement.'),
      const FormLabel('Full name'), TextField(controller: name),
      const FormLabel('Phone number'), TextField(controller: phone, keyboardType: TextInputType.phone),
      const FormLabel('Room'),
      DropdownButtonFormField<String>(
        initialValue: roomId,
        items: state.rooms.map((r) => DropdownMenuItem(value: r.id, child: Text('Room ${r.number} · ${r.type} · ${r.beds - r.occupied} free'))).toList(),
        onChanged: (v) => setModalState(() => roomId = v!),
      ),
      const FormLabel('Bed label'), TextField(controller: bed, decoration: const InputDecoration(hintText: 'e.g. B')),
      const FormLabel('Identity document'), OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.upload_file_outlined), label: const Text('Upload Aadhaar / passport')),
      const FormLabel('Rental agreement'), SwitchListTile(contentPadding: EdgeInsets.zero, value: true, onChanged: (_) {}, title: const Text('Send e-sign request'), subtitle: const Text('Tenant receives a secure signing link')),
      const SizedBox(height: 16), FilledButton(onPressed: () {
        if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
        state.onboardTenant(name: name.text.trim(), phone: phone.text.trim(), roomId: roomId, bed: bed.text.trim().isEmpty ? 'A' : bed.text.trim());
        Navigator.pop(context);
      }, child: const Text('Create & send agreement')),
    ]))));
  }

  void _agreement(BuildContext context, AppState state, Tenant tenant) => showAppSheet(context, Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SheetHandle(),
    const Icon(Icons.verified_outlined, color: primary, size: 54),
    const SizedBox(height: 12), Text('Digital rental agreement', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 8), Text('${tenant.name} · Room ${state.tenantRoomLabel(tenant)}', textAlign: TextAlign.center),
    const SizedBox(height: 22),
    const Card(child: Padding(padding: EdgeInsets.all(16), child: Row(children: [Icon(Icons.description_outlined), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Rental_Agreement.pdf', style: TextStyle(fontWeight: FontWeight.w700)), Text('12 months · E-stamped')]))]))),
    const SizedBox(height: 14), FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.draw_outlined), label: Text(tenant.agreement == AgreementStatus.signed ? 'View signed copy' : 'Send signing reminder')),
  ]));
}

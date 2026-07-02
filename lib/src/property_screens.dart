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
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addPg(context, state), icon: const Icon(Icons.add), label: const Text('Add PG')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        itemCount: state.pgs.length,
        itemBuilder: (context, index) {
          final pg = state.pgs[index];
          final occupancy = ((pg['occupied'] as int) / (pg['beds'] as int) * 100).round();
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 140,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF195F59), Color(0xFF45A497)])),
                child: Stack(children: [
                  const Positioned(right: 20, bottom: -18, child: Icon(Icons.apartment_rounded, size: 150, color: Colors.white10)),
                  Positioned(left: 17, top: 17, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Row(children: [const Icon(Icons.star, color: warning, size: 15), const SizedBox(width: 3), Text('${pg['rating']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))]))),
                  Positioned(right: 10, top: 9, child: IconButton(onPressed: () => _addPg(context, state, existing: pg), icon: const Icon(Icons.edit_outlined, color: Colors.white))),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(17),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pg['name'] as String, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 5),
                  Row(children: [const Icon(Icons.location_on_outlined, size: 16, color: Colors.black45), const SizedBox(width: 4), Expanded(child: Text(pg['address'] as String, style: const TextStyle(fontSize: 12)))]),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: occupancy / 100, minHeight: 7, borderRadius: BorderRadius.circular(8), backgroundColor: primarySoft),
                  const SizedBox(height: 7),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('$occupancy% occupied', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)), Text('${pg['occupied']} of ${pg['beds']} beds', style: const TextStyle(fontSize: 12))]),
                  const Divider(height: 26),
                  Text(pg['amenities'] as String, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _addPg(BuildContext context, AppState state, {Map<String, dynamic>? existing}) {
    final name = TextEditingController(text: existing?['name'] as String?);
    final address = TextEditingController(text: existing?['address'] as String?);
    final beds = TextEditingController(text: '${existing?['beds'] ?? 24}');
    final amenities = TextEditingController(text: existing?['amenities'] as String? ?? 'Wi-Fi • Food • Laundry');
    showAppSheet(context, SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(),
      Text(existing == null ? 'Add a PG property' : 'Edit property', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Property name'), TextField(controller: name, decoration: const InputDecoration(hintText: 'e.g. Nestora Indiranagar')),
      const FormLabel('Full address'), TextField(controller: address, maxLines: 2, decoration: const InputDecoration(hintText: 'Street, area and city')),
      const FormLabel('Total beds'), TextField(controller: beds, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixIcon: Icon(Icons.bed_outlined))),
      const FormLabel('Amenities'), TextField(controller: amenities, maxLines: 2),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add property photos')),
      const SizedBox(height: 18),
      FilledButton(onPressed: () {
        if (name.text.trim().isEmpty || address.text.trim().isEmpty) return;
        final item = <String, dynamic>{'id': existing?['id'] ?? 'p${DateTime.now().millisecondsSinceEpoch}', 'name': name.text.trim(), 'address': address.text.trim(), 'beds': int.tryParse(beds.text) ?? 24, 'occupied': existing?['occupied'] ?? 0, 'amenities': amenities.text.trim(), 'rating': existing?['rating'] ?? 4.5};
        if (existing == null) { state.addItem(state.pgs, item); } else { existing..clear()..addAll(item); state.persistAll(); }
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
    final rooms = state.rooms.where((e) => e['floor'] == floor).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Rooms & beds')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addRoom(context, state), icon: const Icon(Icons.add), label: const Text('Add room')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        const PageHeader(title: 'Bed occupancy', subtitle: 'Live floor-wise availability'),
        const SizedBox(height: 18),
        SegmentedButton<int>(segments: [1, 2, 3].map((f) => ButtonSegment(value: f, label: Text('Floor $f'))).toList(), selected: {floor}, onSelectionChanged: (value) => setState(() => floor = value.first)),
        const SizedBox(height: 18),
        ...rooms.map((room) => Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 48, height: 48, alignment: Alignment.center, decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(13)), child: Text(room['number'] as String, style: const TextStyle(fontWeight: FontWeight.w800, color: primary))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(room['type'] as String, style: Theme.of(context).textTheme.titleMedium), Text('${inr(room['rent'] as int)} / bed / month')])),
                IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
              ]),
              const Divider(height: 25),
              Row(children: [
                for (var bed = 0; bed < (room['beds'] as int); bed++)
                  Expanded(child: Container(
                    margin: EdgeInsets.only(right: bed == (room['beds'] as int) - 1 ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: bed < (room['occupied'] as int) ? primarySoft : const Color(0xFFF1F2F2), borderRadius: BorderRadius.circular(11), border: Border.all(color: bed < (room['occupied'] as int) ? primary.withValues(alpha: .25) : Colors.black12)),
                    child: Column(children: [Icon(Icons.bed_rounded, color: bed < (room['occupied'] as int) ? primary : Colors.black26), const SizedBox(height: 3), Text(bed < (room['occupied'] as int) ? 'Occupied' : 'Available', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: bed < (room['occupied'] as int) ? primary : Colors.black45))]),
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
    final number = TextEditingController();
    final rent = TextEditingController(text: '9000');
    var roomFloor = floor;
    var beds = 2;
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Add a room', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Room number'), TextField(controller: number, decoration: const InputDecoration(hintText: 'e.g. 204')),
      const FormLabel('Floor'), DropdownButtonFormField<int>(initialValue: roomFloor, items: [1,2,3,4,5].map((e) => DropdownMenuItem(value: e, child: Text('Floor $e'))).toList(), onChanged: (v) => setModalState(() => roomFloor = v!)),
      const FormLabel('Sharing type'), DropdownButtonFormField<int>(initialValue: beds, items: const [DropdownMenuItem(value: 1, child: Text('Single')), DropdownMenuItem(value: 2, child: Text('Double sharing')), DropdownMenuItem(value: 3, child: Text('Triple sharing'))], onChanged: (v) => setModalState(() => beds = v!)),
      const FormLabel('Monthly rent per bed'), TextField(controller: rent, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
      const SizedBox(height: 20), FilledButton(onPressed: () {
        if (number.text.trim().isEmpty) return;
        state.addItem(state.rooms, {'id': 'r${DateTime.now().millisecondsSinceEpoch}', 'number': number.text.trim(), 'floor': roomFloor, 'type': beds == 1 ? 'Single' : beds == 2 ? 'Double sharing' : 'Triple sharing', 'rent': int.tryParse(rent.text) ?? 9000, 'beds': beds, 'occupied': 0});
        setState(() => floor = roomFloor); Navigator.pop(context);
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
        : state.tenants.where((e) => '${e['name']} ${e['room']} ${e['phone']}'.toLowerCase().contains(needle)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _onboard(context, state), icon: const Icon(Icons.person_add_alt_1), label: const Text('Onboard')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        PageHeader(title: '${state.tenants.length} active tenants', subtitle: '${state.tenants.where((e) => e['kyc'] == 'Pending').length} KYC pending'),
        const SizedBox(height: 18),
        TextField(onChanged: (value) => setState(() => query = value), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name, room or phone')),
        const SizedBox(height: 14),
        if (results.isEmpty) const EmptyState(icon: Icons.person_search_outlined, title: 'No tenants match your search'),
        ...results.map((tenant) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            shape: const Border(),
            leading: CircleAvatar(backgroundColor: primarySoft, child: Text((tenant['name'] as String).split(' ').map((e) => e[0]).take(2).join(), style: const TextStyle(color: primary, fontWeight: FontWeight.w800))),
            title: Text(tenant['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Room ${tenant['room']} · ${tenant['phone']}'),
            trailing: StatusPill(tenant['kyc'] as String),
            children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Column(children: [
              const Divider(),
              _detail(Icons.calendar_today_outlined, 'Joined', tenant['joinDate'] as String),
              _detail(Icons.description_outlined, 'Agreement', tenant['agreement'] as String),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.call_outlined), label: const Text('Call'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: () => _agreement(context, tenant), icon: const Icon(Icons.draw_outlined), label: const Text('Agreement')))]),
            ]))],
          ),
        )),
      ]),
    );
  }

  Widget _detail(IconData icon, String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Icon(icon, size: 17, color: Colors.black45), const SizedBox(width: 8), Text('$label: ', style: const TextStyle(fontSize: 12)), Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))]));

  void _onboard(BuildContext context, AppState state) {
    final name = TextEditingController();
    final phone = TextEditingController();
    final room = TextEditingController();
    showAppSheet(context, SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Onboard tenant', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6), const Text('Capture details, verify KYC and send the rental agreement.'),
      const FormLabel('Full name'), TextField(controller: name),
      const FormLabel('Phone number'), TextField(controller: phone, keyboardType: TextInputType.phone),
      const FormLabel('Room & bed'), TextField(controller: room, decoration: const InputDecoration(hintText: 'e.g. 202-B')),
      const FormLabel('Identity document'), OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.upload_file_outlined), label: const Text('Upload Aadhaar / passport')),
      const FormLabel('Rental agreement'), SwitchListTile(contentPadding: EdgeInsets.zero, value: true, onChanged: (_) {}, title: const Text('Send e-sign request'), subtitle: const Text('Tenant receives a secure signing link')),
      const SizedBox(height: 16), FilledButton(onPressed: () {
        if (name.text.isEmpty || phone.text.isEmpty) return;
        state.addItem(state.tenants, {'id': 't${DateTime.now().millisecondsSinceEpoch}', 'name': name.text.trim(), 'phone': phone.text.trim(), 'room': room.text.trim(), 'kyc': 'Pending', 'joinDate': '03 Jul 2026', 'agreement': 'Awaiting sign'});
        Navigator.pop(context);
      }, child: const Text('Create & send agreement')),
    ])));
  }

  void _agreement(BuildContext context, Map<String, dynamic> tenant) => showAppSheet(context, Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SheetHandle(),
    const Icon(Icons.verified_outlined, color: primary, size: 54),
    const SizedBox(height: 12), Text('Digital rental agreement', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 8), Text('${tenant['name']} · Room ${tenant['room']}', textAlign: TextAlign.center),
    const SizedBox(height: 22),
    const Card(child: Padding(padding: EdgeInsets.all(16), child: Row(children: [Icon(Icons.description_outlined), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Rental_Agreement.pdf', style: TextStyle(fontWeight: FontWeight.w700)), Text('12 months · E-stamped')]))]))),
    const SizedBox(height: 14), FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.draw_outlined), label: Text(tenant['agreement'] == 'Signed' ? 'View signed copy' : 'Send signing reminder')),
  ]));
}

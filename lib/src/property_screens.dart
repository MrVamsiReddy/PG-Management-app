import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'supabase_config.dart';
import 'theme.dart';
import 'widgets.dart';

class PgListingsScreen extends StatelessWidget {
  const PgListingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ManagerOnly(child: Scaffold(
      appBar: AppBar(title: const Text('PG properties')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _editPg(context, state), icon: const Icon(Icons.add), label: const Text('Add PG')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
        itemCount: state.pgs.length,
        itemBuilder: (context, index) {
          final pg = state.pgs[index];
          final occupancy = pg.beds == 0 ? 0 : (pg.occupied / pg.beds * 100).round();
          final active = state.activePg?.id == pg.id;
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: active
                  ? null
                  : () {
                      state.selectPg(pg.id);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Now managing ${pg.name}')));
                    },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 140,
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF195F59), Color(0xFF45A497)])),
                child: Stack(children: [
                  if (pg.photo != null)
                    Positioned.fill(child: base64Image(pg.photo!))
                  else
                    const Positioned(right: 20, bottom: -18, child: Icon(Icons.apartment_rounded, size: 150, color: Colors.white10)),
                  Positioned(left: 17, top: 17, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Row(children: [const Icon(Icons.star, color: warning, size: 15), const SizedBox(width: 3), Text('${pg.rating}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))]))),
                  Positioned(right: 10, top: 9, child: IconButton(onPressed: () => _editPg(context, state, existing: pg), icon: const Icon(Icons.edit_outlined, color: Colors.white), style: IconButton.styleFrom(backgroundColor: Colors.black26))),
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
                  Row(children: [
                    Expanded(child: Text(pg.amenities, style: const TextStyle(fontSize: 12, color: Colors.black54))),
                    if (active) const StatusPill('Managing') else const Text('Tap to manage', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
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

  void _editPg(BuildContext context, AppState state, {Pg? existing}) {
    final name = TextEditingController(text: existing?.name);
    final address = TextEditingController(text: existing?.address);
    final beds = TextEditingController(text: '${existing?.beds ?? 24}');
    final amenities = TextEditingController(text: existing?.amenities ?? 'Wi-Fi • Food • Laundry');
    String? photo = existing?.photo;
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(),
      Text(existing == null ? 'Add a PG property' : 'Edit property', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Property name'), TextField(controller: name, decoration: const InputDecoration(hintText: 'e.g. Indiranagar PG')),
      const FormLabel('Full address'), TextField(controller: address, maxLines: 2, decoration: const InputDecoration(hintText: 'Street, area and city')),
      const FormLabel('Total beds'), TextField(controller: beds, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixIcon: Icon(Icons.bed_outlined))),
      const FormLabel('Amenities'), TextField(controller: amenities, maxLines: 2),
      const SizedBox(height: 14),
      if (photo != null) ...[
        ClipRRect(borderRadius: BorderRadius.circular(14), child: base64Image(photo!, height: 120)),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        onPressed: () async {
          final picked = await pickImageBase64(context);
          if (picked != null) setModalState(() => photo = picked);
        },
        icon: Icon(photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_outline),
        label: Text(photo == null ? 'Add property photo' : 'Photo added · tap to change'),
      ),
      const SizedBox(height: 18),
      FilledButton(onPressed: () {
        if (name.text.trim().isEmpty || address.text.trim().isEmpty) return;
        final base = existing ?? Pg(id: 'p${DateTime.now().microsecondsSinceEpoch}', name: '', address: '', beds: 0, occupied: 0, amenities: '', rating: 4.5);
        state.savePg(base.copyWith(
          name: name.text.trim(),
          address: address.text.trim(),
          beds: int.tryParse(beds.text) ?? 24,
          amenities: amenities.text.trim(),
          photo: photo,
        ));
        Navigator.pop(context);
      }, child: Text(existing == null ? 'Create property' : 'Save changes')),
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
    final selected = floors.contains(floor) ? floor : (floors.isEmpty ? 1 : floors.first);
    final rooms = state.pgRooms.where((e) => e.floor == selected).toList();
    return ManagerOnly(child: Scaffold(
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
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Add a room', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 6), Text('In ${pg.name} — switch property from the top bar.', style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
        ? state.pgTenants
        : state.pgTenants.where((e) => '${e.name} ${state.tenantRoomLabel(e)} ${e.phone}'.toLowerCase().contains(needle)).toList();
    return ManagerOnly(child: Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _onboard(context, state), icon: const Icon(Icons.person_add_alt_1), label: const Text('Onboard')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        PageHeader(title: '${state.pgTenants.length} active tenants', subtitle: '${state.pgTenants.where((e) => e.kyc == KycStatus.pending).length} KYC pending · ${state.activePg?.name ?? ''}'),
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
              _detail(Icons.verified_user_outlined, 'KYC', tenant.kyc.label),
              const SizedBox(height: 10),
              if (tenant.kycDoc != null) ...[
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _viewKycDoc(context, tenant), icon: const Icon(Icons.badge_outlined), label: const Text('View KYC document'))),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(onPressed: () => _call(tenant.phone), icon: const Icon(Icons.call_outlined), label: const Text('Call tenant')),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton.tonalIcon(onPressed: () => _invite(context, state, tenant), icon: const Icon(Icons.send_outlined), label: const Text('Invite to app'))),
            ]))],
          ),
        )),
      ]),
    ));
  }

  Widget _detail(IconData icon, String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Icon(icon, size: 17, color: Colors.black45), const SizedBox(width: 8), Text('$label: ', style: const TextStyle(fontSize: 12)), Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))]));

  void _call(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    launchUrl(Uri(scheme: 'tel', path: digits));
  }

  void _invite(BuildContext context, AppState state, Tenant tenant) {
    final email = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add ${tenant.name.split(' ').first} to the app'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Their login is created for you, with a one-time password they must replace at first sign-in.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 14),
          TextField(controller: email, autofocus: true, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Tenant email address', prefixIcon: Icon(Icons.mail_outline))),
          const SizedBox(height: 10),
          const Text('Next, the message with the app link and their credentials opens in WhatsApp/SMS/email for you to send.', style: TextStyle(fontSize: 11, color: Colors.black45)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton.icon(onPressed: () async {
            final address = email.text.trim();
            if (!address.contains('@')) return;
            final result = await state.inviteTenant(tenantId: tenant.id, email: address);
            if (dialogContext.mounted) Navigator.pop(dialogContext);
            if (result.error != null) {
              messenger.showSnackBar(SnackBar(content: Text(result.error!)));
              return;
            }
            await _shareInvite(messenger, state, tenant, address, result.tempPassword);
          }, icon: const Icon(Icons.send_outlined), label: const Text('Create login & share')),
        ],
      ),
    );
  }

  Future<void> _shareInvite(ScaffoldMessengerState messenger, AppState state, Tenant tenant, String email, String? tempPassword) async {
    final firstName = tenant.name.split(' ').first;
    final pgName = state.pgNameForTenant(tenant.id);
    final message = tempPassword != null
        ? 'Hi $firstName! Your room at $pgName is now on PG Management.\n\n'
            'Download the app: $apkDownloadUrl\n'
            'Or use the web: $appWebUrl\n\n'
            'Sign in with:\nEmail: $email\nTemporary password: $tempPassword\n\n'
            'You will be asked to set your own password the first time you sign in.'
        : 'Hi $firstName! Your account is now linked to $pgName on PG Management.\n\n'
            'Sign in with this email: $email\n'
            'App: $apkDownloadUrl\nWeb: $appWebUrl\n\n'
            'You will see your room, rent and requests as soon as you sign in.';
    try {
      await SharePlus.instance.share(ShareParams(text: message, subject: 'Your PG Management login'));
    } catch (_) {
      // Share sheet unavailable (e.g. desktop browser): copy instead.
      await Clipboard.setData(ClipboardData(text: message));
      messenger.showSnackBar(const SnackBar(content: Text('Message with the login details copied — paste it into WhatsApp or email.')));
    }
  }

  void _viewKycDoc(BuildContext context, Tenant tenant) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            base64Image(tenant.kycDoc!, fit: BoxFit.contain),
            Padding(padding: const EdgeInsets.all(10), child: Text('${tenant.name} · identity document', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
          ]),
        ),
      );

  void _onboard(BuildContext context, AppState state) {
    final messenger = ScaffoldMessenger.of(context);
    if (state.pgRooms.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('Add a room in ${state.activePg?.name ?? 'this property'} first.')));
      return;
    }
    final available = state.pgRooms.where((r) => r.occupied < r.beds).toList();
    if (available.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text('Every room in ${state.activePg?.name ?? 'this property'} is full. Add a room or free a bed first.')));
      return;
    }

    final formKey = GlobalKey<FormState>();
    final name = TextEditingController();
    final phone = TextEditingController();
    var roomId = available.first.id;
    final bed = TextEditingController(text: state.suggestBed(roomId));
    String? kycDoc;

    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => SingleChildScrollView(
      child: Form(
        key: formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(), Text('Onboard tenant', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6), const Text('Capture details and verify KYC to add a tenant to a room.'),
          const FormLabel('Full name'),
          TextFormField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter the tenant\'s name' : null,
          ),
          const FormLabel('Phone number'),
          TextFormField(
            controller: phone,
            keyboardType: TextInputType.phone,
            validator: (v) => (v == null || v.replaceAll(RegExp(r'[^0-9]'), '').length < 10) ? 'Enter a valid 10-digit number' : null,
          ),
          const FormLabel('Room'),
          DropdownButtonFormField<String>(
            initialValue: roomId,
            // Full rooms are shown but disabled so the owner sees the whole PG.
            items: state.pgRooms.map((r) {
              final free = r.beds - r.occupied;
              final full = free <= 0;
              return DropdownMenuItem(
                value: r.id,
                enabled: !full,
                child: Text(
                  'Room ${r.number} · ${r.type} · ${full ? 'Full' : '$free free'}',
                  style: full ? const TextStyle(color: Colors.black38) : null,
                ),
              );
            }).toList(),
            onChanged: (v) => setModalState(() {
              roomId = v!;
              bed.text = state.suggestBed(roomId); // pre-fill the next free bed
            }),
          ),
          const FormLabel('Bed label'),
          TextFormField(
            controller: bed,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'e.g. B'),
            validator: (v) {
              final b = (v ?? '').trim();
              if (b.isEmpty) return 'Enter a bed label';
              if (state.takenBeds(roomId).contains(b.toUpperCase())) return 'That bed is already taken in this room';
              return null;
            },
          ),
          const FormLabel('Identity document'),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await pickImageBase64(context);
              if (picked != null) setModalState(() => kycDoc = picked);
            },
            icon: Icon(kycDoc == null ? Icons.upload_file_outlined : Icons.check_circle_outline),
            label: Text(kycDoc == null ? 'Upload Aadhaar / passport' : 'Document attached · tap to change'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () {
            if (!formKey.currentState!.validate()) return;
            if (kycDoc == null) {
              messenger.showSnackBar(const SnackBar(content: Text('Upload the identity document to continue.')));
              return;
            }
            final error = state.onboardTenant(name: name.text, phone: phone.text, roomId: roomId, bed: bed.text, kycDoc: kycDoc);
            if (error != null) {
              messenger.showSnackBar(SnackBar(content: Text(error)));
              return;
            }
            Navigator.pop(context);
            messenger.showSnackBar(SnackBar(content: Text('${name.text.trim()} onboarded to room ${state.roomNumber(roomId)}.')));
          }, child: const Text('Onboard tenant')),
        ]),
      ),
    )));
  }
}

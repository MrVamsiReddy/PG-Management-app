import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, this.initialFilter = 'All'});

  /// One of 'All', 'Open', 'In progress', 'Resolved'.
  final String initialFilter;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late String filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final manager = state.role != UserRole.tenant;
    final myRoomId = state.currentTenant?.roomId;
    final mine = manager ? state.pgMaintenance : state.maintenance.where((e) => e.roomId == myRoomId).toList();
    final items = filter == 'All' ? mine : mine.where((e) => e.status.label == filter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _raiseIssue(context, state), icon: const Icon(Icons.add), label: Text(manager ? 'Create request' : 'Raise issue')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        PageHeader(title: manager ? 'Service desk' : 'My requests', subtitle: '${mine.where((e) => e.status != MaintenanceStatus.resolved).length} active · ${mine.where((e) => e.status == MaintenanceStatus.resolved).length} resolved'),
        const SizedBox(height: 16),
        SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: ['All', 'Open', 'In progress', 'Resolved'].map((e) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e), selected: filter == e, onSelected: (_) => setState(() => filter = e)))).toList())),
        const SizedBox(height: 14),
        ...items.map((item) => Card(
          margin: const EdgeInsets.only(bottom: 11),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _details(context, state, item),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [StatusPill(item.priority.label), const Spacer(), StatusPill(item.status.label)]),
              const SizedBox(height: 12), Text(item.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5), Text('${item.category} · Room ${state.roomNumber(item.roomId)} · ${relativeTime(item.createdAt)}', style: const TextStyle(fontSize: 11)),
              const Divider(height: 24),
              Row(children: [CircleAvatar(radius: 13, backgroundColor: primarySoft, child: Icon(item.assignee == null ? Icons.person_add_alt : Icons.person_outline, size: 15, color: primary)), const SizedBox(width: 7), Text(item.assignee ?? 'Unassigned', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), const Spacer(), const Icon(Icons.chevron_right, color: Colors.black38)]),
            ])),
          ),
        )),
        if (items.isEmpty) const EmptyState(icon: Icons.build_outlined, title: 'No requests here'),
      ]),
    );
  }

  void _raiseIssue(BuildContext context, AppState state) {
    if (state.rooms.isEmpty) return;
    final manager = state.role != UserRole.tenant;
    final scoped = manager && state.pgRooms.isNotEmpty ? state.pgRooms : state.rooms;
    final title = TextEditingController();
    var roomId = manager ? scoped.first.id : (state.currentTenant?.roomId ?? state.rooms.first.id);
    var category = 'Plumbing';
    var priority = Priority.medium;
    String? photo;
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Raise maintenance issue', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('What needs fixing?'), TextField(controller: title, maxLines: 2, decoration: const InputDecoration(hintText: 'Describe the issue briefly')),
      const FormLabel('Room'),
      if (manager)
        DropdownButtonFormField<String>(
          initialValue: roomId,
          items: scoped.map((r) => DropdownMenuItem(value: r.id, child: Text('Room ${r.number} · Floor ${r.floor}'))).toList(),
          onChanged: (v) => setModalState(() => roomId = v!),
        )
      else
        TextField(enabled: false, decoration: InputDecoration(hintText: 'Room ${state.roomNumber(roomId)}')),
      const FormLabel('Category'), DropdownButtonFormField<String>(initialValue: category, items: ['Plumbing', 'Electrical', 'Internet', 'Cleaning', 'Furniture', 'Other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setModalState(() => category = v!)),
      const FormLabel('Priority'), SegmentedButton<Priority>(segments: Priority.values.map((e) => ButtonSegment(value: e, label: Text(e.label))).toList(), selected: {priority}, onSelectionChanged: (v) => setModalState(() => priority = v.first)),
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
        label: Text(photo == null ? 'Attach a photo' : 'Photo attached · tap to change'),
      ),
      const SizedBox(height: 18), FilledButton(onPressed: () {
        if (title.text.trim().isEmpty) return;
        state.addMaintenanceRequest(title: title.text.trim(), roomId: roomId, category: category, priority: priority, photo: photo);
        Navigator.pop(context);
      }, child: const Text('Submit request')),
    ]))));
  }

  void _details(BuildContext context, AppState state, MaintenanceRequest item) {
    final manager = state.role != UserRole.tenant;
    final open = item.status == MaintenanceStatus.open;
    final assignee = TextEditingController(text: item.assignee ?? '');
    showAppSheet(context, SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Row(children: [Expanded(child: Text(item.title, style: Theme.of(context).textTheme.headlineMedium)), StatusPill(item.status.label)]),
      const SizedBox(height: 8), Text('${item.category} · Room ${state.roomNumber(item.roomId)} · ${item.priority.label} priority'),
      if (item.photo != null) ...[
        const SizedBox(height: 14),
        ClipRRect(borderRadius: BorderRadius.circular(14), child: base64Image(item.photo!, height: 160)),
      ],
      const SizedBox(height: 24), Text('Status timeline', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 13),
      _timeline('Request created', formatWhen(item.createdAt), true, first: true),
      _timeline('Assigned to technician', item.assignee ?? 'Unassigned', item.status != MaintenanceStatus.open),
      _timeline('Work in progress', 'Technician attending', item.status != MaintenanceStatus.open),
      _timeline('Issue resolved', 'Awaiting completion', item.status == MaintenanceStatus.resolved, last: true),
      if (manager && item.status != MaintenanceStatus.resolved) ...[
        if (open) ...[
          const FormLabel('Assign technician'),
          TextField(controller: assignee, decoration: const InputDecoration(hintText: 'e.g. Ravi Kumar', prefixIcon: Icon(Icons.engineering_outlined))),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: () {
          state.setMaintenanceStatus(
            item.id,
            open ? MaintenanceStatus.inProgress : MaintenanceStatus.resolved,
            assignee: open ? (assignee.text.trim().isEmpty ? 'Ravi Kumar' : assignee.text) : item.assignee,
          );
          Navigator.pop(context);
        }, icon: Icon(open ? Icons.play_arrow_rounded : Icons.check), label: Text(open ? 'Assign & start work' : 'Mark as resolved')),
      ],
    ])));
  }

  Widget _timeline(String title, String subtitle, bool done, {bool first = false, bool last = false}) => IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    SizedBox(width: 28, child: Column(children: [if (!first) Expanded(child: Container(width: 2, color: done ? primary : Colors.black12)), Container(width: 14, height: 14, decoration: BoxDecoration(color: done ? primary : Colors.white, shape: BoxShape.circle, border: Border.all(color: done ? primary : Colors.black26, width: 2))), if (!last) Expanded(child: Container(width: 2, color: done ? primary : Colors.black12))])),
    Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(8, 10, 0, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: done ? ink : Colors.black38)), Text(subtitle, style: const TextStyle(fontSize: 11))]))),
  ]));
}


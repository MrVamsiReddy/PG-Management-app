import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  String filter = 'All';
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final manager = state.role != UserRole.tenant;
    final mine = manager ? state.maintenance : state.maintenance.where((e) => e['room'] == AppState.currentTenantRoom).toList();
    final items = filter == 'All' ? mine : mine.where((e) => e['status'] == filter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Maintenance')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _raiseIssue(context, state), icon: const Icon(Icons.add), label: Text(manager ? 'Create request' : 'Raise issue')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        PageHeader(title: manager ? 'Service desk' : 'My requests', subtitle: '${mine.where((e) => e['status'] != 'Resolved').length} active · ${mine.where((e) => e['status'] == 'Resolved').length} resolved'),
        const SizedBox(height: 16),
        SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, children: ['All', 'Open', 'In progress', 'Resolved'].map((e) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(e), selected: filter == e, onSelected: (_) => setState(() => filter = e)))).toList())),
        const SizedBox(height: 14),
        ...items.map((item) => Card(
          margin: const EdgeInsets.only(bottom: 11),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _details(context, state, item),
            child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [StatusPill(item['priority'] as String), const Spacer(), StatusPill(item['status'] as String)]),
              const SizedBox(height: 12), Text(item['title'] as String, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5), Text('${item['category']} · Room ${item['room']} · ${item['date']}', style: const TextStyle(fontSize: 11)),
              const Divider(height: 24),
              Row(children: [CircleAvatar(radius: 13, backgroundColor: primarySoft, child: Icon(item['assignee'] == 'Unassigned' ? Icons.person_add_alt : Icons.person_outline, size: 15, color: primary)), const SizedBox(width: 7), Text(item['assignee'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), const Spacer(), const Icon(Icons.chevron_right, color: Colors.black38)]),
            ])),
          ),
        )),
      ]),
    );
  }

  void _raiseIssue(BuildContext context, AppState state) {
    final title = TextEditingController();
    final room = TextEditingController(text: state.role == UserRole.tenant ? AppState.currentTenantRoom : '');
    var category = 'Plumbing'; var priority = 'Medium';
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Raise maintenance issue', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('What needs fixing?'), TextField(controller: title, maxLines: 2, decoration: const InputDecoration(hintText: 'Describe the issue briefly')),
      const FormLabel('Room'), TextField(controller: room),
      const FormLabel('Category'), DropdownButtonFormField<String>(initialValue: category, items: ['Plumbing', 'Electrical', 'Internet', 'Cleaning', 'Furniture', 'Other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setModalState(() => category = v!)),
      const FormLabel('Priority'), SegmentedButton<String>(segments: ['Low', 'Medium', 'High'].map((e) => ButtonSegment(value: e, label: Text(e))).toList(), selected: {priority}, onSelectionChanged: (v) => setModalState(() => priority = v.first)),
      const SizedBox(height: 14), OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Attach photos')),
      const SizedBox(height: 18), FilledButton(onPressed: () {
        if (title.text.trim().isEmpty) return;
        state.addItem(state.maintenance, {'id': 'm${DateTime.now().millisecondsSinceEpoch}', 'title': title.text.trim(), 'room': room.text.trim(), 'category': category, 'status': 'Open', 'priority': priority, 'assignee': 'Unassigned', 'date': 'Just now'});
        Navigator.pop(context);
      }, child: const Text('Submit request')),
    ]))));
  }

  void _details(BuildContext context, AppState state, Map<String, dynamic> item) {
    final manager = state.role != UserRole.tenant;
    final open = item['status'] == 'Open';
    final assignee = TextEditingController(text: item['assignee'] == 'Unassigned' ? '' : item['assignee'] as String);
    showAppSheet(context, SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Row(children: [Expanded(child: Text(item['title'] as String, style: Theme.of(context).textTheme.headlineMedium)), StatusPill(item['status'] as String)]),
      const SizedBox(height: 8), Text('${item['category']} · Room ${item['room']} · ${item['priority']} priority'),
      const SizedBox(height: 24), Text('Status timeline', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 13),
      _timeline('Request created', item['date'] as String, true, first: true),
      _timeline('Assigned to technician', item['assignee'] as String, item['status'] != 'Open'),
      _timeline('Work in progress', 'Technician attending', item['status'] == 'In progress' || item['status'] == 'Resolved'),
      _timeline('Issue resolved', 'Awaiting completion', item['status'] == 'Resolved', last: true),
      if (manager && item['status'] != 'Resolved') ...[
        if (open) ...[
          const FormLabel('Assign technician'),
          TextField(controller: assignee, decoration: const InputDecoration(hintText: 'e.g. Ravi Kumar', prefixIcon: Icon(Icons.engineering_outlined))),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: () {
          state.setMaintenanceStatus(item['id'] as String, open ? 'In progress' : 'Resolved', assignee: open ? (assignee.text.trim().isEmpty ? 'Ravi Kumar' : assignee.text) : null);
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

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tenant = state.role == UserRole.tenant;
    final items = tenant ? state.attendance.where((e) => e['name'] == AppState.currentTenantName).toList() : state.attendance;
    final record = state.todayAttendance;
    final checkedIn = state.isCheckedIn;
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 40), children: [
        if (tenant) ...[
          Card(color: ink, child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
            Text(DateFormat('EEEE, dd MMMM').format(DateTime.now()).toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 12),
            Text(record == null ? '—' : (checkedIn ? record['checkIn'] as String : record['checkOut'] as String), style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.white)),
            Text(record == null ? 'Not checked in yet' : (checkedIn ? 'Checked in' : 'Checked out'), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: ink),
              onPressed: () {
                state.toggleCheckIn();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(checkedIn ? 'Checked out successfully' : 'Checked in successfully')));
              },
              icon: Icon(checkedIn ? Icons.logout : Icons.login),
              label: Text(checkedIn ? 'Check out now' : 'Check in now'),
            )),
          ]))),
          const SizedBox(height: 22),
        ],
        PageHeader(title: tenant ? 'My check-in history' : 'Today’s attendance', subtitle: tenant ? 'Your recent access log' : '${items.where((e) => e['status'] == 'In').length} currently inside'),
        const SizedBox(height: 15),
        ...items.map((item) => Card(margin: const EdgeInsets.only(bottom: 9), child: ListTile(
          leading: CircleAvatar(backgroundColor: item['status'] == 'In' ? primarySoft : const Color(0xFFF1F2F2), child: Icon(item['status'] == 'In' ? Icons.login : Icons.logout, color: item['status'] == 'In' ? primary : Colors.black38, size: 20)),
          title: Text(tenant ? item['date'] as String : item['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('In ${item['checkIn']}  ·  Out ${item['checkOut']}'),
          trailing: StatusPill(item['status'] as String),
        ))),
      ]),
    );
  }
}

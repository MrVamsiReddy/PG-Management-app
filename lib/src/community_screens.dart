import 'package:flutter/material.dart';

import 'app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class VisitorsScreen extends StatelessWidget {
  const VisitorsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Visitors')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _addVisitor(context, state), icon: const Icon(Icons.person_add_alt), label: const Text('Add visitor')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        PageHeader(title: 'Visitor log', subtitle: '${state.visitors.where((e) => e['status'] == 'Inside').length} inside · ${state.visitors.where((e) => e['status'] == 'Awaiting approval').length} awaiting approval'),
        const SizedBox(height: 18),
        ...state.visitors.map((visitor) => Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(padding: const EdgeInsets.all(15), child: Column(children: [
            Row(children: [
              const CircleAvatar(backgroundColor: primarySoft, child: Icon(Icons.badge_outlined, color: primary)), const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(visitor['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)), Text('For ${visitor['tenant']} · ${visitor['purpose']}', style: const TextStyle(fontSize: 11))])),
              StatusPill(visitor['status'] as String),
            ]),
            const Divider(height: 23),
            Row(children: [const Icon(Icons.schedule, size: 16, color: Colors.black45), const SizedBox(width: 5), Text(visitor['time'] as String, style: const TextStyle(fontSize: 11)), const Spacer(),
              if (visitor['status'] == 'Awaiting approval') ...[
                TextButton(onPressed: () => state.setVisitorStatus(visitor['id'] as String, 'Declined'), child: const Text('Decline')),
                FilledButton(onPressed: () => state.setVisitorStatus(visitor['id'] as String, 'Inside'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9)), child: const Text('Approve')),
              ] else if (visitor['status'] == 'Inside')
                OutlinedButton(onPressed: () => state.setVisitorStatus(visitor['id'] as String, 'Checked out'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)), child: const Text('Check out')),
            ]),
          ])),
        )),
      ]),
    );
  }

  void _addVisitor(BuildContext context, AppState state) {
    final name = TextEditingController(); final purpose = TextEditingController(); var tenant = state.role == UserRole.tenant ? AppState.currentTenantName : state.tenants.first['name'] as String;
    showAppSheet(context, StatefulBuilder(builder: (context, setModalState) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('Pre-approve visitor', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Visitor name'), TextField(controller: name),
      if (state.role != UserRole.tenant) ...[const FormLabel('Visiting tenant'), DropdownButtonFormField<String>(initialValue: tenant, items: state.tenants.map((e) => DropdownMenuItem(value: e['name'] as String, child: Text(e['name'] as String))).toList(), onChanged: (v) => setModalState(() => tenant = v!))],
      const FormLabel('Purpose'), TextField(controller: purpose, decoration: const InputDecoration(hintText: 'Family, friend, delivery...')),
      const SizedBox(height: 20), FilledButton(onPressed: () {
        if (name.text.trim().isEmpty) return;
        state.addItem(state.visitors, {'id': 'v${DateTime.now().millisecondsSinceEpoch}', 'name': name.text.trim(), 'tenant': tenant, 'purpose': purpose.text.trim(), 'time': 'Expected today', 'status': 'Awaiting approval'}); Navigator.pop(context);
      }, child: const Text('Create visitor pass')),
    ])));
  }
}

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context); final manager = state.role != UserRole.tenant;
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: manager ? FloatingActionButton.extended(onPressed: () => _broadcast(context, state), icon: const Icon(Icons.campaign_outlined), label: const Text('Broadcast')) : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 100), children: [
        const PageHeader(title: 'Community updates', subtitle: 'Important notices from your PG.'), const SizedBox(height: 18),
        ...state.announcements.map((item) => Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: const Color(0xFFF9E8F0), borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.campaign_outlined, color: Color(0xFFB65B87))), const Spacer(), Text(item['date'] as String, style: const TextStyle(fontSize: 11, color: Colors.black45))]),
          const SizedBox(height: 13), Text(item['title'] as String, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 6), Text(item['body'] as String),
          const Divider(height: 25), Text('Posted by ${item['author']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: primary)),
        ])))),
      ]),
    );
  }

  void _broadcast(BuildContext context, AppState state) {
    final title = TextEditingController(); final body = TextEditingController();
    showAppSheet(context, SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetHandle(), Text('New announcement', style: Theme.of(context).textTheme.headlineMedium),
      const FormLabel('Title'), TextField(controller: title, decoration: const InputDecoration(hintText: 'Keep it clear and brief')),
      const FormLabel('Message'), TextField(controller: body, maxLines: 5, decoration: const InputDecoration(hintText: 'Write the update for your tenants...')),
      const FormLabel('Audience'), DropdownButtonFormField<String>(initialValue: 'All tenants', items: ['All tenants', 'Nestora HSR only', 'Nestora Koramangala only'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (_) {}),
      const SizedBox(height: 16), SwitchListTile(contentPadding: EdgeInsets.zero, value: true, onChanged: (_) {}, title: const Text('Send push notification'), subtitle: const Text('Notify tenants immediately')),
      const SizedBox(height: 12), FilledButton.icon(onPressed: () {
        if (title.text.trim().isEmpty || body.text.trim().isEmpty) return;
        state.publishAnnouncement(title.text.trim(), body.text.trim()); Navigator.pop(context);
      }, icon: const Icon(Icons.send_outlined), label: const Text('Publish announcement')),
    ])));
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [TextButton(onPressed: () { for (final n in state.notifications) { n['read'] = true; } state.persistAll(); }, child: const Text('Mark all read'))]),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        itemCount: state.notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 9),
        itemBuilder: (context, index) {
          final item = state.notifications[index];
          return Card(color: item['read'] == false ? primarySoft.withValues(alpha: .55) : Colors.white, child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            leading: CircleAvatar(backgroundColor: Colors.white, child: Icon(notificationIcon(item['type'] as String), color: primary, size: 21)),
            title: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${item['body']}\n${item['time']}', maxLines: 2),
            isThreeLine: true,
            trailing: item['read'] == false ? Container(width: 8, height: 8, decoration: const BoxDecoration(color: coral, shape: BoxShape.circle)) : null,
            onTap: () { item['read'] = true; state.persistAll(); },
          ));
        },
      ),
    );
  }
}

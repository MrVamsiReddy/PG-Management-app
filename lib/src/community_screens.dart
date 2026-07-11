import 'package:flutter/material.dart';

import 'app_state.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

class VisitorsScreen extends StatelessWidget {
  const VisitorsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tenant = state.role == UserRole.tenant;
    // Tenants see their own visitors; managers see the active property's log.
    final entries = tenant
        ? state.visitors
            .where((v) => v.tenantId == state.currentTenantId)
            .toList()
        : state.pgVisitors;
    return Scaffold(
      appBar: AppBar(title: const Text('Visitors')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addVisitor(context, state),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add visitor')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            PageHeader(
                title: 'Visitor log',
                subtitle:
                    '${entries.where((e) => e.status == VisitorStatus.inside).length} inside · ${entries.where((e) => e.status == VisitorStatus.awaitingApproval).length} awaiting approval'),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              const EmptyState(
                  icon: Icons.badge_outlined, title: 'No visitors yet'),
            ...entries.map((visitor) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(children: [
                        Row(children: [
                          CircleAvatar(
                              backgroundColor: softTint,
                              child: const Icon(Icons.badge_outlined,
                                  color: primary)),
                          const SizedBox(width: 11),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(visitor.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                                Text(
                                    'For ${state.tenantName(visitor.tenantId)} · ${visitor.purpose}',
                                    style: const TextStyle(fontSize: 11))
                              ])),
                          StatusPill(visitor.status.label),
                        ]),
                        const Divider(height: 23),
                        Row(children: [
                          Icon(Icons.schedule, size: 16, color: subtle),
                          const SizedBox(width: 5),
                          Text(formatWhen(visitor.expectedAt),
                              style: const TextStyle(fontSize: 11)),
                          const Spacer(),
                          if (visitor.status ==
                              VisitorStatus.awaitingApproval) ...[
                            TextButton(
                                onPressed: () => state.setVisitorStatus(
                                    visitor.id, VisitorStatus.declined),
                                child: const Text('Decline')),
                            FilledButton(
                                onPressed: () => state.setVisitorStatus(
                                    visitor.id, VisitorStatus.inside),
                                style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 13, vertical: 9)),
                                child: const Text('Approve')),
                          ] else if (visitor.status == VisitorStatus.inside)
                            OutlinedButton(
                                onPressed: () => state.setVisitorStatus(
                                    visitor.id, VisitorStatus.checkedOut),
                                style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8)),
                                child: const Text('Check out')),
                        ]),
                      ])),
                )),
          ]),
    );
  }

  void _addVisitor(BuildContext context, AppState state) {
    final manager = state.role != UserRole.tenant;
    final scoped =
        manager && state.pgTenants.isNotEmpty ? state.pgTenants : state.tenants;
    if (scoped.isEmpty) return;
    final name = TextEditingController();
    final purpose = TextEditingController();
    var tenantId = manager ? scoped.first.id : state.currentTenantId;
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, setModalState) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SheetHandle(),
                      Text('Pre-approve visitor',
                          style: Theme.of(context).textTheme.headlineMedium),
                      const FormLabel('Visitor name'),
                      TextField(controller: name),
                      if (state.role != UserRole.tenant) ...[
                        const FormLabel('Visiting tenant'),
                        DropdownButtonFormField<String>(
                            initialValue: tenantId,
                            items: scoped
                                .map((e) => DropdownMenuItem(
                                    value: e.id, child: Text(e.name)))
                                .toList(),
                            onChanged: (v) =>
                                setModalState(() => tenantId = v!)),
                      ],
                      const FormLabel('Purpose'),
                      TextField(
                          controller: purpose,
                          decoration: const InputDecoration(
                              hintText: 'Family, friend, delivery...')),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: () {
                            if (name.text.trim().isEmpty) return;
                            state.addVisitor(
                                name: name.text.trim(),
                                tenantId: tenantId,
                                purpose: purpose.text.trim().isEmpty
                                    ? 'Visit'
                                    : purpose.text.trim());
                            Navigator.pop(context);
                          },
                          child: const Text('Create visitor pass')),
                    ])));
  }
}

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final manager = state.role != UserRole.tenant;
    final items = state.visibleAnnouncements;
    return Scaffold(
      appBar: AppBar(title: Text(l.t('ann.title'))),
      floatingActionButton: manager
          ? FloatingActionButton.extended(
              onPressed: () => _broadcast(context, state, l),
              icon: const Icon(Icons.campaign_outlined),
              label: Text(l.t('ann.broadcast')))
          : null,
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            PageHeader(
                title: l.t('ann.title'), subtitle: l.t('ann.communitySub')),
            const SizedBox(height: 18),
            if (items.isEmpty)
              EmptyState(
                  icon: Icons.campaign_outlined, title: l.t('ann.empty')),
            ...items.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _detail(context, state, l, item),
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFF9E8F0),
                                        borderRadius:
                                            BorderRadius.circular(11)),
                                    child: const Icon(Icons.campaign_outlined,
                                        color: Color(0xFFB65B87))),
                                const Spacer(),
                                if (item.pgId != null) ...[
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: softTint,
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Text(
                                          state.pgById(item.pgId!)?.name ?? '',
                                          style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: primary))),
                                  const SizedBox(width: 8),
                                ],
                                Text(relativeTime(item.postedAt),
                                    style:
                                        TextStyle(fontSize: 11, color: subtle)),
                              ]),
                              const SizedBox(height: 13),
                              Text(item.title,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 6),
                              Text(item.body,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              const Divider(height: 25),
                              Text('${l.t('ann.postedBy')} ${item.author}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color: primary)),
                            ])),
                  ),
                )),
          ]),
    );
  }

  void _detail(BuildContext context, AppState state, AppLocalizations l,
      Announcement item) {
    showAppSheet(
        context,
        SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SheetHandle(),
          Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFF9E8F0),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.campaign_outlined,
                    color: Color(0xFFB65B87))),
            const SizedBox(width: 12),
            Expanded(
                child: Text(item.title,
                    style: Theme.of(context).textTheme.headlineMedium)),
          ]),
          const SizedBox(height: 6),
          Text(
              '${item.pgId == null ? l.t('ann.audienceAll') : state.pgById(item.pgId!)?.name ?? ''} · ${relativeTime(item.postedAt)}',
              style: TextStyle(fontSize: 12, color: subtle)),
          const SizedBox(height: 16),
          Text(item.body, style: const TextStyle(height: 1.4)),
          const Divider(height: 30),
          Text('${l.t('ann.postedBy')} ${item.author}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12, color: primary)),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.t('common.close'))),
        ])));
  }

  void _broadcast(BuildContext context, AppState state, AppLocalizations l) {
    final title = TextEditingController();
    final body = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    // Audience: null = all tenants, or a specific property id.
    String? audience;
    var sendPush = true;
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, setSheet) => SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const SheetHandle(),
                      Text(l.t('ann.new'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      FormLabel(l.t('ann.titleLabel')),
                      TextField(
                          controller: title,
                          decoration: const InputDecoration(
                              hintText: 'Keep it clear and brief')),
                      FormLabel(l.t('ann.messageLabel')),
                      TextField(
                          controller: body,
                          maxLines: 5,
                          decoration: const InputDecoration(
                              hintText:
                                  'Write the update for your tenants...')),
                      FormLabel(l.t('ann.audience')),
                      DropdownButtonFormField<String?>(
                        initialValue: audience,
                        items: [
                          DropdownMenuItem(
                              value: null, child: Text(l.t('ann.audienceAll'))),
                          ...state.pgs.map((e) => DropdownMenuItem(
                              value: e.id, child: Text('${e.name} only'))),
                        ],
                        onChanged: (v) => setSheet(() => audience = v),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: sendPush,
                          onChanged: (v) => setSheet(() => sendPush = v),
                          title: Text(l.t('ann.sendPush')),
                          subtitle: Text(l.t('ann.sendPushSub'))),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                          onPressed: () {
                            if (title.text.trim().isEmpty ||
                                body.text.trim().isEmpty) {
                              messenger.showSnackBar(SnackBar(
                                  content: Text(l.t('ann.validation'))));
                              return;
                            }
                            state.publishAnnouncement(
                                title.text.trim(), body.text.trim(),
                                pgId: audience, sendPush: sendPush);
                            Navigator.pop(context);
                            messenger.showSnackBar(
                                SnackBar(content: Text(l.t('ann.published'))));
                          },
                          icon: const Icon(Icons.send_outlined),
                          label: Text(l.t('ann.publish'))),
                    ]))));
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    // Tenants see only their own + workspace notifications; managers see the
    // active property's managerial and workspace notifications.
    final items = state.visibleNotifications;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        TextButton(
            onPressed: state.markAllNotificationsRead,
            child: const Text('Mark all read'))
      ]),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No notifications yet')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                    color: item.read
                        ? Colors.white
                        : softTint.withValues(alpha: .55),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 8),
                      leading: CircleAvatar(
                          backgroundColor: Colors.white,
                          child: Icon(notificationIcon(item.type),
                              color: primary, size: 21)),
                      title: Text(item.title,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '${item.body}\n${relativeTime(item.createdAt)}',
                          maxLines: 2),
                      isThreeLine: true,
                      trailing: item.read
                          ? null
                          : Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: coral, shape: BoxShape.circle)),
                      onTap: () => state.markNotificationRead(item.id),
                    ));
              },
            ),
    );
  }
}

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
      appBar:
          AppBar(title: Text(AppLocalizations.of(context).t('nav.visitors'))),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _addVisitor(context, state),
          icon: const Icon(Icons.person_add_alt),
          label: Text(AppLocalizations.of(context).t('qa.addVisitor'))),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            PageHeader(
                title: AppLocalizations.of(context).t('vis.log'),
                subtitle:
                    '${entries.where((e) => e.status == VisitorStatus.inside).length} ${AppLocalizations.of(context).t('status.inside').toLowerCase()} · ${entries.where((e) => e.status == VisitorStatus.awaitingApproval).length} ${AppLocalizations.of(context).t('status.awaiting').toLowerCase()}'),
            const SizedBox(height: 18),
            if (entries.isEmpty)
              EmptyState(
                  icon: Icons.badge_outlined,
                  title: AppLocalizations.of(context).t('vis.none')),
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
                                    '${AppLocalizations.of(context).t('vis.forTenant')} ${state.tenantName(visitor.tenantId)} · ${visitor.purpose}',
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
                                child: Text(AppLocalizations.of(context)
                                    .t('vis.decline'))),
                            FilledButton(
                                onPressed: () => state.setVisitorStatus(
                                    visitor.id, VisitorStatus.inside),
                                style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 13, vertical: 9)),
                                child: Text(AppLocalizations.of(context)
                                    .t('vis.approve'))),
                          ] else if (visitor.status == VisitorStatus.inside)
                            OutlinedButton(
                                onPressed: () => state.setVisitorStatus(
                                    visitor.id, VisitorStatus.checkedOut),
                                style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8)),
                                child: Text(AppLocalizations.of(context)
                                    .t('vis.checkOut'))),
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
                      Text(AppLocalizations.of(context).t('vis.preApprove'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      FormLabel(AppLocalizations.of(context).t('vis.name')),
                      TextField(controller: name),
                      if (state.role != UserRole.tenant) ...[
                        FormLabel(
                            AppLocalizations.of(context).t('vis.visiting')),
                        DropdownButtonFormField<String>(
                            initialValue: tenantId,
                            items: scoped
                                .map((e) => DropdownMenuItem(
                                    value: e.id, child: Text(e.name)))
                                .toList(),
                            onChanged: (v) =>
                                setModalState(() => tenantId = v!)),
                      ],
                      FormLabel(AppLocalizations.of(context).t('vis.purpose')),
                      TextField(
                          controller: purpose,
                          decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)
                                  .t('vis.purposeHint'))),
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
                          child: Text(AppLocalizations.of(context)
                              .t('vis.createPass'))),
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
                                        color:
                                            Colors.pink.withValues(alpha: .12),
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
                    color: Colors.pink.withValues(alpha: .12),
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
                          decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)
                                  .t('ann.titleHint'))),
                      FormLabel(l.t('ann.messageLabel')),
                      TextField(
                          controller: body,
                          maxLines: 5,
                          decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)
                                  .t('ann.bodyHint'))),
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
      appBar: AppBar(
          title: Text(AppLocalizations.of(context).t('nav.notifications')),
          actions: [
            TextButton(
                onPressed: state.markAllNotificationsRead,
                child: Text(AppLocalizations.of(context).t('ntf.markAll')))
          ]),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.notifications_none_rounded,
              title: AppLocalizations.of(context).t('ntf.none'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final item = items[index];
                return Card(
                    color: item.read
                        ? surfaceCard
                        : softTint.withValues(alpha: .55),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 8),
                      leading: CircleAvatar(
                          backgroundColor: surfaceCard,
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

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'l10n.dart';
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
    final mine = manager
        ? state.pgMaintenance
        : state.maintenance.where((e) => e.roomId == myRoomId).toList();
    final items = filter == 'All'
        ? mine
        : mine.where((e) => e.status.label == filter).toList();
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).t('mnt.title'))),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _raiseIssue(context, state),
          icon: const Icon(Icons.add),
          label: Text(manager
              ? AppLocalizations.of(context).t('mnt.create')
              : AppLocalizations.of(context).t('qa.raiseIssue'))),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
          children: [
            PageHeader(
                title: manager
                    ? AppLocalizations.of(context).t('mnt.desk')
                    : AppLocalizations.of(context).t('nav.myRequests'),
                subtitle:
                    '${mine.where((e) => e.status != MaintenanceStatus.resolved).length} active · ${mine.where((e) => e.status == MaintenanceStatus.resolved).length} resolved'),
            const SizedBox(height: 16),
            SizedBox(
                height: 38,
                child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: ['All', 'Open', 'In progress', 'Resolved']
                        .map((e) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                                label: Text(
                                    AppLocalizations.of(context).status(e)),
                                selected: filter == e,
                                onSelected: (_) => setState(() => filter = e))))
                        .toList())),
            const SizedBox(height: 14),
            ...items.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 11),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _details(context, state, item),
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                StatusPill(item.priority.label),
                                const Spacer(),
                                StatusPill(item.status.label)
                              ]),
                              const SizedBox(height: 12),
                              Text(item.title,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 5),
                              Text(
                                  '${item.category} · Room ${state.roomNumber(item.roomId)} · ${relativeTime(item.createdAt)}',
                                  style: const TextStyle(fontSize: 11)),
                              const Divider(height: 24),
                              Row(children: [
                                CircleAvatar(
                                    radius: 13,
                                    backgroundColor: softTint,
                                    child: Icon(
                                        item.assignee == null
                                            ? Icons.person_add_alt
                                            : Icons.person_outline,
                                        size: 15,
                                        color: primary)),
                                const SizedBox(width: 7),
                                Text(
                                    item.assignee ??
                                        AppLocalizations.of(context)
                                            .t('mnt.unassigned'),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                                const Spacer(),
                                Icon(Icons.chevron_right, color: subtle)
                              ]),
                            ])),
                  ),
                )),
            if (items.isEmpty)
              EmptyState(
                  icon: Icons.build_outlined,
                  title: AppLocalizations.of(context).t('mnt.none')),
          ]),
    );
  }

  void _raiseIssue(BuildContext context, AppState state) {
    if (state.rooms.isEmpty) return;
    final manager = state.role != UserRole.tenant;
    final scoped =
        manager && state.pgRooms.isNotEmpty ? state.pgRooms : state.rooms;
    final title = TextEditingController();
    var roomId = manager
        ? scoped.first.id
        : (state.currentTenant?.roomId ?? state.rooms.first.id);
    var category = 'Plumbing';
    var priority = Priority.medium;
    String? photo;
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, setModalState) => SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const SheetHandle(),
                      Text(AppLocalizations.of(context).t('mnt.raiseTitle'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      FormLabel(AppLocalizations.of(context).t('mnt.what')),
                      TextField(
                          controller: title,
                          maxLines: 2,
                          decoration: InputDecoration(
                              hintText: AppLocalizations.of(context)
                                  .t('mnt.describe'))),
                      FormLabel(AppLocalizations.of(context).t('common.room')),
                      if (manager)
                        DropdownButtonFormField<String>(
                          initialValue: roomId,
                          items: scoped
                              .map((r) => DropdownMenuItem(
                                  value: r.id,
                                  child: Text(
                                      'Room ${r.number} · Floor ${r.floor}')))
                              .toList(),
                          onChanged: (v) => setModalState(() => roomId = v!),
                        )
                      else
                        TextField(
                            enabled: false,
                            decoration: InputDecoration(
                                hintText: 'Room ${state.roomNumber(roomId)}')),
                      FormLabel(AppLocalizations.of(context).t('mnt.category')),
                      DropdownButtonFormField<String>(
                          initialValue: category,
                          items: [
                            'Plumbing',
                            'Electrical',
                            'Internet',
                            'Cleaning',
                            'Furniture',
                            'Other'
                          ]
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setModalState(() => category = v!)),
                      FormLabel(AppLocalizations.of(context).t('mnt.priority')),
                      SegmentedButton<Priority>(
                          segments: Priority.values
                              .map((e) =>
                                  ButtonSegment(value: e, label: Text(e.label)))
                              .toList(),
                          selected: {priority},
                          onSelectionChanged: (v) =>
                              setModalState(() => priority = v.first)),
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
                            ? AppLocalizations.of(context).t('mnt.attach')
                            : AppLocalizations.of(context).t('mnt.attached')),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                          onPressed: () {
                            if (title.text.trim().isEmpty) return;
                            state.addMaintenanceRequest(
                                title: title.text.trim(),
                                roomId: roomId,
                                category: category,
                                priority: priority,
                                photo: photo);
                            Navigator.pop(context);
                          },
                          child: Text(
                              AppLocalizations.of(context).t('mnt.submit'))),
                    ]))));
  }

  void _details(BuildContext context, AppState state, MaintenanceRequest item) {
    final manager = state.role != UserRole.tenant;
    final open = item.status == MaintenanceStatus.open;
    final assignee = TextEditingController(text: item.assignee ?? '');
    showAppSheet(
        context,
        SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              const SheetHandle(),
              Row(children: [
                Expanded(
                    child: Text(item.title,
                        style: Theme.of(context).textTheme.headlineMedium)),
                StatusPill(item.status.label)
              ]),
              const SizedBox(height: 8),
              Text(
                  '${item.category} · Room ${state.roomNumber(item.roomId)} · ${item.priority.label} priority'),
              if (item.photo != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: base64Image(item.photo!, height: 160)),
              ],
              const SizedBox(height: 24),
              Text(AppLocalizations.of(context).t('mnt.timeline'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 13),
              _timeline(AppLocalizations.of(context).t('mnt.created'),
                  formatWhen(item.createdAt), true,
                  first: true),
              _timeline(
                  AppLocalizations.of(context).t('mnt.assigned'),
                  item.assignee ??
                      AppLocalizations.of(context).t('mnt.unassigned'),
                  item.status != MaintenanceStatus.open),
              _timeline(
                  AppLocalizations.of(context).t('mnt.working'),
                  AppLocalizations.of(context).t('mnt.attending'),
                  item.status != MaintenanceStatus.open),
              _timeline(
                  AppLocalizations.of(context).t('mnt.resolvedStep'),
                  AppLocalizations.of(context).t('mnt.awaitDone'),
                  item.status == MaintenanceStatus.resolved,
                  last: true),
              if (manager && item.status != MaintenanceStatus.resolved) ...[
                if (open) ...[
                  FormLabel(AppLocalizations.of(context).t('mnt.assignTech')),
                  TextField(
                      controller: assignee,
                      decoration: const InputDecoration(
                          hintText: 'e.g. Ravi Kumar',
                          prefixIcon: Icon(Icons.engineering_outlined))),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                    onPressed: () {
                      state.setMaintenanceStatus(
                        item.id,
                        open
                            ? MaintenanceStatus.inProgress
                            : MaintenanceStatus.resolved,
                        assignee: open
                            ? (assignee.text.trim().isEmpty
                                ? 'Ravi Kumar'
                                : assignee.text)
                            : item.assignee,
                      );
                      Navigator.pop(context);
                    },
                    icon: Icon(open ? Icons.play_arrow_rounded : Icons.check),
                    label: Text(open
                        ? AppLocalizations.of(context).t('mnt.assignStart')
                        : AppLocalizations.of(context).t('mnt.markResolved'))),
              ],
            ])));
  }

  Widget _timeline(String title, String subtitle, bool done,
          {bool first = false, bool last = false}) =>
      IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
            width: 28,
            child: Column(children: [
              if (!first)
                Expanded(
                    child:
                        Container(width: 2, color: done ? primary : hairline)),
              Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                      color: done ? primary : surfaceCard,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: done ? primary : faint, width: 2))),
              if (!last)
                Expanded(
                    child:
                        Container(width: 2, color: done ? primary : hairline))
            ])),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 0, 18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: done ? ink : subtle)),
                      Text(subtitle, style: const TextStyle(fontSize: 11))
                    ]))),
      ]));
}

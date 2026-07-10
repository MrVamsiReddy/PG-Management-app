import 'package:flutter/material.dart';

import 'app_state.dart';
import 'dashboard_screen.dart';
import 'l10n.dart';
import 'module_screens.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    // Each role gets its own navigation: tenants never see management
    // surfaces. Platform admins are routed to CustomerManagementScreen before
    // reaching HomeShell — they never manage PGs here.
    final (pages, destinations) = switch (state.role) {
      UserRole.tenant => (
          const <Widget>[
            DashboardScreen(),
            PaymentsScreen(),
            MaintenanceScreen(),
            VisitorsScreen(),
            ProfileScreen()
          ],
          <NavigationDestination>[
            NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home_rounded),
                label: l.t('nav.home')),
            NavigationDestination(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: const Icon(Icons.account_balance_wallet),
                label: l.t('nav.myRent')),
            NavigationDestination(
                icon: const Icon(Icons.build_outlined),
                selectedIcon: const Icon(Icons.build),
                label: l.t('nav.myRequests')),
            NavigationDestination(
                icon: const Icon(Icons.badge_outlined),
                selectedIcon: const Icon(Icons.badge),
                label: l.t('nav.visitors')),
            NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: l.t('nav.profile')),
          ],
        ),
      UserRole.admin || UserRole.owner => (
          const <Widget>[
            DashboardScreen(),
            ModulesHubScreen(),
            PaymentsScreen(),
            MaintenanceScreen(),
            ProfileScreen()
          ],
          <NavigationDestination>[
            NavigationDestination(
                icon: const Icon(Icons.space_dashboard_outlined),
                selectedIcon: const Icon(Icons.space_dashboard_rounded),
                label: l.t('nav.dashboard')),
            NavigationDestination(
                icon: const Icon(Icons.grid_view_outlined),
                selectedIcon: const Icon(Icons.grid_view_rounded),
                label: l.t('nav.manage')),
            NavigationDestination(
                icon: const Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: const Icon(Icons.account_balance_wallet),
                label: l.t('nav.rent')),
            NavigationDestination(
                icon: const Icon(Icons.build_outlined),
                selectedIcon: const Icon(Icons.build),
                label: l.t('nav.requests')),
            NavigationDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: l.t('nav.profile')),
          ],
        ),
    };
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(
          key: ValueKey('${state.role.name}-$index'), child: pages[index]),
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: canvas,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: primary, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.apartment_rounded,
                color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          // Owners work one property at a time: the title doubles as the
          // property switcher. Tenants just see the app name.
          if (state.role != UserRole.tenant && state.activePg != null)
            Flexible(
              child: PopupMenuButton<String>(
                tooltip: 'Switch property',
                onSelected: state.selectPg,
                itemBuilder: (_) => state.pgs
                    .map((p) => PopupMenuItem(
                        value: p.id,
                        child: Row(children: [
                          if (p.id == state.activePg!.id)
                            const Icon(Icons.check, size: 16, color: primary)
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(p.name,
                                  overflow: TextOverflow.ellipsis)),
                        ])))
                    .toList(),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: Text(state.activePg!.name,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(letterSpacing: -.7))),
                  const Icon(Icons.arrow_drop_down),
                ]),
              ),
            )
          else
            Flexible(
                child: Text('PG Management',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(letterSpacing: -.7))),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: primarySoft, borderRadius: BorderRadius.circular(8)),
            child: Text(state.role.label,
                style: const TextStyle(
                    color: primary, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ]),
        actions: [
          Stack(children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen())),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            if (state.hasUnread)
              Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: coral, shape: BoxShape.circle))),
          ]),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                backgroundColor: Colors.white,
                selectedIndex: index,
                onDestinationSelected: (value) => setState(() => index = value),
                labelType: NavigationRailLabelType.all,
                destinations: destinations
                    .map((e) => NavigationRailDestination(
                        icon: e.icon,
                        selectedIcon: e.selectedIcon,
                        label: Text(e.label)))
                    .toList(),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ])
          : content,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => index = value),
              destinations: destinations,
            ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    final tenant = state.role == UserRole.tenant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        const SizedBox(height: 6),
        CircleAvatar(
          radius: 43,
          backgroundColor: primarySoft,
          child: Text(state.initials,
              style: const TextStyle(
                  fontSize: 25, fontWeight: FontWeight.w800, color: primary)),
        ),
        const SizedBox(height: 13),
        Center(
            child: Text(state.displayName,
                style: Theme.of(context).textTheme.titleLarge)),
        if (state.accountEmail != null)
          Center(
              child: Text(state.accountEmail!,
                  style: const TextStyle(fontSize: 12, color: Colors.black45))),
        Center(
            child: Text(tenant
                ? '${state.role.label} · Room ${state.currentTenantRoomLabel} · ${state.pgNameForTenant(state.currentTenantId)}'
                : '${state.role.label} · ${state.pgs.isEmpty ? 'PG Management' : state.pgs.first.name}')),
        const SizedBox(height: 28),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            _profileTile(Icons.person_outline, l.t('profile.personal'),
                state.profilePhone ?? l.t('profile.personalSub'),
                onTap: () => _editPersonal(context, state, l)),
            _profileTile(
                Icons.verified_user_outlined,
                l.t('profile.kyc'),
                tenant
                    ? 'Aadhaar ${state.currentTenant?.kyc.label.toLowerCase() ?? 'pending'}'
                    : l.t('profile.businessDetails'),
                onTap: tenant ? () => _kyc(context, state, l) : null),
            _profileTile(Icons.settings_outlined, l.t('profile.settings'),
                l.t('profile.settingsSub'),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()))),
            _profileTile(
                Icons.help_outline, l.t('profile.help'), l.t('profile.helpSub'),
                onTap: () => _help(context, l)),
          ]),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: state.logout,
          icon: const Icon(Icons.logout),
          label: Text(l.t('common.signOut')),
          style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC94444),
              padding: const EdgeInsets.all(15)),
        ),
        const SizedBox(height: 16),
        const Center(
            child: Text('PG Management v3.0',
                style: TextStyle(fontSize: 11, color: Colors.black38))),
      ],
    );
  }

  Widget _profileTile(IconData icon, String title, String subtitle,
          {VoidCallback? onTap}) =>
      ListTile(
        onTap: onTap,
        leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: primary, size: 21)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      );

  void _editPersonal(BuildContext context, AppState state, AppLocalizations l) {
    final tenant = state.role == UserRole.tenant;
    final name = TextEditingController(text: state.displayName);
    final phone = TextEditingController(text: state.profilePhone ?? '');
    final messenger = ScaffoldMessenger.of(context);
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SheetHandle(),
                      Text(l.t('profile.personal'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      const FormLabel('Full name'),
                      TextField(
                          controller: name,
                          textCapitalization: TextCapitalization.words),
                      if (tenant) ...[
                        const FormLabel('Phone number'),
                        TextField(
                            controller: phone,
                            keyboardType: TextInputType.phone),
                      ],
                      if (state.accountEmail != null) ...[
                        const FormLabel('Email'),
                        TextField(
                            controller:
                                TextEditingController(text: state.accountEmail),
                            enabled: false),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: () async {
                            final error = await state.updatePersonalDetails(
                                name: name.text,
                                phone: tenant ? phone.text : null);
                            if (context.mounted) Navigator.pop(context);
                            messenger.showSnackBar(SnackBar(
                                content: Text(error ?? l.t('settings.saved'))));
                          },
                          child: Text(l.t('common.save'))),
                    ])));
  }

  void _kyc(BuildContext context, AppState state, AppLocalizations l) {
    final doc = state.currentTenant?.kycDoc;
    final messenger = ScaffoldMessenger.of(context);
    showAppSheet(
        context,
        StatefulBuilder(
            builder: (context, setSheet) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SheetHandle(),
                      Text(l.t('profile.kyc'),
                          style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Text(
                          'Aadhaar ${state.currentTenant?.kyc.label.toLowerCase() ?? 'pending'}',
                          style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 14),
                      if (doc != null) ...[
                        ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: base64Image(doc, height: 180)),
                        const SizedBox(height: 12),
                      ] else
                        const EmptyState(
                            icon: Icons.badge_outlined,
                            title: 'No document uploaded yet'),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await pickImageBase64(context);
                          if (picked == null) return;
                          await state.updateKycDoc(picked);
                          if (context.mounted) Navigator.pop(context);
                          messenger.showSnackBar(
                              SnackBar(content: Text(l.t('settings.saved'))));
                        },
                        icon: Icon(doc == null
                            ? Icons.upload_file_outlined
                            : Icons.cached),
                        label: Text(doc == null
                            ? 'Upload document'
                            : 'Replace document'),
                      ),
                    ])));
  }

  void _help(BuildContext context, AppLocalizations l) {
    showAppSheet(
        context,
        Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Text(l.t('help.title'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(l.t('help.intro'),
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.mail_outline, color: primary),
                title: Text(l.t('help.email')),
                subtitle: const Text('support@pgmanagement.app'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.call_outlined, color: primary),
                title: Text(l.t('help.call')),
                subtitle: const Text('+91 98765 43210'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.t('common.close'))),
            ]));
  }
}

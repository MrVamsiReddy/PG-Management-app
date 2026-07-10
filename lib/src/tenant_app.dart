import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'auth_screen.dart';
import 'community_screens.dart';
import 'finance_screens.dart';
import 'l10n.dart';
import 'operations_screens.dart';
import 'settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class TenantApp extends StatelessWidget {
  const TenantApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'PG Management',
          theme: buildAppTheme(),
          locale: state.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _home(),
        ),
      ),
    );
  }

  Widget _home() {
    if (!state.isLoggedIn) return const LoginScreen(portal: LoginPortal.tenant);
    if (state.mustChangePassword) return const SetPasswordScreen();
    if (state.role != UserRole.tenant) return const _WrongApp();
    return const TenantShell();
  }
}

class _WrongApp extends StatelessWidget {
  const _WrongApp();
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.info_outline, size: 48, color: primary),
              const SizedBox(height: 16),
              const Text(
                  'This is the tenant app, but your account is not a tenant account. Use the owner/admin app.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: state.logout, child: const Text('Sign out')),
            ]),
          ),
        ),
      ),
    );
  }
}

class TenantShell extends StatefulWidget {
  const TenantShell({super.key});
  @override
  State<TenantShell> createState() => _TenantShellState();
}

class _TenantShellState extends State<TenantShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const pages = [
      TenantHome(),
      PaymentsScreen(),
      MaintenanceScreen(),
      VisitorsScreen(),
      TenantProfileScreen()
    ];
    final destinations = [
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
    ];
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
                  color: Colors.white, size: 21)),
          const SizedBox(width: 10),
          Text('PG Management',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(letterSpacing: -.7)),
        ]),
        actions: [
          IconButton(
              tooltip: 'Notifications',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationsScreen())),
              icon: const Icon(Icons.notifications_none_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(index), child: pages[index]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: destinations,
      ),
    );
  }
}

class TenantHome extends StatelessWidget {
  const TenantHome({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final due = state.tenantDuePayment;
    final mine = state.tenantPayments;
    final latest = due ?? (mine.isEmpty ? null : mine.first);
    final recent = state.visibleNotifications.take(3).toList();
    return RefreshIndicator(
      onRefresh: state.refresh,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
          children: [
            Text('Hello, ${state.displayName.split(' ').first} 👋',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            if (latest != null)
              _rentCard(context, state, latest)
            else
              const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No rent scheduled yet'),
            const SizedBox(height: 24),
            Row(children: [
              _quick(context, 'Pay rent', Icons.account_balance_wallet_outlined,
                  const PaymentsScreen()),
              const SizedBox(width: 8),
              _quick(context, 'Raise issue', Icons.build_outlined,
                  const MaintenanceScreen()),
              const SizedBox(width: 8),
              _quick(context, 'Add visitor', Icons.badge_outlined,
                  const VisitorsScreen()),
              const SizedBox(width: 8),
              _quick(context, 'Updates', Icons.campaign_outlined,
                  const AnnouncementsScreen()),
            ]),
            const SizedBox(height: 24),
            Text('Recent activity',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              const Card(
                  clipBehavior: Clip.antiAlias,
                  child: EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'Nothing new yet'))
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                    children: recent
                        .map((n) => ListTile(
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const NotificationsScreen())),
                              leading: CircleAvatar(
                                  backgroundColor: primarySoft,
                                  child: Icon(notificationIcon(n.type),
                                      color: primary, size: 20)),
                              title: Text(n.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(n.body,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Text(relativeTime(n.createdAt),
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.black45)),
                            ))
                        .toList()),
              ),
          ]),
    );
  }

  Widget _rentCard(BuildContext context, AppState state, Payment latest) {
    final paid = latest.status == PaymentStatus.paid;
    return Card(
      color: ink,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PaymentsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${formatMonthName(latest.period).toUpperCase()} RENT',
                  style: const TextStyle(
                      color: Colors.white54,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      fontSize: 11)),
              StatusPill(latest.displayStatus),
            ]),
            const SizedBox(height: 14),
            Text(inr(paid ? latest.amount : latest.balance),
                style: Theme.of(context)
                    .textTheme
                    .headlineLarge
                    ?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(
                paid
                    ? 'Paid on ${formatDay(latest.paidDate!)} · Room ${state.currentTenantRoomLabel}'
                    : 'Due by ${formatDay(latest.dueDate)} · Room ${state.currentTenantRoomLabel}',
                style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PaymentsScreen())),
              icon:
                  Icon(paid ? Icons.receipt_long_outlined : Icons.lock_outline),
              label: Text(paid ? 'View receipt' : 'Pay now'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _quick(
          BuildContext context, String label, IconData icon, Widget page) =>
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: primarySoft,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: primary, size: 22)),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 11)),
            ]),
          ),
        ),
      );
}

class TenantProfileScreen extends StatelessWidget {
  const TenantProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final l = AppLocalizations.of(context);
    return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          const SizedBox(height: 6),
          CircleAvatar(
              radius: 43,
              backgroundColor: primarySoft,
              child: Text(state.initials,
                  style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: primary))),
          const SizedBox(height: 13),
          Center(
              child: Text(state.displayName,
                  style: Theme.of(context).textTheme.titleLarge)),
          if (state.accountEmail != null)
            Center(
                child: Text(state.accountEmail!,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black45))),
          Center(
              child: Text(
                  '${state.role.label} · Room ${state.currentTenantRoomLabel} · ${state.pgNameForTenant(state.currentTenantId)}')),
          const SizedBox(height: 28),
          Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                _tile(
                    Icons.person_outline,
                    l.t('profile.personal'),
                    state.profilePhone ?? l.t('profile.personalSub'),
                    () => _editPersonal(context, state, l)),
                _tile(
                    Icons.verified_user_outlined,
                    l.t('profile.kyc'),
                    'Aadhaar ${state.currentTenant?.kyc.label.toLowerCase() ?? 'pending'}',
                    () => _kyc(context, state, l)),
                _tile(
                    Icons.settings_outlined,
                    l.t('profile.settings'),
                    l.t('profile.settingsSub'),
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()))),
                _tile(Icons.help_outline, l.t('profile.help'),
                    l.t('profile.helpSub'), () => _help(context, l)),
              ])),
          const SizedBox(height: 18),
          OutlinedButton.icon(
              onPressed: state.logout,
              icon: const Icon(Icons.logout),
              label: Text(l.t('common.signOut')),
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC94444),
                  padding: const EdgeInsets.all(15))),
          const SizedBox(height: 16),
          const Center(
              child: Text('PG Management v3.0',
                  style: TextStyle(fontSize: 11, color: Colors.black38))),
        ]);
  }

  Widget _tile(
          IconData icon, String title, String subtitle, VoidCallback onTap) =>
      ListTile(
        onTap: onTap,
        leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: primarySoft, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: primary, size: 21)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      );

  void _editPersonal(BuildContext context, AppState state, AppLocalizations l) {
    final name = TextEditingController(text: state.displayName);
    final phone = TextEditingController(text: state.profilePhone ?? '');
    final messenger = ScaffoldMessenger.of(context);
    showAppSheet(
        context,
        Column(
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
              const FormLabel('Phone number'),
              TextField(controller: phone, keyboardType: TextInputType.phone),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: () async {
                    final error = await state.updatePersonalDetails(
                        name: name.text, phone: phone.text);
                    if (context.mounted) Navigator.pop(context);
                    messenger.showSnackBar(SnackBar(
                        content: Text(error ?? l.t('settings.saved'))));
                  },
                  child: Text(l.t('common.save'))),
            ]));
  }

  void _kyc(BuildContext context, AppState state, AppLocalizations l) {
    final doc = state.currentTenant?.kycDoc;
    final messenger = ScaffoldMessenger.of(context);
    showAppSheet(
        context,
        Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Text(l.t('profile.kyc'),
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 14),
              if (doc != null)
                ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: base64Image(doc, height: 180))
              else
                const EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'No document uploaded yet'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await pickImageBase64(context);
                  if (picked == null) return;
                  await state.updateKycDoc(picked);
                  if (context.mounted) Navigator.pop(context);
                  messenger.showSnackBar(
                      SnackBar(content: Text(l.t('settings.saved'))));
                },
                icon: Icon(
                    doc == null ? Icons.upload_file_outlined : Icons.cached),
                label:
                    Text(doc == null ? 'Upload document' : 'Replace document'),
              ),
            ]));
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
                  subtitle: const Text('support@pgmanagement.app')),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.call_outlined, color: primary),
                  title: Text(l.t('help.call')),
                  subtitle: const Text('+91 98765 43210')),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.t('common.close'))),
            ]));
  }
}

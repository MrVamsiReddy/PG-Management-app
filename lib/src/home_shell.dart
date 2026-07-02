import 'package:flutter/material.dart';

import 'app_state.dart';
import 'dashboard_screen.dart';
import 'module_screens.dart';
import 'theme.dart';

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
    final pages = <Widget>[
      const DashboardScreen(),
      const ModulesHubScreen(),
      const PaymentsScreen(),
      const MaintenanceScreen(),
      const ProfileScreen(),
    ];
    const destinations = [
      NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Manage'),
      NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Rent'),
      NavigationDestination(icon: Icon(Icons.build_outlined), selectedIcon: Icon(Icons.build), label: 'Requests'),
      NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: KeyedSubtree(key: ValueKey(index), child: pages[index]),
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
            decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 21),
          ),
          const SizedBox(width: 10),
          Text('nestora', style: Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing: -.7)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(8)),
            child: Text(state.role.label, style: const TextStyle(color: primary, fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ]),
        actions: [
          Stack(children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            if (state.notifications.any((e) => e['read'] == false))
              Positioned(right: 10, top: 10, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: coral, shape: BoxShape.circle))),
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
                destinations: destinations.map((e) => NavigationRailDestination(icon: e.icon, selectedIcon: e.selectedIcon, label: Text(e.label))).toList(),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        const SizedBox(height: 6),
        CircleAvatar(
          radius: 43,
          backgroundColor: primarySoft,
          child: Text(state.initials, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: primary)),
        ),
        const SizedBox(height: 13),
        Center(child: Text(state.displayName, style: Theme.of(context).textTheme.titleLarge)),
        Center(child: Text(state.role == UserRole.tenant ? '${state.role.label} · Room ${AppState.currentTenantBed} · Nestora HSR' : '${state.role.label} · Nestora HSR')),
        const SizedBox(height: 28),
        Card(
          child: Column(children: [
            _profileTile(Icons.person_outline, 'Personal details', 'Name, phone, email'),
            _profileTile(Icons.verified_user_outlined, 'KYC & documents', state.role == UserRole.tenant ? 'Aadhaar verified' : 'Business details'),
            _profileTile(Icons.description_outlined, 'Rental agreement', state.role == UserRole.tenant ? 'Signed · View copy' : 'Templates and e-signatures'),
            _profileTile(Icons.settings_outlined, 'App settings', 'Notifications, security, language'),
            _profileTile(Icons.help_outline, 'Help & support', 'FAQs and contact support'),
          ]),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: state.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC94444), padding: const EdgeInsets.all(15)),
        ),
        const SizedBox(height: 16),
        const Center(child: Text('Nestora v1.0 · Local demo', style: TextStyle(fontSize: 11, color: Colors.black38))),
      ],
    );
  }

  Widget _profileTile(IconData icon, String title, String subtitle) => ListTile(
        leading: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: primary, size: 21)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      );
}

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'l10n.dart';
import 'theme.dart';
import 'widgets.dart';

/// Creates a PG from just its basic details. Rooms, beds, sharing type and
/// rent are configured later — during tenant onboarding or on the Rooms & Beds
/// screen — so PG creation stays light.
class PgSetupWizard extends StatefulWidget {
  const PgSetupWizard({super.key});
  @override
  State<PgSetupWizard> createState() => _PgSetupWizardState();
}

class _PgSetupWizardState extends State<PgSetupWizard> {
  final name = TextEditingController();
  final address = TextEditingController();
  final amenities = TextEditingController(text: 'Wi-Fi • Food • Laundry');

  @override
  void dispose() {
    name.dispose();
    address.dispose();
    amenities.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    if (name.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.t('wiz.enterName'))));
      return;
    }
    final error = state.createProperty(
        name: name.text, address: address.text, amenities: amenities.text);
    if (!mounted) return;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context);
    messenger.showSnackBar(
        SnackBar(content: Text('${name.text.trim()} ${l.t('wiz.created')}')));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('wiz.title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text(l.t('wiz.stepDetails'),
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(l.t('wiz.basicInfo'),
              style: TextStyle(fontSize: 13, color: subtle)),
          const SizedBox(height: 12),
          FormLabel(l.t('wiz.propName')),
          TextField(
              controller: name,
              decoration: InputDecoration(hintText: l.t('wiz.propNameHint'))),
          FormLabel(l.t('wiz.address')),
          TextField(controller: address, maxLines: 2),
          FormLabel(l.t('wiz.amenities')),
          TextField(controller: amenities, maxLines: 2),
          const SizedBox(height: 24),
          FilledButton(onPressed: _create, child: Text(l.t('wiz.create'))),
        ],
      ),
    );
  }
}

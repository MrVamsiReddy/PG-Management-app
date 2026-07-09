import 'package:flutter/material.dart';

import 'app_state.dart';
import 'widgets.dart';

class _Draft {
  _Draft(this.number, this.floor, this.beds, this.rent);
  String number;
  int floor;
  int beds;
  int rent;
}

class PgSetupWizard extends StatefulWidget {
  const PgSetupWizard({super.key});
  @override
  State<PgSetupWizard> createState() => _PgSetupWizardState();
}

class _PgSetupWizardState extends State<PgSetupWizard> {
  int step = 0;

  final name = TextEditingController();
  final address = TextEditingController();
  final amenities = TextEditingController(text: 'Wi-Fi • Food • Laundry');

  final rent = {
    1: TextEditingController(text: '14000'),
    2: TextEditingController(text: '9500'),
    3: TextEditingController(text: '7800'),
    4: TextEditingController(text: '6500'),
  };

  final floors = TextEditingController(text: '2');
  final roomsPerFloor = TextEditingController(text: '4');
  int sharing = 2;

  List<_Draft> drafts = [];

  @override
  void dispose() {
    name.dispose();
    address.dispose();
    amenities.dispose();
    for (final c in rent.values) {
      c.dispose();
    }
    floors.dispose();
    roomsPerFloor.dispose();
    super.dispose();
  }

  int _rentFor(int beds) => int.tryParse(rent[beds]!.text) ?? 0;

  void _generate() {
    final f = (int.tryParse(floors.text) ?? 1).clamp(1, 30);
    final rpf = (int.tryParse(roomsPerFloor.text) ?? 1).clamp(1, 30);
    final list = <_Draft>[];
    for (var fl = 1; fl <= f; fl++) {
      for (var i = 1; i <= rpf; i++) {
        list.add(_Draft('${fl * 100 + i}', fl, sharing, _rentFor(sharing)));
      }
    }
    setState(() => drafts = list);
  }

  int get _totalBeds => drafts.fold(0, (s, d) => s + d.beds);

  Future<void> _create() async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final specs = drafts.map((d) => (number: d.number, floor: d.floor, beds: d.beds, rent: d.rent)).toList();
    final error = state.createProperty(name: name.text, address: address.text, amenities: amenities.text, specs: specs);
    if (!mounted) return;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text('${name.text.trim()} created with ${drafts.length} rooms.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your PG')),
      body: Stepper(
        currentStep: step,
        onStepContinue: _onContinue,
        onStepCancel: step == 0 ? null : () => setState(() => step -= 1),
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(children: [
            FilledButton(onPressed: details.onStepContinue, child: Text(step == 3 ? 'Create' : 'Continue')),
            if (step > 0) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: details.onStepCancel, child: const Text('Back')),
            ],
          ]),
        ),
        steps: [
          Step(
            title: const Text('Property details'),
            isActive: step >= 0,
            content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const FormLabel('Property name'),
              TextField(controller: name, decoration: const InputDecoration(hintText: 'e.g. Indiranagar PG')),
              const FormLabel('Full address'),
              TextField(controller: address, maxLines: 2),
              const FormLabel('Amenities'),
              TextField(controller: amenities, maxLines: 2),
            ]),
          ),
          Step(
            title: const Text('Rent by sharing'),
            isActive: step >= 1,
            content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final e in const [(1, 'Single'), (2, 'Double sharing'), (3, 'Triple sharing'), (4, 'Four sharing')]) ...[
                FormLabel(e.$2),
                TextField(controller: rent[e.$1], keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ')),
              ],
            ]),
          ),
          Step(
            title: const Text('Floors, rooms & beds'),
            isActive: step >= 2,
            content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FormLabel('Floors'), TextField(controller: floors, keyboardType: TextInputType.number)])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FormLabel('Rooms / floor'), TextField(controller: roomsPerFloor, keyboardType: TextInputType.number)])),
              ]),
              const FormLabel('Beds per room'),
              DropdownButtonFormField<int>(
                initialValue: sharing,
                items: const [DropdownMenuItem(value: 1, child: Text('Single')), DropdownMenuItem(value: 2, child: Text('Double sharing')), DropdownMenuItem(value: 3, child: Text('Triple sharing')), DropdownMenuItem(value: 4, child: Text('Four sharing'))],
                onChanged: (v) => setState(() => sharing = v ?? 2),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _generate, icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Generate rooms')),
              const SizedBox(height: 8),
              if (drafts.isEmpty)
                const Text('Generate rooms, then fine-tune rent per room below.', style: TextStyle(fontSize: 12, color: Colors.black54))
              else
                ...drafts.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(child: Text('Room ${d.number} · Floor ${d.floor} · ${d.beds}-share', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        SizedBox(
                          width: 96,
                          child: TextFormField(
                            initialValue: '${d.rent}',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(prefixText: '₹', isDense: true),
                            onChanged: (v) => d.rent = int.tryParse(v) ?? d.rent,
                          ),
                        ),
                        IconButton(onPressed: () => setState(() => drafts.remove(d)), icon: const Icon(Icons.delete_outline)),
                      ]),
                    )),
            ]),
          ),
          Step(
            title: const Text('Review & create'),
            isActive: step >= 3,
            content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.text.trim().isEmpty ? 'Unnamed property' : name.text.trim(), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('${drafts.map((d) => d.floor).toSet().length} floors · ${drafts.length} rooms · $_totalBeds beds'),
              const SizedBox(height: 6),
              const Text('Rent is stored per room now; changing rent later never alters past payments.', style: TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
        ],
      ),
    );
  }

  void _onContinue() {
    final messenger = ScaffoldMessenger.of(context);
    if (step == 0 && name.text.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Enter a property name.')));
      return;
    }
    if (step == 2 && drafts.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Generate at least one room.')));
      return;
    }
    if (step == 3) {
      _create();
      return;
    }
    setState(() => step += 1);
  }
}

import 'package:flutter/material.dart';

import 'src/bootstrap.dart';
import 'src/owner_app.dart';

Future<void> main() async {
  final state = await bootstrap();
  runApp(OwnerAdminApp(state: state));
}

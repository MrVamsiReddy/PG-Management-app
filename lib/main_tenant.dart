import 'package:flutter/material.dart';

import 'src/bootstrap.dart';
import 'src/tenant_app.dart';

Future<void> main() async {
  final state = await bootstrap();
  runApp(TenantApp(state: state));
}

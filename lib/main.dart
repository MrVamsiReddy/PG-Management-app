import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'src/app_state.dart';
import 'src/auth_screen.dart';
import 'src/home_shell.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final box = await Hive.openBox<dynamic>('nestora_local');
  final state = AppState(box)..seedIfNeeded();
  runApp(NestoraApp(state: state));
}

class NestoraApp extends StatelessWidget {
  const NestoraApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Nestora PG',
        theme: buildAppTheme(),
        home: AnimatedBuilder(
          animation: state,
          builder: (context, _) => state.isLoggedIn
              ? const HomeShell()
              : const AuthScreen(),
        ),
      ),
    );
  }
}

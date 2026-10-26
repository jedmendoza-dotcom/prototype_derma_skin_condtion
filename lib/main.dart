import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/app_shell.dart';

void main() => runApp(const DermaScreenApp());

class DermaScreenApp extends StatelessWidget {
  const DermaScreenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DermaScreen',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AppShell(),
    );
  }
}

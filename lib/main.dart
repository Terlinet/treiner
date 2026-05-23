import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';

void main() {
  runApp(const TerlineTTreinerApp());
}

class TerlineTTreinerApp extends StatelessWidget {
  const TerlineTTreinerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TerlineT Treiner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          primary: Colors.orange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}

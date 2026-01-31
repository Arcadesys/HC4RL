import 'package:flutter/material.dart';

import 'shell/tool_picker_screen.dart';

void main() {
  runApp(const HC4RLApp());
}

class HC4RLApp extends StatelessWidget {
  const HC4RLApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HC4RL',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ToolPickerScreen(),
    );
  }
}

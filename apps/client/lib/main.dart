import 'package:flutter/material.dart';

void main() {
  runApp(const StudyFlowApp());
}

class StudyFlowApp extends StatelessWidget {
  const StudyFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'StudyFlow',
      home: Scaffold(
        body: Center(child: Text('StudyFlow')),
      ),
    );
  }
}

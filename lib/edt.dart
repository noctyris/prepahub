import 'package:flutter/material.dart';

class EDTPage extends StatefulWidget {
  const EDTPage({super.key});

  @override
  State<EDTPage> createState() => _EDTPageState();
}

class _EDTPageState extends State<EDTPage> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

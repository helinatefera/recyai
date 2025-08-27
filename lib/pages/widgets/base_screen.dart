import 'package:flutter/material.dart';
import 'navigation.dart';

/// Base screen widget that provides a consistent layout with navigation.
class BaseScreen extends StatelessWidget {
  final Widget child;

  const BaseScreen({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: child,
      bottomNavigationBar: Navigation(
        currentIndex: 0, // Set to the desired initial index
        onItemTapped: (int index) {
          // Handle navigation tap
        },
      ),
    );
  }
}

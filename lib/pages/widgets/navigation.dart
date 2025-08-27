import 'package:awesome_bottom_bar/awesome_bottom_bar.dart';
import 'package:awesome_bottom_bar/widgets/inspired/inspired.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Navigation bar widget for the app.
class Navigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onItemTapped;

  const Navigation({
    super.key,
    required this.currentIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    final List<_NavItem> navItems = [
      _NavItem(icon: Icons.apartment, label: "Brands"),
      _NavItem(icon: Icons.trending_up, label: "Track"),
      _NavItem(icon: Icons.camera_alt, label: "Scan"),
      _NavItem(icon: Icons.emoji_events, label: "Challenges"),
      _NavItem(icon: Icons.settings, label: "Settings"),
    ];

    return BottomBarInspiredOutside(
      items: navItems.asMap().entries.map((entry) {
        final item = entry.value;
        return TabItem(
          icon: item.icon,
          title: item.label, // Hide label for Scan
        );
      }).toList(),
      sizeInside: 50,
      indexSelected: currentIndex, // Changed from currentIndex to indexSelected
      onTap: onItemTapped,
      backgroundColor: const Color(0xFF333A40),
      color: Colors.white,
      colorSelected: Colors.white, // White for active icon
      chipStyle: const ChipStyle(
        background: Color(0xFF2FD885),
        notchSmoothness: NotchSmoothness.softEdge, // Smooth edge for circle
      ),
      itemStyle: ItemStyle.circle, // Circular shape for active item
      top: -30, // Adjust position to match floating effect
      animated: true, // Smooth animations
      iconSize: 24, // Inactive icon size
      elevation: 0, // Shadow to match original boxShadow
      titleStyle: GoogleFonts.poppins(
        fontSize: 11, // Match original selected/unselected font size
        color: Color.fromARGB(255, 68, 68, 68), // Cloud Grey for labels
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  _NavItem({required this.icon, required this.label});
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_requests_page.dart';

/// A button that only shows if the user is an admin.
class AdminDashboardButton extends StatefulWidget {
  const AdminDashboardButton({super.key});
  @override
  State<AdminDashboardButton> createState() => _AdminDashboardButtonState();
}

/// State for [AdminDashboardButton].
class _AdminDashboardButtonState extends State<AdminDashboardButton> {
  late final Stream<bool> _adminStream;
  bool _welcomed = false;

  @override
  void initState() {
    super.initState();
    _adminStream = _buildAdminProbeStream();
  }

  /// Rules-only admin check:
  /// Try reading /adminOnly/ping (readable only by admins via rules).
  Stream<bool> _buildAdminProbeStream() async* {
    final auth = FirebaseAuth.instance;
    await for (final user in auth.idTokenChanges()) {
      if (user == null) {
        yield false;
        continue;
      }
      try {
        await FirebaseFirestore.instance.doc('adminOnly/ping').get();
        yield true; // read success => admin
      } catch (e) {
        yield false; // PERMISSION_DENIED or other => not admin
      }
    }
  }

  /// Builds the widget.
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _adminStream,
      builder: (context, snap) {
        final isAdmin = snap.data ?? false;

        if (isAdmin && !_welcomed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('👋 Welcome, Admin')),
            );
          });
          _welcomed = true;
        }

        if (!isAdmin) return const SizedBox.shrink();

        return _DashButton(
          title: "Admin • Bin Requests",
          subtitle: "View and manage requests",
          icon: Icons.admin_panel_settings_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminRequestsPage(), // page already admin-only
            ),
          ),
        );
      },
    );
  }
}

/// A dashboard button widget.
class _DashButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _DashButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF233038),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFFDDE5E4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        color: Color(0xFFF9FBFA),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                        color: Color(0xFFD0D8D7),
                        fontSize: 12.5,
                      )),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF95A3A1)),
          ],
        ),
      ),
    );
  }
}

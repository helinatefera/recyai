import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:animate_do/animate_do.dart';

import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../services/pdf_export.dart';
import '../services/privacy_policy.dart';
import 'package:geolocator/geolocator.dart';


import 'edit.dart';
import '../services/notification_service.dart';

/// Settings screen where users can manage their profile, notifications, and app preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final RefreshController _refreshController = RefreshController(
    initialRefresh: false,
  );

  Future<void> _setUserLocation() async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enable location services")),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permission denied")),
      );
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'location': GeoPoint(pos.latitude, pos.longitude),
        'locationUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() {}); // refresh UI
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location updated successfully")),
        );
      }
    }
  } catch (e) {
    debugPrint("Error setting location: $e");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to set location: $e")),
      );
    }
  }
}

  
  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  void _onRefresh() async {
    if (mounted) {
      setState(() {});
    }
    _refreshController.refreshCompleted();
  }

  Future<void> _exportAndDownloadData(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF2FD885)),
            const SizedBox(height: 20),
            Text("Preparing your data...", style: TextStyle(color: Colors.white.withOpacity(0.9))),
          ],
        ),
      ),
    );

    try {
      final pdfFile = await PDFExport.generateUserDataPDF();
      final directory = await getApplicationDocumentsDirectory();
      final downloadPath = '${directory.path}/UserDataExport_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await pdfFile.copy(downloadPath);

      if (context.mounted) Navigator.pop(context);

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2C2C2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text("Export Successful", style: TextStyle(color: Colors.white)),
            content: Text(
              "Your data PDF has been saved. You can open it now or find it later in your device's files.",
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Done", style: TextStyle(color: Colors.white)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await OpenFile.open(downloadPath);
                },
                child: const Text("Open File", style: TextStyle(color: Color(0xFF2FD885), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e, stack) {
      debugPrint("Export error: $e\n$stack");
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Export failed: ${e.toString()}', style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<bool?> _showDeleteConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text("Are you sure?", style: TextStyle(color: Colors.white)),
        content: Text(
          "This will permanently delete your account and all associated data from our services.",
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<String?> _showReauthenticationDialog(BuildContext context) {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2C2C2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Verify Identity", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Please enter your current password to confirm account deletion.", style: TextStyle(color: Colors.white.withOpacity(0.7))),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.3))),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF2FD885))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, passwordController.text),
            child: const Text("Confirm", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF121212),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF2FD885))),
          );
        }
        final currentUser = authSnapshot.data;
        if (currentUser == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF121212),
            body: Center(child: Text("Please log in to see settings.", style: TextStyle(color: Colors.white))),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: SafeArea(
            top: false,
            child: SmartRefresher(
              controller: _refreshController,
              onRefresh: _onRefresh,
              header: const WaterDropHeader(
                waterDropColor: Color(0xFF2FD885),
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUser.uid)
                          .get(),
                      builder: (context, userDocSnapshot) {
                        if (userDocSnapshot.connectionState == ConnectionState.waiting) {
                          return _buildProfileHeader(
                              context,
                              isLoading: true, name: "Loading...", location: "Fetching data...");
                        }
                        if (!userDocSnapshot.hasData || !userDocSnapshot.data!.exists) {
                          return _buildProfileHeader(context, name: "No data found", location: "Please try again.");
                        }

                        final data = userDocSnapshot.data!.data() as Map<String, dynamic>;
                        final name = data['name'] ?? 'User';
                        final photoUrl = data['photoUrl'] as String?;
                        final loc = data['location'];
                        final locationText = (loc is GeoPoint)
                            ? "Location: (${loc.latitude.toStringAsFixed(2)}, ${loc.longitude.toStringAsFixed(2)})"
                            : "Location: Not set";
                        
                        return _buildProfileHeader(
                          context,
                          name: name,
                          location: locationText,
                          photoUrl: photoUrl,
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
                      child: Column(
                        children: [
                          FadeInUp(
                            from: 20,
                            delay: const Duration(milliseconds: 200),
                            child: _NotificationsCard(onSettingsChanged: _onRefresh),
                          ),
                          FadeInUp(
                            from: 20,
                            delay: const Duration(milliseconds: 300),
                            child: _buildContentCard(
                              title: "Data & Privacy",
                              child: Column(
                                children: [
                                  _buildListTile(
                                    icon: Icons.download_for_offline_outlined,
                                    title: "Download Report",
                                    onTap: () => _exportAndDownloadData(context),
                                  ),
                                  _buildListTile(
                                    icon: Icons.privacy_tip_outlined,
                                    title: "Privacy Policy",
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const PrivacyPolicyPage(),
                                        ),
                                      );
                                    },
                                  ),
                                  _buildListTile(
                                    icon: Icons.delete_forever,
                                    title: "Delete Account",
                                    color: Colors.redAccent,
                                    onTap: () async {
                                      final confirm = await _showDeleteConfirmationDialog(context);
                                      if (confirm != true || !context.mounted) return;

                                      final user = FirebaseAuth.instance.currentUser;
                                      if (user == null) return;

                                      final password = await _showReauthenticationDialog(context);
                                      if (password == null || password.isEmpty || !context.mounted) return;
                                      
                                      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF2FD885))));
                                      
                                      try {
                                        final cred = EmailAuthProvider.credential(email: user.email!, password: password);
                                        await user.reauthenticateWithCredential(cred);
                                        
                                        try {
                                          await FirebaseStorage.instance.ref('profile_images/${user.uid}.jpg').delete();
                                        } catch (e) {
                                          debugPrint("Profile image not found or could not be deleted: $e");
                                        }

                                        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
                                        
                                        await user.delete();
                                        await FirebaseAuth.instance.signOut();
                                        
                                        if (context.mounted) {
                                          Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
                                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Account deleted successfully.")));
                                        }

                                      } on FirebaseAuthException catch (e) {
                                        if(context.mounted) Navigator.pop(context);
                                        if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.redAccent, content: Text("Error: ${e.message ?? 'Wrong password or session expired.'}")));
                                      } catch (e) {
                                        if(context.mounted) Navigator.pop(context);
                                        if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.redAccent, content: Text("An unexpected error occurred: $e")));
                                      }
                                    },
                                  ),
                                  _buildListTile(
                                    icon: Icons.logout,
                                    title: "Log Out",
                                    onTap: () async {
                                      await FirebaseAuth.instance.signOut();
                                      if (context.mounted) {
                                        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          FadeInUp(
                            from: 20,
                            delay: const Duration(milliseconds: 400),
                            child: _buildContentCard(
                              title: "About",
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("App Version", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                                        const Text("1.0.0", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  _buildListTile(
                                    icon: Icons.headset_mic_outlined,
                                    title: "Contact Support",
                                    onTap: () { /* TODO */ },
                                  ),
                                  _buildListTile(
                                    icon: Icons.star_outline,
                                    title: "Rate App",
                                    color: const Color(0xFFFFB547),
                                    onTap: () { /* TODO */ },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildProfileHeader(
    BuildContext context, {
    required String name,
    required String location,
    String? photoUrl,
    bool isLoading = false,
  }) {
    final topPadding = MediaQuery.of(context).padding.top;
    final screenHeight = MediaQuery.of(context).size.height;
    final profileHeight = screenHeight * 0.4;
    final scale = profileHeight / 334; 

    final backgroundHeight = 220 * scale;
    final titleTop = topPadding + 16 * scale;
    final cardTop = topPadding + 40 * scale;
    final cardMarginTop = 30 * scale;
    final cardSizedBoxHeight = 30 * scale;
    final nameSizedBoxHeight = 4 * scale;
    final locationSizedBoxHeight = 12 * scale;
    final avatarRadius = 30 * scale;
    final titleFontSize = 21 * scale;
    final nameFontSize = 20 * scale;
    final locationFontSize = 14 * scale; 
    final editIconSize = 16 * scale;
    final cardBorderRadius = 24 * scale;
    final shadowBlur = 20 * scale;
    final shadowOffset = 10 * scale;
    final fadeInUpFrom = 20 * scale;

    return SizedBox(
      height: profileHeight,
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                height: backgroundHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
                  image: DecorationImage(
                    image: const AssetImage('images/auth.jpg'),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.45),
                      BlendMode.darken,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: titleTop,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Settings",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: titleFontSize,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: cardTop,
            left: 16,
            right: 16,
            child: FadeInUp(
              from: fadeInUpFrom,
              delay: const Duration(milliseconds: 200),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    margin: EdgeInsets.only(top: cardMarginTop),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2a2a2e),
                      borderRadius: BorderRadius.circular(cardBorderRadius),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: shadowBlur,
                          offset: Offset(0, shadowOffset),
                        )
                      ]
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          SizedBox(height: cardSizedBoxHeight),
                          FadeInUp(
                            delay: const Duration(milliseconds: 300),
                            child: Text(name, style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: nameFontSize, color: Colors.white.withOpacity(0.95))),
                          ),
                          FadeInUp(
                            delay: const Duration(milliseconds: 400),
                            child: Column(
                              children: [
                                Text(
                                  location,
                                  style: TextStyle(fontSize: locationFontSize, color: Colors.white.withOpacity(0.7)),
                                ),
                                if (location.contains("Not set"))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: FilledButton.icon(
                                      onPressed: _setUserLocation,
                                      icon: const Icon(Icons.location_on_outlined),
                                      label: const Text("Set Location"),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF2FD885).withOpacity(0.15),
                                        foregroundColor: const Color(0xFF2FD885),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),


                          SizedBox(height: locationSizedBoxHeight),
                           FadeInUp(
                             delay: const Duration(milliseconds: 500),
                            child: FilledButton.icon(
                              onPressed: isLoading ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())).then((_) => _onRefresh()),
                              icon: Icon(Icons.edit_outlined, size: editIconSize),
                              label: const Text("Edit Profile"),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2FD885).withOpacity(0.15),
                                foregroundColor: const Color(0xFF2FD885),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    child: FadeIn(
                      delay: const Duration(milliseconds: 250),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [Color(0xFF2FD885), Color(0xFF0F9E84)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: Colors.grey.shade800,
                          backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                          child: (photoUrl == null || photoUrl.isEmpty) ? Icon(Icons.person_rounded, size: avatarRadius + 5, color: Colors.white.withOpacity(0.7)) : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard({required String title, required Widget child}) {
    return Card(
      color: const Color(0xFF1C1C1E),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.lato(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildListTile({required IconData icon, required String title, Color? color, required VoidCallback onTap}) {
    final tileColor = color ?? Colors.white.withOpacity(0.8);
    return ListTile(
      leading: Icon(icon, color: tileColor),
      title: Text(title, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.w500)),
      trailing: Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}

class _NotificationsCard extends StatefulWidget {
  final VoidCallback onSettingsChanged;
  const _NotificationsCard({required this.onSettingsChanged});

  @override
  State<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends State<_NotificationsCard> {
  bool _dailyEnabled = false,
      _weeklyEnabled = false,
      _challengeEnabled = false,
      _loading = true;
  TimeOfDay? _notificationTime;
  int _recapDay = 1;
  String _recapTime = '09:00';

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final dailyEnabledFuture = NotificationService.isDailyNotificationEnabled();
      final dailyTimeFuture = NotificationService.getDailyNotificationTime();
      final weeklySettingsFuture = NotificationService.getWeeklyRecapSettings();

      final results = await Future.wait([dailyEnabledFuture, dailyTimeFuture, weeklySettingsFuture]);

      if (mounted) {
        setState(() {
          _dailyEnabled = results[0] as bool;
          _notificationTime = results[1] as TimeOfDay?;
          final weeklySettings = results[2] as Map<String, dynamic>;
          _weeklyEnabled = weeklySettings['enabled'] as bool;
          _recapDay = weeklySettings['day'] as int;
          _recapTime = weeklySettings['time'] as String;
          if (userDoc.exists) {
            _challengeEnabled = userDoc.data()!['notifChallenge'] ?? false;
          }
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading notification settings: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateNotificationSetting(bool enabled, Future<void> Function() onEnable, Future<void> Function() onDisable) async {
    if (enabled) {
      if (!(await NotificationService.requestPermissions())) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Notification permissions are required.")));
        return;
      }
      await onEnable();
    } else {
      await onDisable();
    }
    widget.onSettingsChanged();
  }

  Future<void> _updateDailyNotification(bool enabled) async {
    await _updateNotificationSetting(enabled, () async {
      final time = await showTimePicker(
        context: context,
        initialTime: _notificationTime ?? const TimeOfDay(hour: 20, minute: 0),
        builder: (context, child) => Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF2FD885),
              onPrimary: Colors.black,
              surface: Color(0xFF1C1C1E),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF2C2C2E),
          ),
          child: child!,
        ),
      );
      if (time != null) {
        await NotificationService.enableDailyNotifications(hour: time.hour, minute: time.minute);
        if (mounted) setState(() { _dailyEnabled = true; _notificationTime = time; });
      }
    }, () async {
      await NotificationService.disableDailyNotifications();
      if(mounted) setState(() => _dailyEnabled = false);
    });
  }

  Future<void> _updateWeeklyNotification(bool enabled) async {
    await _updateNotificationSetting(enabled, () async {
      await NotificationService.showWeeklyRecapPicker(context);
      final weeklySettings = await NotificationService.getWeeklyRecapSettings();
      if (mounted) setState(() {
        _weeklyEnabled = weeklySettings['enabled'] as bool;
        _recapDay = weeklySettings['day'] as int;
        _recapTime = weeklySettings['time'] as String;
      });
    }, () async {
      await NotificationService.disableWeeklyRecap();
      if (mounted) setState(() => _weeklyEnabled = false);
    });
  }

  Future<void> _updateChallengeNotification(bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _updateNotificationSetting(enabled, () async {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({'notifChallenge': true}, SetOptions(merge: true));
      if (mounted) setState(() => _challengeEnabled = true);
    }, () async {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({'notifChallenge': false}, SetOptions(merge: true));
      if (mounted) setState(() => _challengeEnabled = false);
    });
  }

  String _getDayName(int day) => ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][day - 1];

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF2FD885)));

    return Card(
      color: const Color(0xFF1C1C1E),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Notifications", style: GoogleFonts.lato(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9))),
            const SizedBox(height: 8),
            _buildSwitchTile(
              value: _dailyEnabled,
              onChanged: _updateDailyNotification,
              title: "Daily Reminder",
              subtitle: _dailyEnabled ? "Scheduled at ${_notificationTime?.format(context) ?? 'Not set'}" : "Get a daily nudge to scan",
            ),
            _buildSwitchTile(
              value: _weeklyEnabled,
              onChanged: _updateWeeklyNotification,
              title: "Weekly Recap",
              subtitle: _weeklyEnabled ? "Scheduled for ${_getDayName(_recapDay)} at $_recapTime" : "Get a summary of your impact",
            ),
            _buildSwitchTile(
              value: _challengeEnabled,
              onChanged: _updateChallengeNotification,
              title: "Challenge Updates",
              subtitle: "Progress on neighborhood challenges",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({required bool value, required Function(bool) onChanged, required String title, required String subtitle}) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF2FD885),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.7))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
    );
  }
}
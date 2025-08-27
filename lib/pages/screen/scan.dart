import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/pages/services/waste_classifier.dart';
import 'package:gif/gif.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

import '../widgets/bin_service_button.dart';
import '../widgets/bulky_item_form.dart' as bulky_form;
import 'bulky_items_list.dart';
import '../admin/admin_dashboard_button.dart';


// Screen for scanning waste items and displaying results.
class Scan extends StatefulWidget {
  const Scan({super.key});

  @override
  _ScanState createState() => _ScanState();
}

class _ScanState extends State<Scan>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  File? selectedImage;
  String? _predictedClass;
  String? _brand;
  String? _tips;
  bool? _isRecyclable;
  String? _confidence;
  int? _streak;
  String? _binType;
  int? _xpEarned;
  List<String> _bonusReasons = [];
  bool isProcessing = false;
  bool showResult = false;
  WasteClassifier wasteClassifier = WasteClassifier();
  late GifController _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('images/animated_logo.gif'), context);
  }

  @override
  void initState() {
    super.initState();
    _controller = GifController(vsync: this);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<bool> _checkCameraAccess() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      _showPermanentDenialAlert();
      return false;
    }
    final result = await Permission.camera.request();
    return result.isGranted;
  }

  void _showPermanentDenialAlert() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Camera Access Required"),
        content: const Text(
          "You've previously denied camera access. Please enable it in settings to scan items.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  Future<void> pickAndSendToGPT() async {
    if (!await _checkCameraAccess()) return;

    final ImagePicker picker = ImagePicker();
    final XFile? imageFile = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (imageFile == null) return;

    setState(() {
      selectedImage = File(imageFile.path);
      isProcessing = true;
      _bonusReasons = [];
    });

    final result = await wasteClassifier.classify(selectedImage!);

    if (result['success'] == false) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to identify the waste. Please try again with a clearer image.',
          ),
        ),
      );
      return;
    }

    final label = result['label']?.toString().split(' ').map(
          (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
        ).join(' ');
    final brand = result['brand']?.toString().split(' ').map(
          (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
        ).join(' ');
    final tips = result['tips'];
    bool recyclable = result['recyclable'];
    final confidence = result['confidence'];

    String binType;
    if (label != null &&
        (label.toLowerCase().contains("batter") ||
            label.toLowerCase().contains("e-waste") ||
            label.toLowerCase().contains("film"))) {
      binType = 'special';
      recyclable = true;
    } else {
      binType = recyclable ? 'blue' : 'green';
    }

    final user = FirebaseAuth.instance.currentUser!;
    final scanResult = await saveScan({
      'material': label,
      'brand': brand,
      'binType': binType,
      'recyclable': recyclable,
      'imagePath': selectedImage?.path,
    });

    _xpEarned = scanResult['xpEarned'];
    _bonusReasons = scanResult['bonusReasons'];

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final streak = userDoc.data()?['streak'] as int? ?? 0;
    print("uid: ${FirebaseAuth.instance.currentUser?.uid}");


    setState(() {
      _predictedClass = label;
      _brand = brand;
      _tips = tips;
      _isRecyclable = recyclable;
      _confidence = confidence;
      _streak = streak;
      _binType = binType;
      isProcessing = false;
      showResult = true;
    });

    showScanResult();
  }

  Future<Map<String, dynamic>> saveScan(Map<String, dynamic> result) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {'xpEarned': 0, 'bonusReasons': []};

    final uid = user.uid;
    final now = DateTime.now();
    final todayKey =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final scanRef = FirebaseFirestore.instance.collection('scans').doc();

    int baseXP = 0;
    String binType = result['binType'];
    String material = result['material']?.toString().toLowerCase() ?? '';
    List<String> bonusReasons = [];

    if (binType == 'special') {
      baseXP = 60;
      bonusReasons.add("Special drop-off: +60 XP");
    } else if (binType == 'blue') {
      baseXP = 10;
      bonusReasons.add("Base reward: +10 XP");

      if (material.contains("aluminum") ||
          material.contains("pet") ||
          material.contains("can")) {
        baseXP += 50;
        bonusReasons.add("Aluminum/Cans/PET: +50 XP");
      } else if (material.contains("cardboard") || material.contains("glass")) {
        baseXP += 40;
        bonusReasons.add("Cardboard/Glass: +40 XP");
      } else if (material.contains("plastic")) {
        baseXP += 30;
        bonusReasons.add("Plastic: +30 XP");
      }
    }

    final userDoc = await userRef.get();
    final data = userDoc.data() ?? {};

    bool firstTimeToday = false;
    if (binType == 'blue') {
      Map<String, dynamic> dailyMaterials =
          Map<String, dynamic>.from(data['dailyMaterials'] ?? {});
      List<dynamic> todayMaterials = dailyMaterials[todayKey] ?? [];

      if (!todayMaterials.contains(material)) {
        baseXP += 10;
        firstTimeToday = true;
        bonusReasons.add("First-time a day recycling : +10 XP");
        todayMaterials.add(material);
        dailyMaterials[todayKey] = todayMaterials;
      }
    }

    if (binType == 'blue') {
      Map<String, dynamic> blueBinDailyCounts =
          Map<String, dynamic>.from(data['blueBinDailyCounts'] ?? {});
      int blueBinToday = blueBinDailyCounts[todayKey] ?? 0;

      if (blueBinToday >= 20) {
        int beforePenalty = baseXP;
        baseXP = (baseXP * 0.2).round();
        int penaltyAmount = beforePenalty - baseXP;
        bonusReasons.add("Daily cap penalty: -${penaltyAmount} XP");
      }

      blueBinDailyCounts[todayKey] = blueBinToday + 1;
      await userRef.update({'blueBinDailyCounts': blueBinDailyCounts});
    }

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final data = snapshot.data() ?? {};

      Map<String, dynamic> dailyMaterials =
          Map<String, dynamic>.from(data['dailyMaterials'] ?? {});
      List<dynamic> todayMaterials = dailyMaterials[todayKey] ?? [];

      int xp = (data['xp'] ?? 0) + baseXP;
      int scans = (data['scans'] ?? 0) + 1;
      int streak = data['streak'] ?? 0;
      String? lastScanDate = data['lastScanDate'];
      Map<String, dynamic> dailyCounts =
          Map<String, dynamic>.from(data['dailyCounts'] ?? {});
      int todayCount = (dailyCounts[todayKey] ?? 0) + 1;
      dailyCounts[todayKey] = todayCount;

      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final yesterdayKey =
          "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";

      if (lastScanDate == todayKey) {
      } else if (lastScanDate == yesterdayKey) {
        streak += 1;
      } else {
        streak = 1;
      }

      transaction.set(userRef, {
        'xp': xp,
        'scans': scans,
        'streak': streak,
        'lastScanDate': todayKey,
        'dailyCounts': dailyCounts,
        'dailyMaterials': dailyMaterials,
      }, SetOptions(merge: true));

      transaction.set(scanRef, {
        'userId': uid,
        'material': result['material'],
        'brand': result['brand'],
        'binType': result['binType'],
        'recyclable': result['recyclable'],
        'timestamp': Timestamp.now(),
        'xpEarned': baseXP,
        'firstTime': firstTimeToday,
      });
    });

    return {
      'xpEarned': baseXP,
      'bonusReasons': bonusReasons
    };
  }

  void showScanResult() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 50, color: Colors.green),
                  const SizedBox(height: 12),
                  Text(
                    "$_predictedClass",
                    style:
                        const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  if (_brand != null && _brand!.isNotEmpty)
                    Text("Brand: $_brand",
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 4),
                  if (_confidence != null)
                    Text("Confidence: $_confidence",
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _binType == 'special'
                                ? Colors.purple
                                : (_isRecyclable == true
                                    ? Colors.blue
                                    : Colors.green),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.recycling,
                              color: Colors.white, size: 20),
                        ),
                        
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _binType == 'special'
                                    ? "Special Drop-off"
                                    : (_isRecyclable == true
                                        ? "Blue Bin"
                                        : "Green Bin"),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                  _binType == 'special'
                                      ? "Requires special disposal at designated locations"
                                      : "$_tips",
                                  style: const TextStyle(
                                      fontSize: 14, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_bonusReasons.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            _binType == 'special' ? Colors.purple[50] : Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Reward Details",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _binType == 'special'
                                  ? Colors.purple[800]
                                  : Colors.blue[800],
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._bonusReasons
                              .map((reason) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.star,
                                          size: 16,
                                          color: _binType == 'special'
                                              ? Colors.purple
                                              : Colors.blue,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            reason,
                                            style: TextStyle(
                                              color: _binType == 'special'
                                                  ? Colors.purple[800]
                                                  : Colors.blue[800],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ],
                      ),
                    ),
                  ],
                  if (_binType == 'special') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.purple[800], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Special drop-off items like batteries and e-waste require proper disposal at designated locations. You earned bonus XP for responsible recycling!",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.purple[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _binType == 'special'
                          ? Colors.purple[100]
                          : Colors.amber[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.star,
                                color: _binType == 'special'
                                    ? Colors.purple
                                    : Colors.orange),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "+$_xpEarned XP Earned",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _binType == 'special'
                                        ? Colors.purple[800]
                                        : Colors.orange[800],
                                  ),
                                ),
                                if (_binType == 'special')
                                  Text(
                                    "Special Drop-off Bonus!",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.purple[800],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        Text("Streak: ${_streak ?? 0} days",
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 2),
                          Text(
                            "Scan automatically saved to your account.",
                            style: TextStyle(color: Colors.green, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        showResult = false;
                        selectedImage = null;
                      });
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2FD885),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Center(
                        child: Text("Continue Scanning",
                            style: TextStyle(color: Colors.white))),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
Widget build(BuildContext context) {
  final bg = const Color(0xFF12181B);
  final panel = const Color(0xFF182226);
  final border = const Color(0xFF233038);
  final accent = const Color(0xFF2FD885);

  return Scaffold(
    backgroundColor: bg,
    appBar: AppBar(
      backgroundColor: bg,
      elevation: 0,
      centerTitle: true,
      title: const Text("Recy.AI",
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
    ),
    body: Stack(
      children: [
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Container(
                      decoration: BoxDecoration(
                        color: panel,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: border),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [panel, const Color.fromARGB(255, 66, 65, 65)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Image(
                            image: AssetImage('images/logono.png'),
                            width: 150,
                            height: 150,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Ready to Scan",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF9FBFA),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Tap the button below to scan waste items",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFFDDE5E4),
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            // width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt_outlined,
                                  color: Colors.white,size: 20,),
                              onPressed: pickAndSendToGPT,
                              label: const Text(
                                "Start Scanning",
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2FD885),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),
                Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF182226),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF233038)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _DashButton(
                              title: "Shop Reusables",
                              subtitle: "Buy reusable items",
                              icon: Icons.storefront_outlined,
                              onTap: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const BulkyItemsList()));
                              },
                            ),
                            const Divider(color: Color(0xFF233038), height: 1),
                            _DashButton(
                              title: "Schedule Bulky Pickup",
                              subtitle: "Request for pickup",
                              icon: Icons.local_shipping_outlined,
                              onTap: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const bulky_form.BulkyItemForm()));
                              },
                            ),
                            const Divider(color: Color(0xFF233038), height: 1),
                            _DashButton(
                              title: "Clean or Fix Bin",
                              subtitle: "Request for bin service",
                              icon: Icons.delete_outline,
                              onTap: () {
                                showDialog(context: context, builder: (_) => const Dialog(child: Padding(padding: EdgeInsets.all(12), child: BinServiceButton())));
                              },
                            ),
                            const Divider(color: Color(0xFF233038), height: 1),
                            // Admin-only entry (auto-hidden if not admin)
                            const AdminDashboardButton(),
                          ],
                        ),
                      ),
              ],
            ),
          ),
        ),

        if (isProcessing)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.55),
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF182226),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF233038)),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Gif(
                        image: const AssetImage('images/animated_logo.gif'),
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                        controller: _controller,
                        autostart: Autostart.loop,
                        placeholder: (context) =>
                            const SizedBox(width: 120, height: 120),
                        onFetchCompleted: () {
                          _controller.reset();
                          _controller.forward();
                        },
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "Analyzing waste...",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
    }



class _DashButton extends StatelessWidget { 
  final String title; final String subtitle; 
  final IconData icon; final VoidCallback onTap;
   const _DashButton({ required this.title, 
   required this.subtitle, required this.icon, 
   required this.onTap, }); 
   
   @override Widget build(
    BuildContext context) { 
      return InkWell( 
        borderRadius: BorderRadius.circular(12), 
        onTap: onTap, 
        child: Padding( 
          padding: const EdgeInsets.symmetric(
            vertical: 10, horizontal: 6), 
            child: Row( 
              children: [ 
              Container( width: 44, height: 44, 
              decoration: BoxDecoration( 
                color: const Color(0xFF233038), 
                borderRadius: BorderRadius.circular(12), ), 
                child: Icon(icon, color: const Color(0xFFDDE5E4)), ), 
                const SizedBox(width: 12), 
                Expanded( 
                  child: 
                Column( 
                  crossAxisAlignment: CrossAxisAlignment.start,
                   children: [ 
                    Text(title, style: const TextStyle( 
                      color: Color(0xFFF9FBFA), 
                      fontSize: 15, fontWeight: FontWeight.w600)), 
                      const SizedBox(height: 2), 
                      Text( subtitle, style: const TextStyle( 
                        color: Color(0xFFD0D8D7), fontSize: 12.5,
                         ), 
                         ), 
                         ], 
                         ), 
                         ), 
                         const Icon(Icons.chevron_right, color: Color(0xFF95A3A1)),
                          ], 
                          ), 
                          ), 
                          ); 
                          } }
                          
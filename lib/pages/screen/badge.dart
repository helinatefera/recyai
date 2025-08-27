import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


/// A section that shows user badges based on their recycling activities.
class BadgesSection extends StatefulWidget {
  const BadgesSection({super.key});

  @override
  State<BadgesSection> createState() => _BadgesSectionState();
}

class _BadgesSectionState extends State<BadgesSection> {
  late Future<List<_BadgeData>> _badgesF;

  @override
  void initState() {
    super.initState();
    _badgesF = _computeBadges();
  }

  Future<List<_BadgeData>> _computeBadges() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _defaults();

    // fetch scans and user (for streak) in parallel
    final firestore = FirebaseFirestore.instance;
    final results = await Future.wait([
      firestore.collection('scans').where('userId', isEqualTo: uid).get(),
      firestore.collection('users').doc(uid).get(),
    ]);
    final snap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final userDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
    final userData = userDoc.data() ?? {};
    final streak = (userData['streak'] as int?) ?? 0;

    int plasticQualified = 0; // PET/HDPE with RecyScore >= 4
    int metalCans = 0;        // Aluminum/Steel cans
    int glassJars = 0;        // Clean jars/bottles (count glass items)
    int cardboardFlat = 0;    // Flattened cardboard boxes
    int hazardousDrop = 0;    // Hazardous/e-waste drop-offs

    for (final d in snap.docs) {
      final data = d.data();

      String _s(dynamic v) => v == null ? '' : v.toString().trim().toLowerCase();
      final material = _s(data['material']);               // e.g., plastic, metal, glass, cardboard, battery
      final category = _s(data['category']);               // optional
      final type = _s(data['type']);                       // optional (e.g., can, jar, bottle)
      final family = _s(data['materialFamily']);           // optional
      final resin = _s(data['resinCode'] ?? data['resin']); // optional "1"/"2"
      final action = _s(data['action']);                   // optional "flattened"
      final flattened = data['flattened'] == true || action == 'flattened';
      final dropoffFlag = data['dropoff'] == true;

      double recyScore = 0.0;
      final rs = data['recyScore'] ?? data['score'];
      if (rs is num) recyScore = rs.toDouble();
      else if (rs != null) recyScore = double.tryParse(rs.toString()) ?? 0.0;

      bool containsAny(String src, List<String> keys) =>
          keys.any((k) => src.contains(k));

      // PET / HDPE detection
      final isPET = containsAny(material, ['pet']) || resin == '1' || containsAny(family, ['pet']);
      final isHDPE = containsAny(material, ['hdpe', 'pehd']) || resin == '2' || containsAny(family, ['hdpe', 'pehd']);
      if ((isPET || isHDPE) && recyScore >= 4.0) plasticQualified++;

      // Metal cans
      final isMetal = containsAny(material, ['metal', 'aluminum', 'aluminium', 'steel']) ||
          containsAny(family, ['metal', 'aluminum', 'aluminium', 'steel']);
      final isCanLike = containsAny(type, ['can']) || containsAny(category, ['can']);
      if (isMetal || isCanLike) metalCans++;

      // Glass jars/bottles
      final isGlass = containsAny(material, ['glass']) || containsAny(family, ['glass']);
      final isJarBottle = containsAny(type, ['jar', 'bottle']) || containsAny(category, ['jar', 'bottle']);
      if (isGlass || isJarBottle) glassJars++;

      // Cardboard flattened boxes
      final isCardboard = containsAny(material, ['cardboard', 'corrugated']) || containsAny(family, ['cardboard']);
      final isBox = containsAny(type, ['box']) || containsAny(category, ['box']);
      if (isCardboard && (flattened || isBox)) cardboardFlat++;

      // Hazardous / e-waste
      final isHazardous = containsAny(material, ['battery', 'e-waste', 'ewaste', 'hazard']);
      if (isHazardous || dropoffFlag) hazardousDrop++;
    }

    // goals
    const gPlastic = 100;
    const gMetal = 100;
    const gGlass = 50;
    const gCardboard = 100;
    const gDrop = 5;
    const gStreak = 7;

    return [
      _BadgeData("Plastic Pro", "Recycle 100 PET/HDPE items (RecyScore ≥ 4).", Icons.recycling, plasticQualified, gPlastic),
      _BadgeData("Metal Master", "Recycle 100 aluminum/steel cans.", Icons.local_drink, metalCans, gMetal),
      _BadgeData("Glass Guardian", "Recycle 50 clean glass jars/bottles.", Icons.local_bar, glassJars, gGlass),
      _BadgeData("Cardboard Champ", "Flatten 100 cardboard boxes.", Icons.inventory_2, cardboardFlat, gCardboard),
      _BadgeData("Drop-off Hero", "Do 5 hazardous/e-waste drop-offs.", Icons.battery_alert, hazardousDrop, gDrop),
      _BadgeData("One-Bin Wonder", "Maintain a 7-day streak.", Icons.local_fire_department, streak, gStreak),
    ];
  }

  List<_BadgeData> _defaults() => const [
        _BadgeData("Plastic Pro", "Recycle 100 PET/HDPE items (RecyScore ≥ 4).", Icons.recycling, 0, 100),
        _BadgeData("Metal Master", "Recycle 100 aluminum/steel cans.", Icons.local_drink, 0, 100),
        _BadgeData("Glass Guardian", "Recycle 50 clean glass jars/bottles.", Icons.local_bar, 0, 50),
        _BadgeData("Cardboard Champ", "Flatten 100 cardboard boxes.", Icons.inventory_2, 0, 100),
        _BadgeData("Drop-off Hero", "Do 5 hazardous/e-waste drop-offs.", Icons.battery_alert, 0, 5),
        _BadgeData("One-Bin Wonder", "Maintain a 7-day streak.", Icons.local_fire_department, 0, 7),
      ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_BadgeData>>(
      future: _badgesF,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(color: Color(0xFF2FD885)),
            ),
          );
        }
        final badges = snap.data!;
        return SizedBox(
          height: 118,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: badges.map((b) {
                final achieved = b.count >= b.goal;
                return GestureDetector(
                  onTap: () => _showBadgeDetail(context, b),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
                    child: Column(
                      children: [
                        _ShinyCircleBadge(
                          achieved: achieved,
                          icon: b.icon,
                          radius: 28,
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 68,
                          child: Text(
                            b.title,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: achieved ? Colors.white : Colors.white54,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showBadgeDetail(BuildContext context, _BadgeData b) {
    final achieved = b.count >= b.goal;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            _ShinyCircleBadge(achieved: achieved, icon: b.icon, radius: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(b.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              b.desc,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.85)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: achieved ? const Color(0xFF2FD885).withOpacity(0.14) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: achieved ? const Color(0xFF2FD885) : Colors.white10),
              ),
              child: Text(
                '${b.count > b.goal ? b.goal : b.count} / ${b.goal}  ${achieved ? "— Achieved!" : "— Keep going"}',
                style: TextStyle(
                  color: achieved ? const Color(0xFF2FD885) : Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: Color(0xFF2FD885), fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

class _ShinyCircleBadge extends StatelessWidget {
  final bool achieved;
  final IconData icon;
  final double radius;

  const _ShinyCircleBadge({
    required this.achieved,
    required this.icon,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: achieved
            ? const LinearGradient(
                colors: [Color(0xFF2FD885), Color(0xFF0F9E84)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [Colors.white12, Colors.white10],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        boxShadow: achieved
            ? [
                BoxShadow(
                  color: const Color(0xFF2FD885).withOpacity(0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                )
              ]
            : [],
      ),
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          shape: BoxShape.circle,
          border: Border.all(
            color: achieved ? const Color(0xFF2FD885) : Colors.white10,
            width: achieved ? 1.5 : 1,
          ),
        ),
        child: Icon(
          icon,
          size: radius * 0.95,
          color: achieved ? const Color(0xFF2FD885) : Colors.white38,
        ),
      ),
    );

    return achieved
        ? circle
        : Opacity(
            opacity: 0.6,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
              child: circle,
            ),
          );
  }
}

class _BadgeData {
  final String title;
  final String desc;
  final IconData icon;
  final int count;
  final int goal;

  const _BadgeData(this.title, this.desc, this.icon, this.count, this.goal);
}

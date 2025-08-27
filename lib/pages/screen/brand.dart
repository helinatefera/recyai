import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:animate_do/animate_do.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';


/// Screen that shows brand statistics based on user scans.
class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key});

  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> brands = [];
  int totalUnrecyclable = 0;
  final currentUser = FirebaseAuth.instance.currentUser;
  final RefreshController _refreshController = RefreshController(
    initialRefresh: false,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (currentUser != null) {
      loadBrandStats();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await loadBrandStats();
    _refreshController.refreshCompleted();
  }

  Future<void> loadBrandStats() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('scans')
        .where('userId', isEqualTo: currentUser!.uid)
        .get();

    final docs = snapshot.docs;

    final Map<String, int> categoryCount = {};
    // This map will group all scans by a key (e.g., "Coca-Cola Plastic")
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final doc in docs) {
      final data = doc.data();
      final brand = (data['brand'] ?? '').toString().trim();
      final wasteType = (data['material'] ?? 'unknown').toString().trim();

      // Use a composite key to group by both brand and material
      final key = brand.isEmpty ? 'unknown_$wasteType' : '$brand $wasteType';

      categoryCount[wasteType] = (categoryCount[wasteType] ?? 0) + 1;

      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(data);
    }

    brands = grouped.entries.map((entry) {
      final all = entry.value;

      final unrecyclableCount = all
          .where((s) => s['recyclable'] == false)
          .length;

      final firstMaterial =
          all.firstWhere(
            (e) => e['material'] != null,
            orElse: () => {},
          )['material'] ??
          'Unknown';

      final categoryTotalCount = categoryCount[firstMaterial] ?? 0;

      return {
        'name': entry.key.split(' ').first,
        'category': firstMaterial.toString(),
        'count': all.length,
        'unrecyclableCount': unrecyclableCount,
        'unrecyclablePct': categoryTotalCount == 0
            ? 0
            : ((unrecyclableCount * 100) / categoryTotalCount).round(),
      };
    }).toList();

    setState(() {});
  }

  Color getBadgeColor(int pct) {
    if (pct >= 70) return const Color(0xFFF05B5B);
    if (pct >= 50) return const Color(0xFFFFB547);
    if (pct >= 30) return const Color(0xFF2FD885);
    return const Color(0xFF65DF9E);
  }

  final String wasteTypeIconsPath = 'images/wastes/';

  final Map<String, String> wasteTypeIcons = {
    'paper cups': 'paper-cups.svg',
    'cardboard boxes': 'cardboard-boxes.svg',
    'cardboard packaging': 'cardboard-packaging.svg',
    'plastic water bottle': 'plastic-water-bottle.svg',
    'styrofoam': 'styrofoam.svg',
    'plastic cup lids': 'plastic-cup-lids.svg',
    'plastic food containers': 'plastic-food-containers.svg',
    'plastic shopping bags': 'plastic-shopping-bags.svg',
    'plastic soda bottles': 'plastic-soda-bottles.svg',
    'plastic trash bags': 'plastic-trash-bags.svg',
    'plastic straws': 'plastic-straws.svg',
    'plastic items': 'plastic-items.svg',
    'paper': 'paper.svg',
    'metals': 'metals.svg',
    'glass': 'glass.svg',
    'organic': 'organic.svg',
    'e-waste': 'e-waste.svg',
    'textiles': 'textiles.svg',
    'hazardous': 'hazardous.svg',
    'unknown': 'unknown.svg',
  };

  Widget _buildBrandList(List<Map<String, dynamic>> list) {
    // This helper function is assumed to exist in your file's scope.

    return ListView.builder(
      itemCount: list.length + 1,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemBuilder: (_, i) {
        if (i == list.length) return const SizedBox(height: 100);

        final b = list[i];

        final int unrecyclablePct = (b['unrecyclablePct'] as num).toInt();

        return FadeInUp(
          delay: Duration(milliseconds: 50 * i),
          duration: const Duration(milliseconds: 300),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.0),
              color: const Color(0xFF1C1C1E),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  SvgPicture.asset(
                    wasteTypeIconsPath +
                        (wasteTypeIcons[b['category'].toLowerCase()] ??
                            'unknown.svg'),
                    width: 50,
                    height: 50,
                    colorFilter: ColorFilter.linearToSrgbGamma(),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b['name']
                              .split(' ')
                              .map(
                                (word) => word.isEmpty
                                    ? ''
                                    : word[0].toUpperCase() +
                                          word.substring(1).toLowerCase(),
                              )
                              .join(' '),
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Divider(
                          color: const Color(0xFF0F9E84).withOpacity(0.2),
                          height: 1,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b['category']
                                      .split(' ')
                                      .map(
                                        (word) => word.isEmpty
                                            ? ''
                                            : word[0].toUpperCase() +
                                                  word
                                                      .substring(1)
                                                      .toLowerCase(),
                                      )
                                      .join(' '),
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.camera_enhance_outlined,
                                      color: Colors.white.withOpacity(0.5),
                                      size: 15,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${b['count']} Scans",
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            SizedBox(
                              width: 45,
                              height: 45,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: unrecyclablePct / 100.0,
                                    strokeWidth: 4.5,
                                    backgroundColor: Colors.white.withOpacity(
                                      0.1,
                                    ),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      getBadgeColor(unrecyclablePct),
                                    ),
                                  ),
                                  Text(
                                    '$unrecyclablePct%',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
    final worst = brands.where((b) => b['unrecyclablePct'] >= 5).toList()
      ..sort((a, b) => b['unrecyclablePct'].compareTo(a['unrecyclablePct']));
    final best = brands.where((b) => b['unrecyclablePct'] < 5).toList()
      ..sort((a, b) => b['unrecyclablePct'].compareTo(a['unrecyclablePct']));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        elevation: 0,
        
        backgroundColor: Color(0xFF1C1C1E), 
        title: Text(
          "Top Brand Tracker",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            fontSize: 21,
            color: Colors.white.withOpacity(0.9),
          ),
        ),

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 4.0),
            child: Container(
              height: 40, 
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2C),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                dividerHeight: 0,
                indicator: BoxDecoration(
                  color: const Color(0xFF2FD885),
                  borderRadius: BorderRadius.circular(
                    10.0,
                  ), 
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                    ),
                  ],
                ),

                indicatorPadding: const EdgeInsets.all(3.0),

                labelColor: Colors.grey.shade900, // Dark blue for active text
                unselectedLabelColor: Colors.white.withOpacity(0.6),
                labelStyle: GoogleFonts.roboto(
                  fontWeight: FontWeight.w900, // Medium
                  fontSize: 14,
                ),
                unselectedLabelStyle: GoogleFonts.roboto(
                  fontWeight: FontWeight.w500, // Medium
                  fontSize: 14,
                ),

                tabs: const [
                  Tab(text: 'Worst Offenders'),
                  Tab(text: 'Rising Stars'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: SmartRefresher(
        controller: _refreshController,
        onRefresh: _onRefresh,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildBrandList(worst), // Content for the "Worst Offenders" tab
            _buildBrandList(best), // Content for the "Rising Stars" tab
          ],
        ),
      ),
    );
  }
}

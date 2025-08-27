import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:animate_do/animate_do.dart';
import './badge.dart';
import './yearly_calander.dart';


class UserStats {
  final int lifetimeScanned;
  final int  xpEarned;
  final int currentStreak;
  final int globalRank;

  UserStats({
    required this.lifetimeScanned,
    required this.xpEarned,
    required this.currentStreak,
    required this.globalRank,
  });
}

class TrackScreen extends StatefulWidget {
  const TrackScreen({super.key});

  @override
  State<TrackScreen> createState() => _TrackScreenState();
}

class _TrackScreenState extends State<TrackScreen> {
  final RefreshController _refreshController =
      RefreshController(initialRefresh: false);

  @override
  void dispose() {
    _refreshController.dispose();
    super.dispose();
  }

  Future<_Stats> _getStats() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firestore = FirebaseFirestore.instance;

    final userSnap = await firestore.collection('users').doc(uid).get();
    final userData = userSnap.data() ?? {};
    final currentUserXp = userData['xp'] as int? ?? 0;

    final rankQuery = await firestore
        .collection('users')
        .where('xp', isGreaterThan: currentUserXp)
        .count()
        .get();

    final higherRankedUsers = rankQuery.count;
    final globalRank = (higherRankedUsers ?? 0) + 1;

    final now = DateTime.now();
    final weekStart =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final scanSnap = await firestore
        .collection('scans')
        .where('userId', isEqualTo: uid)
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart),
        )
        .get();

    int weeklyRecycled = 0, weeklyNonRecycled = 0;
    for (final doc in scanSnap.docs) {
      if (doc.data().containsKey('recyclable') && doc['recyclable'] == true) {
        weeklyRecycled++;
      } else {
        weeklyNonRecycled++;
      }
    }

    final allSnap = await firestore
        .collection('scans')
        .where('userId', isEqualTo: uid)
        .get();

    int lifetimeRecycled = 0;
    for (final doc in allSnap.docs) {
      if (doc.data().containsKey('recyclable') && doc['recyclable'] == true) {
        lifetimeRecycled++;
      }
    }
    
    final lifetimeScanned = allSnap.size;
    final _xpEarned = currentUserXp;

    return _Stats(
      userData: userData,
      weeklyScanned: weeklyRecycled + weeklyNonRecycled,
      weeklyRecycled: weeklyRecycled,
      weeklyNonRecycled: weeklyNonRecycled,
      lifetimeScanned: lifetimeScanned,
      xpEarned: _xpEarned,
      lifetimeRecycled: lifetimeRecycled,
      globalRank: globalRank,
    );
  }

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {});
    }
    _refreshController.refreshCompleted();
  }

  Widget _buildImpactHeader(BuildContext context, _Stats stats) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final headerHeight = screenHeight * 0.35;

    final headerStats = UserStats(
      lifetimeScanned: stats.lifetimeScanned,
      xpEarned: stats.xpEarned,
      currentStreak: stats.userData['streak'] ?? 0,
      globalRank: stats.globalRank,
    );

    return FadeInDown(
      duration: const Duration(milliseconds: 800),
      child: SizedBox(
        height: headerHeight,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: headerHeight * 0.85,
                width: double.infinity,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('images/auth.jpg'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: headerHeight * 0.85,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withOpacity(0.4), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              child: _buildImpactCard(context, screenWidth, headerStats),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImpactCard(BuildContext context, double screenWidth, UserStats stats) {
    return Container(
      width: screenWidth * 0.85,
      padding: const EdgeInsets.all(2.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2FD885).withOpacity(0.8),
            const Color(0xFF2FD885).withOpacity(0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: -5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeIn(
              duration: const Duration(milliseconds: 1000),
              child: Text(
                "Your Eco-Impact",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.9),
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Divider(
              color: Color(0xFF2FD885),
              thickness: 0.5,
              height: 30,
              indent: 20,
              endIndent: 20,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                BounceInLeft(
                  duration: const Duration(milliseconds: 1200),
                  child: _buildSideStat("Streak", "${stats.currentStreak} Days", Icons.local_fire_department_rounded),
                ),
                FadeInUp(
                  duration: const Duration(milliseconds: 1000),
                  child: _buildMainStat(stats.xpEarned),
                ),
                BounceInRight(
                  duration: const Duration(milliseconds: 1200),
                  child: _buildSideStat("Rank", stats.globalRank > 0 ? "#${stats.globalRank}" : "N/A", Icons.leaderboard_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainStat(int value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value.toDouble()),
          duration: const Duration(milliseconds: 1500),
          builder: (context, animatedValue, child) {
            return Text(
              animatedValue.toInt().toString(),
              style: const TextStyle(
                color: Color(0xFF2FD885),
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        const Text(
          "Total XP Earned",
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSideStat(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF2FD885), size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildContentCard({required String title, required Widget child}) {
    return FadeInUp(
      duration: const Duration(milliseconds: 800),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: FutureBuilder<_Stats>(
          future: _getStats(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2FD885)),
              );
            }
            if (snap.hasError || !snap.hasData) {
              return Center(
                child: Text(
                  'Error loading stats.\nPlease pull to refresh.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
              );
            }
            final s = snap.data!;
            final now = DateTime.now();
            final todayKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
            final dailyCounts = Map<String, dynamic>.from(s.userData['dailyCounts'] ?? {});
            final todayCount = dailyCounts[todayKey] ?? 0;
            final dailyGoal = s.userData['dailyGoal'] ?? 5;
            final progress = (todayCount / dailyGoal).clamp(0.0, 1.0);

            final weekDays = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
            final weeklyStats = weekDays.map((day) {
              final key = "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
              final count = dailyCounts[key] as int? ?? 0;
              final maxDaily = (dailyGoal * 1.5).clamp(10, 100).toDouble();
              return {
                'day': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.weekday - 1],
                'height': (count / maxDaily).clamp(0.0, 1.0),
              };
            }).toList();

            return SmartRefresher(
              controller: _refreshController,
              onRefresh: _onRefresh,
              header: const WaterDropHeader(waterDropColor: Color(0xFF2FD885)),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildImpactHeader(context, s),
                    Padding(
                      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 400 ? 8.0 : 16.0),
                      child: Column(
                        children: [
                          _buildContentCard(
                            title: "Today's Progress",
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    children: [
                                      Text(
                                        "Goal: $todayCount / $dailyGoal",
                                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.local_fire_department, color: Color(0xFFFFB547), size: 20),
                                          const SizedBox(width: 6),
                                          Text(
                                            "${s.userData['streak'] ?? 0} day streak!",
                                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9), fontSize: 16),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ZoomIn(
                                        duration: const Duration(milliseconds: 1000),
                                        child: SizedBox(
                                          width: 80,
                                          height: 80,
                                          child: CircularProgressIndicator(
                                            value: progress,
                                            strokeWidth: 8,
                                            backgroundColor: Colors.white.withOpacity(0.1),
                                            color: const Color(0xFF2FD885),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        "${(progress * 100).toInt()}%",
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildContentCard(
                            title: "This Week",
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: weeklyStats.asMap().entries.map((entry) {
                                    int index = entry.key;
                                    var stat = entry.value;
                                    return SlideInUp(
                                      delay: Duration(milliseconds: 200 * index),
                                      duration: const Duration(milliseconds: 800),
                                      child: Column(
                                        children: [
                                          Container(
                                            width: 16,
                                            height: 100 * (stat['height'] as double),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [Color(0xFF2FD885), Color(0xFF0F9E84)],
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              ),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            stat['day'].toString(),
                                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const Divider(height: 32, color: Colors.white12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    FadeInLeft(
                                      duration: const Duration(milliseconds: 800),
                                      child: _block(s.weeklyScanned, "Scanned"),
                                    ),
                                    FadeInUp(
                                      duration: const Duration(milliseconds: 800),
                                      child: _block(s.weeklyRecycled, "Recycled"),
                                    ),
                                    FadeInRight(
                                      duration: const Duration(milliseconds: 800),
                                      child: _block(s.weeklyNonRecycled, "Other"),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),                          
                          
                          const SizedBox(height: 16),
                          _buildContentCard(
                            title: "📊 Impact Tracker",
                            child: const RectYearCalendar(),
                          ),

                          const SizedBox(height: 16),
                          _buildContentCard(
                            title: "🏅 Eco-Badges",
                            child: const BadgesSection(),
                          ),
                          
                          const SizedBox(height: 16),
                          _buildContentCard(
                            title: "Lifetime Impact",
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final screenHeight = MediaQuery.of(context).size.height;
                                final gridHeight = (screenHeight * 0.20).clamp(150.0, 250.0);
                                final screenWidth = MediaQuery.of(context).size.width;
                                final aspectRatio = (screenWidth < 400) ? 1.5 : 1.8;

                                return SizedBox(
                                  height: gridHeight,
                                  child: GridView.count(
                                    crossAxisCount: 2,
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: aspectRatio,
                                    children: [
                                      ZoomIn(
                                        duration: const Duration(milliseconds: 800),
                                        child: _buildLifetimeStat(
                                          "${s.lifetimeRecycled}",
                                          "Recycled",
                                          Icons.eco,
                                          const Color(0xFF2FD885),
                                          screenWidth,
                                        ),
                                      ),
                                      ZoomIn(
                                        delay: const Duration(milliseconds: 200),
                                        duration: const Duration(milliseconds: 800),
                                        child: _buildLifetimeStat(
                                          "${s.lifetimeScanned - s.lifetimeRecycled}",
                                          "Other",
                                          Icons.inventory_2,
                                          Colors.white70,
                                          screenWidth,
                                        ),
                                      ),
  
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _block(int value, String label) => Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
          ),
        ],
      );

  Widget _buildLifetimeStat(String value, String label, IconData icon, Color color, double screenWidth) {
    final fontSizeValue = (screenWidth < 400) ? 16.0 : 18.0;
    final fontSizeLabel = (screenWidth < 400) ? 10.0 : 12.0;
    final iconSize = (screenWidth < 400) ? 16.0 : 18.0;
    final padding = (screenWidth < 400) ? 6.0 : 8.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: fontSizeValue,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Icon(icon, color: color, size: iconSize),
            ],
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: fontSizeLabel,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height * 0.8);

    var firstControlPoint = Offset(size.width / 4, size.height);
    var firstEndPoint = Offset(size.width / 2, size.height * 0.9);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    var secondControlPoint = Offset(size.width * 3 / 4, size.height * 0.8);
    var secondEndPoint = Offset(size.width, size.height * 0.9);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _Stats {
  final Map<String, dynamic> userData;
  final int weeklyScanned;
  final int weeklyRecycled;
  final int weeklyNonRecycled;
  final int lifetimeScanned;
  final int xpEarned;
  final int lifetimeRecycled;
  final int globalRank;

  _Stats({
    required this.userData,
    required this.weeklyScanned,
    required this.weeklyRecycled,
    required this.weeklyNonRecycled,
    required this.lifetimeScanned,
    required this.xpEarned,
    required this.lifetimeRecycled,
    required this.globalRank,
  });
}
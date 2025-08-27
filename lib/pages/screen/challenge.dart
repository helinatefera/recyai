import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_fonts/google_fonts.dart';


/// Screen for neighborhood challenges.
class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});
  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  bool isJoining = false;
  bool _loading = true;

  late TextEditingController _joinCodeController;
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
  final PageController _pageController = PageController();

  final Set<String> _celebratedInSession = {};
  final Set<String> _awardedOncePerPeriod = {};

  List<Map<String, dynamic>> _challenges = [];
  List<Map<String, dynamic>> _leaderboard = [];

  // quests config & per-quest progress
  List<Map<String, dynamic>> _dailyQuests = [];
  List<Map<String, dynamic>> _weeklyQuests = [];
  Map<String, int> _dailyProg = {};
  Map<String, int> _weeklyProg = {};

  @override
  void initState() {
    super.initState();
    _joinCodeController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _joinCodeController.dispose();
    _refreshController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _fetchActiveChallengesData(),
      _fetchTopUsersData(),
      _fetchQuestsAndProgress(),
    ]);
    if (!mounted) return;
    setState(() {
      _challenges = results[0] as List<Map<String, dynamic>>;
      _leaderboard = results[1] as List<Map<String, dynamic>>;
      _loading = false;
    });
  }

  void _onRefresh() async {
    await _loadData();
    _refreshController.refreshCompleted();
  }

  Future<void> handleJoinChallenge() async {
    final code = _joinCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => isJoining = true);

    final user = FirebaseAuth.instance.currentUser;
    final challengeDoc = await FirebaseFirestore.instance.collection('challenges').doc(code).get();

    if (challengeDoc.exists && user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'challengeId': code});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You've joined the challenge successfully."),
            backgroundColor: Color(0xFF2FD885),
          ),
        );
      }
      await _loadData();
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid challenge code.")),
        );
      }
    }

    setState(() {
      _joinCodeController.clear();
      isJoining = false;
    });
  }


Future<void> _maybeCelebrateChallenge(String challengeId, String title) async {
  if (_celebratedInSession.contains(challengeId)) return;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
  final snap = await userRef.get();
  final List<dynamic> already = (snap.data()?['celebratedChallengeIds'] as List?) ?? [];

  if (already.contains(challengeId)) {
    _celebratedInSession.add(challengeId);
    return;
  }

  await userRef.set({
    'celebratedChallengeIds': FieldValue.arrayUnion([challengeId]),
  }, SetOptions(merge: true));

  _celebratedInSession.add(challengeId);

  if (!mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text("🎉 Congratulations!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: Text(
        'You completed challenge "$title" 🎉',
        style: const TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("OK", style: TextStyle(color: Color(0xFF2FD885))),
        ),
      ],
    ),
  );
}


  Future<List<Map<String, dynamic>>> _fetchTopUsersData() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .orderBy('xp', descending: true)
        .limit(3)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'name': data['name'] ?? 'User',
        'items': data['xp'] ?? 0,
        'uid': doc.id,
        'photoUrl': data['photoUrl'] ?? '',
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchActiveChallengesData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final uid = user.uid;
    final now = DateTime.now();

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final joinedChallengeId = userDoc.data()?['challengeId'];

    final createdSnapshot = await FirebaseFirestore.instance
        .collection('challenges')
        .where('creatorId', isEqualTo: uid)
        .where('active', isEqualTo: true)
        .get();

    DocumentSnapshot? joinedSnapshot;
    if (joinedChallengeId != null) {
      joinedSnapshot = await FirebaseFirestore.instance.collection('challenges').doc(joinedChallengeId).get();
    }

    final List<Map<String, dynamic>> challenges = [];
    final Set<String> challengeIds = {};

    for (final doc in createdSnapshot.docs) {
      if (challengeIds.add(doc.id)) {
        final data = doc.data();
        final DateTime end = (data['end'] as Timestamp).toDate();
        if (end.isAfter(now)) {
          challenges.add({...data, 'id': doc.id, 'isCreator': true});
        }
      }
    }

    if (joinedSnapshot != null && joinedSnapshot.exists && challengeIds.add(joinedSnapshot.id)) {
      final data = joinedSnapshot.data() as Map<String, dynamic>;
      final DateTime end = (data['end'] as Timestamp).toDate();
      if (end.isAfter(now) && (data['active'] == true)) {
        challenges.add({...data, 'id': joinedSnapshot.id, 'isCreator': false});
      }
    }

    if (challenges.isEmpty) return [];

    for (final challenge in challenges) {
      final DateTime start = (challenge['start'] as Timestamp).toDate();
      final DateTime end = (challenge['end'] as Timestamp).toDate();
      final DateTime upper = DateTime.now().isBefore(end) ? DateTime.now() : end;

      final scanSnapshot = await FirebaseFirestore.instance
          .collection('scans')
          .where('userId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(upper))
          // no orderBy to avoid composite index requirement
          .get();

      challenge['userScans'] = scanSnapshot.docs.length;
    }

    return challenges;
  }

  // -------------------- QUESTS (config + progress) --------------------

  String _mat(dynamic v) => (v?.toString().trim().toLowerCase() ?? '');
  bool _isPET(String m) =>
      m == 'pet' || m == 'pet plastic' || m == 'plastic_pet' || m == 'plastic (pet)' || m == 'plastic-pet' || m == 'pet bottle';

  Future<List<String>> _materialsInRange(DateTime from, DateTime to) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('scans')
          .where('userId', isEqualTo: uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(to))
          // no orderBy (keeps it index-light)
          .get();
      return snap.docs.map((d) => _mat(d.data()['material'])).toList();
    } catch (_) {
      return [];
    }
  }

  int _countWhere(Iterable<String> mats, bool Function(String) test) {
    var c = 0;
    for (final m in mats) {
      if (test(m)) c++;
    }
    return c;
  }

  Future<void> _computeDailyProgress(DateTime dayStart, DateTime dayEnd) async {
    final mats = await _materialsInRange(dayStart, dayEnd);
    final distinctFamilies = mats.toSet();

    _dailyProg = {
      'quick_clean': mats.length, // goal will be compared against config (set goal=4 in /config/quests)
      'mix_it_up': distinctFamilies.length,
      'prep_pro': _countWhere(mats, (m) => m == 'cardboard'),
    };
  }

  Future<void> _computeWeeklyProgress(DateTime weekStart, DateTime weekEnd) async {
    final mats = await _materialsInRange(weekStart, weekEnd);

    // weekly specifics, keyed by ids from /config/quests
    _weeklyProg = {
      'metal_monday': _countWhere(mats, (m) => m == 'metal'),
      'pet_focus': _countWhere(mats, (m) => _isPET(m)),
      'glass_class': _countWhere(mats, (m) => m == 'glass'),
      'drop_off_done': _countWhere(mats, (m) => m == 'e-waste' || m == 'battery' || m == 'ewaste'),
    };
  }

  Future<void> _autoAwardPerQuest({
    required List<Map<String, dynamic>> quests,
    required bool isDaily,
  }) async {
    for (final q in quests) {
      final id = (q['id'] ?? '') as String;
      if (id.isEmpty) continue;
      final goal = (q['goal'] ?? 0) as int;
      final xp = (q['xp'] ?? 0) as int;

      final progMap = isDaily ? _dailyProg : _weeklyProg;
      final progress = (progMap[id] ?? 0);

      final keySuffix = isDaily ? _dayKey() : _weekKey();
      final sessionKey = '${isDaily ? "D" : "W"}::$id::$keySuffix';

      if (progress >= goal && !_awardedOncePerPeriod.contains(sessionKey)) {
        await _addXp(xp);
        _awardedOncePerPeriod.add(sessionKey);
        if (!mounted) continue;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 ${q['title'] ?? id} complete! +$xp XP added'),
            backgroundColor: const Color(0xFF2FD885),
          ),
        );
      }
    }
  }

  Future<void> _addXp(int add) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await tx.get(userRef);
      final currentXp = (snap.data()?['xp'] ?? 0) as int;
      tx.update(userRef, {'xp': currentXp + add});
    });
  }

  Future<void> _fetchQuestsAndProgress() async {
    final cfg = await FirebaseFirestore.instance.collection('config').doc('quests').get(); // /config/quests
    final data = cfg.data() ?? {};
    final daily = (data['daily'] as List?) ?? [];
    final weekly = (data['weekly'] as List?) ?? [];

    _dailyQuests = daily.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    _weeklyQuests = weekly.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();

    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    final weekStart = dayStart.subtract(Duration(days: dayStart.weekday % 7)); // Sunday start
    final weekEnd = weekStart.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));

    await _computeDailyProgress(dayStart, dayEnd);
    await _computeWeeklyProgress(weekStart, weekEnd);

    await _autoAwardPerQuest(quests: _dailyQuests, isDaily: true);
    await _autoAwardPerQuest(quests: _weeklyQuests, isDaily: false);

    if (mounted) setState(() {});
  }

  String _dayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  String _weekKey() {
    final d = DateTime.now();
    final start = DateTime(d.year, d.month, d.day).subtract(Duration(days: DateTime(d.year, d.month, d.day).weekday % 7));
    return '${start.year}-${start.month}-${start.day}';
  }

  String generateJoinCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _deleteChallenge(String challengeId) async {
    final batch = FirebaseFirestore.instance.batch();
    final challengeRef = FirebaseFirestore.instance.collection('challenges').doc(challengeId);

    batch.update(challengeRef, {
      'active': false,
      'end': Timestamp.now(),
    });

    final usersSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('challengeId', isEqualTo: challengeId)
        .get();

    for (final u in usersSnap.docs) {
      batch.update(u.reference, {'challengeId': FieldValue.delete()});
    }

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Challenge closed and removed from participants.'), backgroundColor: Color(0xFF2FD885)),
    );
    await _loadData();
  }

  Widget _buildContentCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white.withOpacity(0.9),
              )),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _questTile(Map<String, dynamic> q, {required bool isDaily}) {
    final id = (q['id'] ?? '') as String;
    final title = (q['title'] ?? id) as String;
    final subtitle = (q['subtitle'] ?? '') as String;
    final goal = (q['goal'] ?? 0) as int;
    final xp = (q['xp'] ?? 0) as int;

    final progMap = isDaily ? _dailyProg : _weeklyProg;
    final progress = (progMap[id] ?? 0);
    final capped = progress > goal ? goal : progress;
    final ratio = goal > 0 ? (progress / goal).clamp(0.0, 1.0) : 0.0;
    final done = progress >= goal;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: done
              ? [const Color(0xFF2FD885).withOpacity(0.25), const Color(0xFF2FD885).withOpacity(0.05)]
              : [const Color(0xFF1E1F22), const Color(0xFF1A1B1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: done ? const Color(0xFF2FD885) : Colors.white.withOpacity(0.08), width: done ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: done ? const Color(0xFF2FD885).withOpacity(0.15) : Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? const Color(0xFF2FD885) : Colors.white.withOpacity(0.08),
                ),
                alignment: Alignment.center,
                child: Icon(done ? Icons.check_rounded : Icons.recycling_rounded,
                    size: 22, color: done ? Colors.black : Colors.white70),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2FD885).withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2FD885)),
                ),
                child: Text('+$xp XP',
                    style: const TextStyle(color: Color(0xFF2FD885), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6.0, left: 48),
              child: Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 12,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(done ? const Color(0xFF2FD885) : Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$capped / $goal',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              Text(done ? 'Completed (XP added)' : 'Keep going',
                  style: TextStyle(color: done ? const Color(0xFF2FD885) : Colors.white70, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = _challenges.length > 1;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 10),
            Text(
              "Neighborhood Challenges",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 21,
                color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.9),
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: SmartRefresher(
            controller: _refreshController,
            onRefresh: _onRefresh,
            header: const WaterDropHeader(waterDropColor: Color(0xFF2FD885)),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF2FD885)))
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_challenges.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 20, bottom: 20),
                            child: Center(
                              child: Text(
                                "No active challenges. Join or create one!",
                                style: TextStyle(color: Colors.white70, fontSize: 16),
                              ),
                            ),
                          )
                        else
                          FadeInUp(
                            duration: const Duration(milliseconds: 600),
                            child: SizedBox(
                              height: 210,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  PageView.builder(
                                    controller: _pageController,
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _challenges.length,
                                    itemBuilder: (context, index) {
                                      final c = _challenges[index];
                                      final DateTime end = (c['end'] as Timestamp).toDate();
                                      final int progress = (c['userScans'] ?? 0) as int;
                                      final int goal = (c['goal'] ?? 1) as int;
                                      final double ratio = goal > 0 ? (progress / goal).clamp(0.0, 1.0) : 0.0;
                                      final int daysLeft = end.difference(DateTime.now()).inDays;
                                      final displayProgress = progress > goal ? goal : progress;

                                      String? message;
                                      if (ratio >= 1.0) {
                                        message = "🎉 You completed the challenge! Amazing job!";
                                        final sid = c['id'] as String? ?? '';
                                        if (sid.isNotEmpty) {
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            _maybeCelebrateChallenge(sid, (c['title'] as String?) ?? 'Challenge');
                                          });
                                        }
                                      } else if (ratio >= 0.75) {
                                        message = "💪 You're almost there! Just a little more!";
                                      } else if (ratio >= 0.5) {
                                        message = "🔥 Great progress! You're halfway to your goal!";
                                      }


                                      return Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 8),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              const Color(0xFF2FD885).withOpacity(0.9),
                                              const Color.fromARGB(255, 69, 138, 125),
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    c['title'],
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 18,
                                                      color: Colors.white,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.white.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(20),
                                                      ),
                                                      child: Text(
                                                        ratio >= 1.0 ? "Completed" : "Active",
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    if (c['isCreator'] == true) ...[
                                                      const SizedBox(width: 6),
                                                      IconButton(
                                                        tooltip: 'Delete challenge',
                                                        onPressed: () async {
                                                          final confirm = await showDialog<bool>(
                                                            context: context,
                                                            builder: (_) => AlertDialog(
                                                              backgroundColor: const Color(0xFF1C1C1E),
                                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                              title: const Text('Delete Challenge?', style: TextStyle(color: Colors.white)),
                                                              content: const Text(
                                                                'This will close the challenge and remove it from all participants.',
                                                                style: TextStyle(color: Colors.white70),
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () => Navigator.pop(context, false),
                                                                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                                                ),
                                                                TextButton(
                                                                  onPressed: () => Navigator.pop(context, true),
                                                                  child: const Text('Delete', style: TextStyle(color: Color(0xFFEA4335))),
                                                                ),
                                                              ],
                                                            ),
                                                          );
                                                          if (confirm == true) {
                                                            await _deleteChallenge(c['id'] as String);
                                                          }
                                                        },
                                                        icon: const Icon(Icons.delete_forever, color: Colors.white),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                            if (c['isCreator'] == true)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 8.0),
                                                child: SelectableText(
                                                  "Join Code: ${c['id']}",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            const Spacer(),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: LinearProgressIndicator(
                                                value: ratio,
                                                minHeight: 12,
                                                backgroundColor: Colors.black.withOpacity(0.2),
                                                valueColor: const AlwaysStoppedAnimation(Colors.white),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            if (message != null)
                                              Center(
                                                child: Text(
                                                  message,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text.rich(
                                                  TextSpan(
                                                    children: [
                                                      TextSpan(
                                                        text: "$displayProgress",
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                      TextSpan(
                                                        text: " / ${c['goal']} items",
                                                        style: TextStyle(
                                                          color: Colors.white.withOpacity(0.8),
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  "${daysLeft >= 0 ? daysLeft : 0} days left",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  if (hasMultiple)
                                    Positioned(
                                      left: -10,
                                      child: IconButton(
                                        icon: const Icon(Icons.chevron_left, color: Colors.white, size: 40),
                                        onPressed: () {
                                          _pageController.previousPage(
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeInOut,
                                          );
                                        },
                                      ),
                                    ),
                                  if (hasMultiple)
                                    Positioned(
                                      right: -10,
                                      child: IconButton(
                                        icon: const Icon(Icons.chevron_right, color: Colors.white, size: 40),
                                        onPressed: () {
                                          _pageController.nextPage(
                                            duration: const Duration(milliseconds: 300),
                                            curve: Curves.easeInOut,
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                        const SizedBox(height: 24),

                        FadeInUp(
                          delay: const Duration(milliseconds: 200),
                          duration: const Duration(milliseconds: 800),
                          child: _buildContentCard(
                            title: "Neighborhood Leaderboard",
                            child: _leaderboard.isEmpty
                                ? const Center(child: Text("No users found.", style: TextStyle(color: Colors.white70)))
                                : Column(
                                    children: _leaderboard.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final user = entry.value;
                                      final isCurrent = user['uid'] == FirebaseAuth.instance.currentUser?.uid;
                                      final String photoUrl = user['photoUrl'] ?? '';

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isCurrent ? const Color(0xFF2FD885).withOpacity(0.15) : Colors.white.withOpacity(0.05),
                                          borderRadius: BorderRadius.circular(12),
                                          border: isCurrent ? Border.all(color: const Color(0xFF2FD885), width: 1.5) : null,
                                        ),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: index == 0
                                                  ? const Color(0xFFFFD700)
                                                  : index == 1
                                                      ? const Color(0xFFC0C0C0)
                                                      : const Color(0xFFCD7F32),
                                              child: Text("${index + 1}",
                                                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                            ),
                                            const SizedBox(width: 12),
                                            CircleAvatar(
                                              radius: 20,
                                              backgroundColor: Colors.grey.shade800,
                                              backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                                              child: photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.white70, size: 20) : null,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                user['name'],
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              "${user['items']} XP",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        FadeInUp(
                          delay: const Duration(milliseconds: 400),
                          duration: const Duration(milliseconds: 800),
                          child: _buildContentCard(
                            title: "How to Participate",
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _joinCodeController,
                                  builder: (context, value, child) {
                                    final isButtonEnabled = value.text.trim().isNotEmpty && !isJoining;
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _joinCodeController,
                                            style: const TextStyle(color: Colors.white),
                                            decoration: InputDecoration(
                                              hintText: "Enter challenge code",
                                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                                              ),
                                              focusedBorder: const OutlineInputBorder(
                                                borderRadius: BorderRadius.all(Radius.circular(8)),
                                                borderSide: BorderSide(color: Color(0xFF2FD885)),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: isButtonEnabled ? handleJoinChallenge : null,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: isButtonEnabled ? const Color(0xFF2FD885) : const Color(0xFF2FD885).withOpacity(0.5),
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: Text(
                                            isJoining ? "Joining..." : "Join",
                                            style: TextStyle(
                                              color: isButtonEnabled ? Colors.black : Colors.black.withOpacity(0.5),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                Center(
                                  child: Text(
                                    "— OR —",
                                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Center(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2FD885).withOpacity(0.2),
                                      side: const BorderSide(color: Color(0xFF2FD885)),
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.add, color: Color(0xFF2FD885)),
                                    label: const Text("Create a New Challenge", style: TextStyle(color: Color(0xFF2FD885))),
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) => CreateChallengeDialog(
                                        onChallengeCreated: _loadData,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        if (_dailyQuests.isNotEmpty)
                          FadeInUp(
                            delay: const Duration(milliseconds: 120),
                            duration: const Duration(milliseconds: 600),
                            child: _buildContentCard(
                              title: "🔥 Daily Quests",
                              child: Column(
                                children: _dailyQuests.map((q) => _questTile(q, isDaily: true)).toList(),
                              ),
                            ),
                          ),
                         const SizedBox(height: 16),

                        if (_weeklyQuests.isNotEmpty)
                          FadeInUp(
                            delay: const Duration(milliseconds: 160),
                            duration: const Duration(milliseconds: 600),
                            child: _buildContentCard(
                              title: "📅 Weekly Quests",
                              child: Column(
                                children: _weeklyQuests.map((q) => _questTile(q, isDaily: false)).toList(),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class CreateChallengeDialog extends StatefulWidget {
  final VoidCallback? onChallengeCreated;
  const CreateChallengeDialog({super.key, this.onChallengeCreated});
  @override
  _CreateChallengeDialogState createState() => _CreateChallengeDialogState();
}

class _CreateChallengeDialogState extends State<CreateChallengeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _goalController = TextEditingController();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  bool _submitting = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    final challengeId = FirebaseFirestore.instance.collection('challenges').doc().id;
    final user = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance.collection('challenges').doc(challengeId).set({
      'id': challengeId,
      'title': _titleController.text.trim(),
      'goal': int.tryParse(_goalController.text.trim()) ?? 50,
      'start': Timestamp.now(),
      'end': Timestamp.fromDate(_endDate),
      'active': true,
      'creatorId': user?.uid,
    });

    if (context.mounted) Navigator.of(context).pop();
    widget.onChallengeCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text("Create New Challenge", style: TextStyle(color: Colors.white)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Challenge Title", labelStyle: TextStyle(color: Colors.white70)),
                validator: (v) => v == null || v.trim().isEmpty ? "Title is required" : null,
              ),
              TextFormField(
                controller: _goalController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "Recycling Goal (items)",
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                validator: (v) => v == null || int.tryParse(v.trim()) == null ? "Enter a valid number" : null,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Ends on:", style: TextStyle(color: Colors.white.withOpacity(0.8))),
                  TextButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) setState(() => _endDate = date);
                    },
                    child: Text("${_endDate.toLocal()}".split(' ')[0],
                        style: const TextStyle(color: Color(0xFF2FD885), fontWeight: FontWeight.bold)),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text("Cancel", style: TextStyle(color: _submitting ? Colors.white30 : Colors.white70)),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2FD885),
            minimumSize: const Size(100, 36),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                )
              : const Text("Create", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

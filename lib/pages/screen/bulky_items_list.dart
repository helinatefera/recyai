import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class BulkyItemsList extends StatefulWidget {
  const BulkyItemsList({super.key});

  @override
  State<BulkyItemsList> createState() => _BulkyItemsListState();
}

class _BulkyItemsListState extends State<BulkyItemsList> {
  final Color _bg = const Color(0xFF12181B);
  final Color _panel = const Color(0xFF182226);
  final Color _border = const Color(0xFF233038);
  final Color _textPrimary = const Color(0xFFF9FBFA);
  final Color _textSecondary = const Color(0xFFDDE5E4);
  final Color _accent = const Color(0xFF2FD885);

  final TextEditingController _searchCtl = TextEditingController();
  String _searchTerm = '';
  String? _pickingId;

  bool _showMyPicks = false;

  final RefreshController _refreshController = RefreshController(initialRefresh: false);

  @override
  void dispose() {
    _searchCtl.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _itemsStream() {
    final col = FirebaseFirestore.instance.collection('bulky_items');
    if (_showMyPicks) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        // Query that returns nothing when not signed in
        return col.where('pickedBy', isEqualTo: '_no_user_').orderBy('createdAt', descending: true).snapshots();
      }
      return col.where('pickedBy', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots();
    } else {
      return col.where('isPicked', isEqualTo: false).orderBy('createdAt', descending: true).snapshots();
    }
  }

  Future<void> _pickItem(BuildContext context, String itemId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to pick items')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Pickup'),
        content: const Text('Mark this bulky item as picked by you?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _pickingId = itemId);
    try {
      await FirebaseFirestore.instance.collection('bulky_items').doc(itemId).update({
        'isPicked': true,
        'pickedBy': user.uid,
        'pickedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item picked successfully')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingId = null);
    }
  }

  Future<void> _openMap(String location) async {
    final parts = location.split(',');
    if (parts.length < 2) return;
    final lat = parts[0].trim();
    final lon = parts[1].trim();
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openImageFullScreen(String id, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _FullscreenImage(heroTag: id, imageUrl: url)),
    );
  }

  Future<void> _onRefresh() async {
    try {
      final col = FirebaseFirestore.instance.collection('bulky_items');
      if (_showMyPicks) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '_no_user_';
        await col.where('pickedBy', isEqualTo: uid).orderBy('createdAt', descending: true).limit(1).get(
              const GetOptions(source: Source.server),
            );
      } else {
        await col.where('isPicked', isEqualTo: false).orderBy('createdAt', descending: true).limit(1).get(
              const GetOptions(source: Source.server),
            );
      }
    } catch (_) {}
    if (mounted) setState(() {});
    _refreshController.refreshCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: true,
        leading: BackButton(color: _textSecondary),
        title: Text(
          'Shop Reusables',
          style: TextStyle(color: _textSecondary, fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtl,
                    onChanged: (v) => setState(() => _searchTerm = v.trim()),
                    style: TextStyle(color: _textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search by item name...',
                      hintStyle: TextStyle(color: _textSecondary),
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      filled: true,
                      fillColor: const Color(0xFF1B2429),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _accent, width: 1.2),
                      ),
                      suffixIcon: _searchTerm.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70),
                              onPressed: () {
                                _searchCtl.clear();
                                setState(() => _searchTerm = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Available'),
                          selected: !_showMyPicks,
                          onSelected: (s) => setState(() => _showMyPicks = !s ? true : false),
                          labelStyle: TextStyle(
                            color: !_showMyPicks ? Colors.black : _textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          backgroundColor: const Color(0xFF1B2429),
                          selectedColor: _accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(color: _border),
                          ),
                        ),
                        ChoiceChip(
                          label: const Text('My Picks'),
                          selected: _showMyPicks,
                          onSelected: (s) => setState(() => _showMyPicks = s),
                          labelStyle: TextStyle(
                            color: _showMyPicks ? Colors.black : _textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          backgroundColor: const Color(0xFF1B2429),
                          selectedColor: _accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(color: _border),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _itemsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SmartRefresher(
                      controller: _refreshController,
                      onRefresh: _onRefresh,
                      header: const ClassicHeader(),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        itemBuilder: (_, __) => _SkeletonCard(panel: _panel, border: _border),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: 5,
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];
                  final filtered = _searchTerm.isEmpty
                      ? docs
                      : docs.where((d) {
                          final data = d.data() as Map<String, dynamic>;
                          final name = (data['itemName'] ?? '').toString().toLowerCase();
                          return name.contains(_searchTerm.toLowerCase());
                        }).toList();

                  if (_showMyPicks && FirebaseAuth.instance.currentUser == null) {
                    return SmartRefresher(
                      controller: _refreshController,
                      onRefresh: _onRefresh,
                      header: const ClassicHeader(),
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline, size: 48, color: _textSecondary),
                              const SizedBox(height: 10),
                              Text('Sign in to see your picks',
                                  style: TextStyle(color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('Your picked items will appear here.',
                                  style: TextStyle(color: _textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  if (filtered.isEmpty) {
                    return SmartRefresher(
                      controller: _refreshController,
                      onRefresh: _onRefresh,
                      header: const ClassicHeader(),
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off_outlined, size: 48, color: _textSecondary),
                              const SizedBox(height: 10),
                              Text('No results',
                                  style: TextStyle(
                                      color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('Try a different search term.', style: TextStyle(color: _textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    );
                  }

                  return SmartRefresher(
                    controller: _refreshController,
                    onRefresh: _onRefresh,
                    header: const ClassicHeader(),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final doc = filtered[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final id = doc.id;
                        final imageUrl = (data['imageUrl'] as String?) ?? '';
                        final name = (data['itemName'] as String?) ?? 'Unnamed';
                        final location = (data['location'] as String?) ?? 'Unknown location';
                        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                        final isPicked = (data['isPicked'] as bool?) ?? false;

                        return Container(
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _border),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {},
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Hero(
                                  tag: id,
                                  child: GestureDetector(
                                    onTap: () => _openImageFullScreen(id, imageUrl),
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(16),
                                        bottomLeft: Radius.circular(16),
                                      ),
                                      child: imageUrl.isEmpty
                                          ? Container(
                                              width: 110,
                                              height: 88,
                                              color: const Color(0xFF233038),
                                              child: const Icon(Icons.image_not_supported_outlined,
                                                  color: Colors.white54),
                                            )
                                          : Image.network(
                                              imageUrl,
                                              width: 110,
                                              height: 88,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                width: 110,
                                                height: 88,
                                                color: const Color(0xFF233038),
                                                child: const Icon(Icons.broken_image_outlined,
                                                    color: Colors.white54),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(8),
                                          onTap: () => _openMap(location),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.location_on_outlined,
                                                  size: 16, color: Colors.white70),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  location,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: _accent,
                                                    fontSize: 12.5,
                                                    decoration: TextDecoration.underline,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (createdAt != null) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.schedule_outlined,
                                                  size: 16, color: Colors.white70),
                                              const SizedBox(width: 4),
                                              Text(
                                                _timeAgo(createdAt),
                                                style: TextStyle(color: _textSecondary, fontSize: 12.5),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                                  child: _showMyPicks || isPicked
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2B3A3F),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: _border),
                                          ),
                                          child: Text('Picked',
                                              style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w600)),
                                        )
                                      : ElevatedButton(
                                          onPressed: _pickingId == id ? null : () => _pickItem(context, id),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _accent,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            disabledBackgroundColor: _accent.withOpacity(0.5),
                                          ),
                                          child: _pickingId == id
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                      strokeWidth: 2, color: Colors.white),
                                                )
                                              : const Text('Pick'),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _FullscreenImage extends StatelessWidget {
  final String heroTag;
  final String imageUrl;
  const _FullscreenImage({required this.heroTag, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: const BackButton(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            maxScale: 4,
            child: imageUrl.isEmpty
                ? const Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 80)
                : Image.network(imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final Color panel;
  final Color border;
  const _SkeletonCard({required this.panel, required this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 110,
            height: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF233038),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _shimmerBar(width: 140),
                  const SizedBox(height: 8),
                  _shimmerBar(width: 100),
                  const Spacer(),
                  _shimmerBar(width: 60),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _shimmerBar({double width = 120}) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2A30),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

// lib/pages/admin/admin_requests_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AdminRequestsPage extends StatefulWidget {
  const AdminRequestsPage({super.key});
  @override
  State<AdminRequestsPage> createState() => _AdminRequestsPageState();
}

class _AdminRequestsPageState extends State<AdminRequestsPage> {
  final _addedIds = <String>{};
  late final FirebaseMessaging _fm;

  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  String _status = 'all'; 

  // Theme
  static const bg = Color(0xFF12181B);
  static const panel = Color(0xFF182226);
  static const chipBg = Color(0xFF1C262B);
  static const border = Color(0xFF233038);
  static const textP = Color(0xFFF9FBFA);
  static const textS = Color(0xFFDDE5E4);
  static const hint = Color(0xFFA9B4B3);
  static const accent = Color(0xFF2FD885);

  @override
  void initState() {
    super.initState();
    _fm = FirebaseMessaging.instance;
    _fm.subscribeToTopic('bin_requests_admins');
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (!mounted) return;
      if (n != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${n.title ?? "New Bin Request"} • ${n.body ?? ""}'),
            action: SnackBarAction(label: 'OPEN', onPressed: _scrollToTop),
          ),
        );
      }
    });
  }

  void _scrollToTop() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  Stream<QuerySnapshot> _stream() {
    Query q = FirebaseFirestore.instance.collection('bin_requests');
    if (_status != 'all') {
      q = q.where('status', isEqualTo: _status);
    }
    q = q.orderBy('createdAt', descending: true);
    return q.snapshots(includeMetadataChanges: false);
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

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete request?'),
            content: const Text(
              'This will permanently remove the request.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // Delete Firestore doc + image in Firebase Storage (if any).
  Future<void> _deleteRequestCompletely(String id, Map<String, dynamic> data) async {
    final docRef = FirebaseFirestore.instance.collection('bin_requests').doc(id);

    // Delete image from Storage if imageUrl present.
    final imgUrl = (data['imageUrl'] ?? '') as String;
    if (imgUrl.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(imgUrl).delete();
      } catch (_) {
      }
    }

    await docRef.delete();
  }

  String? _parseStatusQuery(String q) {
    final s = q.toLowerCase().replaceAll('_', ' ').trim();
    if (s == 'pending' || s.endsWith(':pending')) return 'pending';
    if (s == 'in progress' || s == 'inprogress' || s.endsWith(':in progress') || s.endsWith(':in_progress') || s.endsWith(':inprogress')) {
      return 'in_progress';
    }
    if (s == 'done' || s.endsWith(':done')) return 'done';
    return null;
  }

  Widget _buildStatusChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _status == value,
      onSelected: (sel) {
        if (!sel) return;
        setState(() => _status = value);
      },
      labelStyle: TextStyle(
        color: _status == value ? Colors.black : textS,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: chipBg,
      selectedColor: accent,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(color: textS),
        title: const Text('Admin • Bin Requests', style: TextStyle(color: textP)),
        actions: [
          IconButton(
            tooltip: 'Scroll to top',
            onPressed: _scrollToTop,
            icon: const Icon(Icons.arrow_upward, color: textS),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                children: [
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: textP, fontSize: 14),
                      decoration: const InputDecoration(
                        icon: Icon(Icons.search, color: Colors.white70, size: 18),
                        hintText: 'Search email / type / location / status (e.g., status:done)',
                        hintStyle: TextStyle(color: hint, fontSize: 13),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _buildStatusChip('All', 'all'),
                        _buildStatusChip('Pending', 'pending'),
                        _buildStatusChip('In Progress', 'in_progress'),
                        _buildStatusChip('Done', 'done'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: border),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _stream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snap.hasData) {
                    for (final c in snap.data!.docChanges) {
                      if (c.type == DocumentChangeType.added) {
                        final id = c.doc.id;
                        if (!_addedIds.contains(id)) {
                          _addedIds.add(id);
                          final d = c.doc.data() as Map<String, dynamic>? ?? {};
                          final type = (d['requestType'] ?? 'Bin Request').toString();
                          final loc = (d['location'] ?? 'Unknown').toString();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('New: $type • $loc'),
                                action: SnackBarAction(label: 'OPEN', onPressed: _scrollToTop),
                              ),
                            );
                          });
                        }
                      }
                    }
                  }

                  var docs = snap.data?.docs ?? [];

                  final rawQ = _searchCtrl.text.trim();
                  final q = rawQ.toLowerCase();
                  final statusFromQuery = _parseStatusQuery(q);

                  if (q.isNotEmpty) {
                    docs = docs.where((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final email = (d['userEmail'] ?? '').toString().toLowerCase();
                      final type = (d['requestType'] ?? '').toString().toLowerCase();
                      final loc = (d['location'] ?? '').toString().toLowerCase();
                      final statusVal = (d['status'] ?? '').toString().toLowerCase();

                      final textMatch = email.contains(q) || type.contains(q) || loc.contains(q) || statusVal.contains(q);
                      final statusMatch = statusFromQuery == null || statusVal == statusFromQuery;

                      return textMatch && statusMatch;
                    }).toList();
                  }

                  if (docs.isEmpty) {
                    return const Center(child: Text('No requests found', style: TextStyle(color: textS)));
                  }

                  return ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      final d = doc.data() as Map<String, dynamic>;
                      final id = doc.id;
                      final img = (d['imageUrl'] ?? '') as String;
                      final type = (d['requestType'] ?? '') as String;
                      final loc = (d['location'] ?? 'Unknown') as String;
                      final email = (d['userEmail'] ?? '') as String;
                      final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
                      final status = (d['status'] ?? 'pending') as String;

                      return Container(
                        decoration: BoxDecoration(
                          color: panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (img.isEmpty) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _AdminImageFullscreen(tag: id, url: img),
                                  ),
                                );
                              },
                              child: Hero(
                                tag: id,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                  ),
                                  child: img.isEmpty
                                      ? Container(
                                          width: 110,
                                          height: 88,
                                          color: const Color(0xFF233038),
                                          child: const Icon(Icons.image_not_supported_outlined, color: Colors.white54),
                                        )
                                      : Image.network(img, width: 110, height: 88, fit: BoxFit.cover),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text(type, style: const TextStyle(color: textP, fontSize: 15, fontWeight: FontWeight.w700)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: status == 'done' 
                                              ? const Color.fromARGB(255, 93, 174, 0)
                                              : status == 'in_progress'
                                                  ? Colors.deepOrange
                                                  : const Color.fromARGB(255, 3, 26, 202),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: border),
                                        ),
                                      child: Text(
                                        status == 'done'
                                            ? 'Done'
                                            : status == 'in_progress'
                                                ? 'In Progress'
                                                : 'Pending',
                                        style: const TextStyle(color: textS, fontSize: 11),
                                      )
                                      ),
                                    ]),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.person_outline, size: 16, color: Colors.white70),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            email,
                                            style: const TextStyle(color: textS, fontSize: 12.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    InkWell(
                                      onTap: () => _openMap(loc),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.location_on_outlined, size: 16, color: Colors.white70),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              loc,
                                              style: const TextStyle(
                                                color: accent,
                                                fontSize: 12.5,
                                                decoration: TextDecoration.underline,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (createdAt != null) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.schedule_outlined, size: 16, color: Colors.white70),
                                          const SizedBox(width: 4),
                                          Text(_ago(createdAt), style: const TextStyle(color: textS, fontSize: 12.5)),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
                              child: PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'delete') {
                                    final ok = await _confirmDelete(context);
                                    if (!ok) return;
                                    try {
                                      await _deleteRequestCompletely(id, d);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Request and image deleted')),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Delete failed')),
                                        );
                                      }
                                    }
                                    return;
                                  }
                                  try {
                                    await FirebaseFirestore.instance.collection('bin_requests').doc(id).update({'status': v});
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marked $v')));
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Update failed')));
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'pending', child: Text('Pending')),
                                  PopupMenuItem(value: 'in_progress', child: Text('In Progress')),
                                  PopupMenuItem(value: 'done', child: Text('Done')),
                                  PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                                child: const Icon(Icons.more_vert, color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _AdminImageFullscreen extends StatelessWidget {
  final String tag;
  final String url;
  const _AdminImageFullscreen({required this.tag, required this.url});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, leading: const BackButton(color: Colors.white), elevation: 0),
      body: Center(
        child: Hero(tag: tag, child: InteractiveViewer(maxScale: 4, child: Image.network(url, fit: BoxFit.contain))),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PDFExport {

  static Future<File> generateUserDataPDF() async {
    
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final pdf = pw.Document();

      // Fetch user data with timeout
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 10));

      // Fetch scan history with pagination (1000 records at a time)
      final scans = await _fetchAllScans(user.uid);

      // Build PDF content
      pdf.addPage(
        pw.MultiPage(
          build: (context) => [
                pw.Header(level: 0, text: 'Recycle Tracker Data Export'),
                pw.SizedBox(height: 20),
                _buildUserInfo(user, userDoc),
                pw.SizedBox(height: 30),
                _buildStatistics(scans),
                pw.SizedBox(height: 30),
                _buildScanHistory(scans),
              ],
          footer: (context) => pw.Text(
                'Generated on ${DateFormat.yMMMMd().add_jm().format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 10),
              )),
      );

      // Save to file
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/recycle_data_export_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await pdf.save());
      
      return file;
    } on FirebaseException catch (e) {
      throw Exception('Firestore error: ${e.message}');
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      throw Exception('Failed to generate PDF: $e');
    }
  }

  static Future<List<QueryDocumentSnapshot>> _fetchAllScans(String userId) async {
    List<QueryDocumentSnapshot> allScans = [];
    QuerySnapshot? snapshot;
    const int batchSize = 1000;

    do {
      final query = FirebaseFirestore.instance
          .collection('scans')
          .where('userId', isEqualTo: userId)
          .limit(batchSize);

      if (snapshot != null && snapshot.docs.isNotEmpty) {
        query.startAfterDocument(snapshot.docs.last);
      }

      snapshot = await query.get();
      allScans.addAll(snapshot.docs);
    } while (snapshot.docs.length == batchSize);

    // Sort by timestamp descending
    allScans.sort((a, b) => (b['timestamp'] as Timestamp).compareTo(a['timestamp'] as Timestamp));
    
    return allScans;
  }

  static pw.Widget _buildUserInfo(User user, DocumentSnapshot userDoc) {
    final userData = userDoc.data() as Map<String, dynamic>? ?? {};
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Header(level: 1, text: 'User Information'),
        pw.Divider(),
        pw.Text('Email: ${user.email ?? 'Not available'}'),
        pw.Text('Account Created: ${user.metadata.creationTime?.toLocal().toString() ?? 'Unknown'}'),
        pw.Text('XP: ${userData['xp'] ?? 0}'),
        pw.Text('Daily Goal: ${userData['dailyGoal'] ?? 5}'),
        pw.Text('Current Streak: ${userData['streak'] ?? 0} days'),
      ],
    );
  }

  static pw.Widget _buildStatistics(List<QueryDocumentSnapshot> scans) {
    final recycled = scans.where((doc) => doc['recyclable'] == true).length;
    final nonRecycled = scans.length - recycled;
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Header(level: 1, text: 'Statistics'),
        pw.Divider(),
        pw.Text('Total Scanned Items: ${scans.length}', 
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text('Recyclable Items: $recycled'),
        pw.Text('Non-Recyclable Items: $nonRecycled'),
        pw.SizedBox(height: 10),
        pw.Text('CO₂ Prevented: ${(recycled * 0.07).toStringAsFixed(2)} lbs'),
      ],
    );
  }

  static pw.Widget _buildScanHistory(List<QueryDocumentSnapshot> scans) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Header(level: 1, text: 'Scan History (${scans.length} items)'),
        pw.Divider(),
        scans.isEmpty 
            ? pw.Text('No scan history available')
            : pw.Table.fromTextArray(
                headers: ['Date', 'Item', 'Recyclable', 'Confidence'],
                data: scans.take(1000).map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return [
                    DateFormat.yMd().add_jm().format((data['timestamp'] as Timestamp).toDate()),
                    data['itemName']?.toString() ?? 'Unknown',
                    data['recyclable'] == true ? 'Yes' : 'No',
                    '${((data['confidence'] ?? 0) * 100).toStringAsFixed(1)}%'
                  ];
                }).toList(),
              ),
      ],
    );
  }
}

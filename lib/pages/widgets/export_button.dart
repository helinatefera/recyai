import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// --- DATA CLASS (for organizing data) ---

class WeeklyReportData {
  final String userName;
  final int weeklyScanned;
  final int weeklyRecycled;
  final int weeklyNonRecycled;

  WeeklyReportData({
    required this.userName,
    required this.weeklyScanned,
    required this.weeklyRecycled,
    required this.weeklyNonRecycled,
  });
}


// --- PDF GENERATION SERVICE (all logic is here) ---

class WeeklyReportPdf {
  /// Generates and saves a weekly report PDF.
  static Future<File> generate(WeeklyReportData data) async {
    final pdf = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: pw.Font.ttf(await rootBundle.load("assets/fonts/NotoSans-Regular.ttf")),
    );
    
    // Load app icon from assets
    final appIcon = pw.MemoryImage(
      (await rootBundle.load('images/start_logo.png')).buffer.asUint8List(),
    );

    final greenColor = PdfColor.fromHex('#2FD885');
    final darkColor = PdfColor.fromHex('#1C1C1E');
    final lightTextColor = PdfColor.fromHex('#FFFFFF').flatten();

    // Get date range for the report title
    final now = DateTime.now();
    final weekEnd = now;
    final weekStart = now.subtract(const Duration(days: 6));
    final dateRange = "${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}, ${weekEnd.year}";

    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // --- HEADER ---
              _buildHeader(appIcon, dateRange, greenColor),
              pw.SizedBox(height: 30),

              // --- USER GREETING ---
              pw.Text('Weekly Summary for ${data.userName}', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),

              // --- STATS CARDS ---
              _buildStatsGrid(data, greenColor, darkColor),
              pw.SizedBox(height: 30),

              // --- BREAKDOWN SECTION ---
              pw.Text('Weekly Breakdown', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: lightTextColor)),
              pw.Divider(color: greenColor.shade(0.2), height: 15),
              _buildBreakdownChart(data, greenColor),

              pw.Spacer(),

              // --- FOOTER ---
              _buildFooter(),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/WeeklyReport.pdf");
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _buildHeader(pw.MemoryImage icon, String dateRange, PdfColor primaryColor) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            pw.Image(icon, width: 40, height: 40),
            pw.SizedBox(width: 10),
            pw.Text('RecyAI Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.Text(dateRange, style: pw.TextStyle(color: primaryColor, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _buildStatsGrid(WeeklyReportData data, PdfColor primaryColor, PdfColor darkColor) {
    return pw.GridView(
      crossAxisCount: 3,
      childAspectRatio: 1.8,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        _buildStatCard('Total Scanned', data.weeklyScanned.toString(), primaryColor, darkColor),
        _buildStatCard('Recycled Items', data.weeklyRecycled.toString(), primaryColor, darkColor),
        _buildStatCard('Other Items', data.weeklyNonRecycled.toString(), primaryColor, darkColor),
      ],
    );
  }

  static pw.Widget _buildStatCard(String title, String value, PdfColor primaryColor, PdfColor darkColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: darkColor,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: primaryColor.shade(0.5)),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(value, style: pw.TextStyle(color: primaryColor, fontSize: 28, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Text(title, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  static pw.Widget _buildBreakdownChart(WeeklyReportData data, PdfColor primaryColor) {
    final total = data.weeklyScanned;
    if (total == 0) return pw.Center(child: pw.Text("No items scanned this week.", style: const pw.TextStyle(color: PdfColors.grey)));

    final recycledPercent = (data.weeklyRecycled / total);
    final otherPercent = (data.weeklyNonRecycled / total);

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#1C1C1E'),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text("Recycled vs. Other", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 20),
          pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.LinearProgressIndicator(
              value: recycledPercent,
              backgroundColor: PdfColors.grey600,
              valueColor: primaryColor,
              minHeight: 20,
            ),
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Recycled: ${(recycledPercent * 100).toStringAsFixed(0)}% (${data.weeklyRecycled})'),
              pw.Text('Other: ${(otherPercent * 100).toStringAsFixed(0)}% (${data.weeklyNonRecycled})'),
            ],
          )
        ],
      ),
    );
  }

  static pw.Widget _buildFooter() {
    return pw.Center(
      child: pw.Text(
        'Report generated on ${DateTime.now().toLocal().toString().substring(0, 16)} by RecyAI',
        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey),
      ),
    );
  }
}

// --- FLUTTER WIDGET ---

class ExportButton extends StatelessWidget {
  const ExportButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF2FD885)),
      title: const Text('Export Weekly Report'),
      onTap: () => _exportAndDownloadData(context),
    );
  }

  /// Fetches weekly data and generates a themed PDF report.
  Future<void> _exportAndDownloadData(BuildContext context) async {
    // Show a themed loading dialog
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
            Text("Preparing your weekly report...", style: TextStyle(color: Colors.white.withOpacity(0.9))),
          ],
        ),
      ),
    );

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("You must be logged in to export data.");
      }

      // 1. Fetch data required for the weekly report
      final firestore = FirebaseFirestore.instance;
      final userSnap = await firestore.collection('users').doc(user.uid).get();
      final userName = userSnap.data()?['name'] ?? 'Eco Warrior';

      final now = DateTime.now();
      final weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      final scanSnap = await firestore
          .collection('scans')
          .where('userId', isEqualTo: user.uid)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .get();

      int weeklyRecycled = 0, weeklyNonRecycled = 0;
      for (final doc in scanSnap.docs) {
        if (doc.data().containsKey('recyclable') && doc['recyclable'] == true) {
          weeklyRecycled++;
        } else {
          weeklyNonRecycled++;
        }
      }

      final reportData = WeeklyReportData(
        userName: userName,
        weeklyScanned: scanSnap.size,
        weeklyRecycled: weeklyRecycled,
        weeklyNonRecycled: weeklyNonRecycled,
      );

      // 2. Generate the PDF using the service class defined in this file
      final pdfFile = await WeeklyReportPdf.generate(reportData);

      if (context.mounted) Navigator.pop(context); // Close loading dialog

      // 3. Show a themed success dialog
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF2C2C2E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text("Report Ready", style: TextStyle(color: Colors.white)),
            content: Text(
              "Your weekly report PDF has been saved. You can open it now or find it in your device's files.",
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
                  await OpenFile.open(pdfFile.path);
                },
                child: const Text("Open Report", style: TextStyle(color: Color(0xFF2FD885), fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    } catch (e, stack) {
      debugPrint("Export error: $e\n$stack");
      if (context.mounted) Navigator.pop(context); // Close loading dialog
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
}
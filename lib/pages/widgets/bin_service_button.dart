import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BinServiceButton extends StatefulWidget {
  const BinServiceButton({super.key});
  @override
  State<BinServiceButton> createState() => _BinServiceButtonState();
}

class _BinServiceButtonState extends State<BinServiceButton> {
  bool _sending = false;

  Future<File?> _compress(File original) async {
    final dir = await getTemporaryDirectory();
    final out = p.join(dir.path, "bin_${DateTime.now().millisecondsSinceEpoch}.jpg");
    final f = await FlutterImageCompress.compressAndGetFile(
      original.path,
      out,
      quality: 70,
      minWidth: 1600,
      minHeight: 1600,
      format: CompressFormat.jpeg,
      keepExif: true,
    );
    return f == null ? null : File(f.path);
  }

  Future<String?> _promptForLocation() async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        title: const Text(
          'Enter Location',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g., New York, Manhattan, Apartment 45B',
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2FD885)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF2FD885)),
            ),
          ),
          textInputAction: TextInputAction.done,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF2FD885))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2FD885),
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              final txt = controller.text.trim();
              if (txt.isEmpty) return;
              Navigator.pop(context, txt);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _createRequest(String serviceType) async {
    if (_sending) return;

    final locationText = await _promptForLocation();
    if (locationText == null) return;

    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      _toast('Camera permission is required');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast('Please sign in');
      return;
    }

    final picker = ImagePicker();
    final XFile? shot = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      maxWidth: 3000,
    );
    if (shot == null) return;

    try {
      setState(() => _sending = true);

      final original = File(shot.path);
      final toUpload = (await _compress(original)) ?? original;

      final path = 'bin_requests/${user.uid}_${DateTime.now().toIso8601String()}.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);
      await ref.putFile(toUpload, SettableMetadata(contentType: 'image/jpeg'));
      final imageUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('bin_requests').add({
        'userId': user.uid,
        'userEmail': user.email,
        'requestType': serviceType,
        'location': locationText,
        'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      _toast('Request submitted ✔️');
    } catch (e) {
      _toast('Submit failed');
      // ignore: avoid_print
      print("Error submitting bin request: $e");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2FD885),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Request Service',
                style: TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _sheetTile(
                icon: Icons.cleaning_services_outlined,
                title: 'Bin Clean',
                subtitle: 'Request cleaning for your bin',
                onTap: () {
                  Navigator.pop(context);
                  _createRequest('Bin Clean');
                },
              ),
              Divider(color: Colors.grey.shade700, height: 1),
              _sheetTile(
                icon: Icons.build_outlined,
                title: 'Bin Service',
                subtitle: 'Repair or replace your bin',
                onTap: () {
                  Navigator.pop(context);
                  _createRequest('Bin Service');
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF2FD885)),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Color.fromARGB(255, 255, 255, 255),
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white70),
      ),
      onTap: onTap,
    );
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF2FD885),
          behavior: SnackBarBehavior.floating,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _sending ? null : _openPicker,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Icon(Icons.delete_outline),
        label: Text(_sending ? 'Sending...' : 'My Bin'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2FD885),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          disabledBackgroundColor: const Color(0xFF2FD885).withOpacity(0.6),
        ),
      ),
    );
  }
}

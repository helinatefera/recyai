import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class BulkyItemForm extends StatefulWidget {
  const BulkyItemForm({super.key});

  @override
  _BulkyItemFormState createState() => _BulkyItemFormState();
}

class _BulkyItemFormState extends State<BulkyItemForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  File? _image;
  String? _location;
  bool _submitting = false;

  final Color _bg = const Color(0xFF12181B);
  final Color _panel = const Color(0xFF182226);
  final Color _border = const Color(0xFF233038);
  final Color _textPrimary = const Color(0xFFF9FBFA);
  final Color _textSecondary = const Color(0xFFDDE5E4);
  final Color _accent = const Color(0xFF2FD885);

  Future<String?> _promptForLocation() async {
    final controller = TextEditingController(text: _location ?? "");
    return showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enter Location', style: TextStyle(color: Colors.white)),
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
            child: const Text('Use Location'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    final ImagePicker picker = ImagePicker();
    final XFile? imageFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      maxWidth: 3000,
    );

    if (imageFile != null) {
      setState(() => _image = File(imageFile.path));
    }
  }

  Future<File?> _compressImage(File original) async {
    final dir = await getTemporaryDirectory();
    final targetPath = p.join(dir.path, "bulky_${DateTime.now().millisecondsSinceEpoch}.jpg");

    final result = await FlutterImageCompress.compressAndGetFile(
      original.path,
      targetPath,
      quality: 70,
      minWidth: 1600,
      minHeight: 1600,
      format: CompressFormat.jpeg,
      keepExif: true,
    );

    if (result == null) return null;
    return File(result.path);
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || _image == null || _location == null) {
      _showSnack("Please complete all fields.", isError: true);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack("You need to be signed in.", isError: true);
      return;
    }

    try {
      setState(() => _submitting = true);

      final File toUpload = (await _compressImage(_image!)) ?? _image!;

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('bulky_images/${user.uid}_${DateTime.now().toIso8601String()}.jpg');

      final snapshot = await storageRef.putFile(
        toUpload,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('bulky_items').add({
        'userId': user.uid,
        'itemName': _nameController.text.trim(),
        'location': _location, // existing field, now user-entered
        'imageUrl': imageUrl,
        'isPicked': false,
        'createdAt': Timestamp.now(),
      });

      setState(() => _submitting = false);
      await _showSuccessDialog();
    } catch (_) {
      setState(() => _submitting = false);
      _showSnack("Failed to post item. Try again.", isError: true);
    }
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Color(0xFF2FD885)),
            SizedBox(width: 8),
            Text("Item Posted", style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text("Your bulky item has been added successfully.",
            style: TextStyle(color: _textSecondary)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text("OK", style: TextStyle(color: Color(0xFF2FD885))),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF2FD885),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readyToSubmit =
        _formKey.currentState?.validate() == true && _image != null && _location != null;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: true,
        leading: BackButton(color: _textSecondary),
        title: const Text(
          'Schedule Bulky Pickup',
          style: TextStyle(
            color: Color(0xFFF9FBFA),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            Container(
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF233038),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.category_outlined, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Bulky Item Details",
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  )),
                              Text("Add a photo, name, and location",
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 12.5,
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(color: _textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Item Name',
                        labelStyle: TextStyle(color: _textSecondary),
                        hintText: 'e.g., Old Sofa',
                        hintStyle: TextStyle(color: _textSecondary.withOpacity(0.6)),
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
                        prefixIcon: const Icon(Icons.edit_outlined, color: Colors.white70),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Please enter item name' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Take Picture'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _textPrimary,
                              side: BorderSide(color: _border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_image != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: _border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.file(
                            _image!,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final val = await _promptForLocation();
                              if (val != null) setState(() => _location = val);
                            },
                            icon: const Icon(Icons.location_on_outlined),
                            label: const Text('Enter Location'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _textPrimary,
                              side: BorderSide(color: _border),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _location == null
                          ? Text("No location set",
                              style: TextStyle(color: _textSecondary, fontSize: 12.5))
                          : Chip(
                              backgroundColor: const Color(0xFF233038),
                              avatar: const Icon(Icons.place, size: 16, color: Colors.white),
                              label: Text(_location!,
                                  style: const TextStyle(color: Colors.white)),
                              shape: RoundedRectangleBorder(
                                side: BorderSide(color: _border),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: Text(_submitting ? "Submitting..." : "Submit"),
                        onPressed: _submitting ? null : _submitForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          disabledBackgroundColor: _accent.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

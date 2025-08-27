import 'dart:io';

import 'package:flutter/material.dart';

import 'package:animate_do/animate_do.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart'; 
import 'package:image_picker/image_picker.dart';


/// Screen for editing user profile information.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // --- Your state variables and logic functions remain unchanged ---
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  File? _newImage;
  String? _currentImageUrl;
  bool _loading = false;
  bool _changePassword = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists) {
      final data = doc.data()!;
      if (!mounted) return;
      setState(() {
        _nameController.text = data['name'] ?? '';
        _currentImageUrl = data['photoUrl'];
      });
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    try {
      final file = File(picked.path);
      final targetPath =
          '${file.parent.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 10,
        minWidth: 400,
        minHeight: 400,
      );

      if (!mounted) return;
      if (compressedFile != null) {
        setState(() => _newImage = File(compressedFile.path));
      } else {
        setState(() => _newImage = file);
      }
    } catch (e) {
      print("Image compression error: $e");
      if (!mounted) return;
      setState(() => _newImage = File(picked.path));
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    if (_changePassword &&
        _newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }

    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (user == null || uid == null) return;

    String photoUrl = _currentImageUrl ?? '';
    if (_newImage != null) {
      if (_currentImageUrl != null && _currentImageUrl!.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(_currentImageUrl!).delete();
        } catch (_) {}
      }
      final ref = FirebaseStorage.instance.ref().child(
        '/images/profile/$uid.jpg',
      );
      await ref.putFile(_newImage!);
      photoUrl = await ref.getDownloadURL();
    }

    try {
      String? finalPhotoUrl = _currentImageUrl;
      if (_newImage != null) {
        if (_currentImageUrl != null && _currentImageUrl!.isNotEmpty) {
          try {
            await FirebaseStorage.instance
                .refFromURL(_currentImageUrl!)
                .delete();
          } catch (e) {
            print("Failed to delete old image, continuing: $e");
          }
        }
        final storageRef = FirebaseStorage.instance.ref().child(
          'images/profile/${user.uid}.jpg',
        );
        await storageRef.putFile(_newImage!);
        finalPhotoUrl = await storageRef.getDownloadURL();
      }

      if (_changePassword) {
        final cred = EmailAuthProvider.credential(
          email: user.email!,
          password: _oldPasswordController.text.trim(),
        );
        await user.reauthenticateWithCredential(cred);
        await user.updatePassword(_newPasswordController.text.trim());
      }

      await user.updateDisplayName(_nameController.text.trim());
      if (finalPhotoUrl != null && finalPhotoUrl.isNotEmpty) {
        await user.updatePhotoURL(finalPhotoUrl);
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'name': _nameController.text.trim(), 'photoUrl': finalPhotoUrl ?? ''},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully!')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An unexpected error occurred: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          ClipPath(
            clipper: CurvedBottomClipper(),
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F9E84), Color(0xFF2FD885)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: Column(
              children: [
                AppBar(
                  title: Text(
                    'Edit Profile',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  foregroundColor: Colors.white,
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF2FD885),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  const SizedBox(height: 20),
                                  // --- Styled Profile Avatar ---
                                  FadeInDown(
                                    child: GestureDetector(
                                      onTap: _pickImage,
                                      child: Stack(
                                        children: [
                                          CircleAvatar(
                                            radius: 60,
                                            backgroundColor: const Color(
                                              0xFF2FD885,
                                            ),
                                            child: CircleAvatar(
                                              radius: 57,
                                              backgroundColor:
                                                  Colors.grey.shade800,
                                              backgroundImage: _newImage != null
                                                  ? FileImage(_newImage!)
                                                  : (_currentImageUrl != null &&
                                                                _currentImageUrl!
                                                                    .isNotEmpty
                                                            ? NetworkImage(
                                                                _currentImageUrl!,
                                                              )
                                                            : null)
                                                        as ImageProvider?,
                                              child:
                                                  _newImage == null &&
                                                      (_currentImageUrl ==
                                                              null ||
                                                          _currentImageUrl!
                                                              .isEmpty)
                                                  ? const Icon(
                                                      Icons.person,
                                                      size: 60,
                                                      color: Colors.white54,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            right: 4,
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF2FD885),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFF121212,
                                                  ),
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.edit,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  // --- Personal Information Section ---
                                  FadeInUp(
                                    child: _buildSection(
                                      title: 'Personal Information',
                                      child: _buildStyledTextFormField(
                                        controller: _nameController,
                                        label: 'Full Name',
                                        icon: Icons.person_outline,
                                        validator: (val) =>
                                            val == null || val.isEmpty
                                            ? 'Please enter your name'
                                            : null,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  // --- Security Section ---
                                  FadeInUp(
                                    delay: const Duration(milliseconds: 100),
                                    child: _buildSection(
                                      title: 'Security',
                                      child: Column(
                                        children: [
                                          Theme(
                                            data: Theme.of(context).copyWith(
                                              unselectedWidgetColor:
                                                  Colors.white70,
                                            ),
                                            child: CheckboxListTile(
                                              title: const Text(
                                                'Change Password',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              value: _changePassword,
                                              onChanged: (v) => setState(
                                                () => _changePassword = v!,
                                              ),
                                              activeColor: const Color(
                                                0xFF2FD885,
                                              ),
                                              controlAffinity:
                                                  ListTileControlAffinity
                                                      .leading,
                                              contentPadding: EdgeInsets.zero,
                                            ),
                                          ),
                                          if (_changePassword)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 12.0,
                                              ),
                                              child: Column(
                                                children: [
                                                  _buildStyledTextFormField(
                                                    controller:
                                                        _oldPasswordController,
                                                    label: 'Current Password',
                                                    icon: Icons
                                                        .lock_open_outlined,
                                                    isPassword: true,
                                                    validator: (val) =>
                                                        _changePassword &&
                                                            (val == null ||
                                                                val.isEmpty)
                                                        ? 'Enter current password'
                                                        : null,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  _buildStyledTextFormField(
                                                    controller:
                                                        _newPasswordController,
                                                    label: 'New Password',
                                                    icon: Icons.lock_outline,
                                                    isPassword: true,
                                                    validator: (val) =>
                                                        _changePassword &&
                                                            (val == null ||
                                                                val.length < 6)
                                                        ? 'Password must be at least 6 characters'
                                                        : null,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  _buildStyledTextFormField(
                                                    controller:
                                                        _confirmPasswordController,
                                                    label:
                                                        'Confirm New Password',
                                                    icon: Icons.lock_outline,
                                                    isPassword: true,
                                                    validator: (val) =>
                                                        _changePassword &&
                                                            val !=
                                                                _newPasswordController
                                                                    .text
                                                        ? 'Passwords do not match'
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                  // --- Save Button ---
                                  FadeInUp(
                                    delay: const Duration(milliseconds: 200),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: _saveChanges,
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                        ),
                                        label: const Text('Save Changes'),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          backgroundColor: const Color(
                                            0xFF2FD885,
                                          ),
                                          foregroundColor: Colors.black,
                                          textStyle: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 32),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // [NEW HELPER WIDGET] - A reusable widget for creating styled sections.
  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            color: Colors.white.withOpacity(0.8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: child,
        ),
      ],
    );
  }

  // [NEW HELPER WIDGET] - A reusable widget for creating styled text fields.
  Widget _buildStyledTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    bool isPassword = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        prefixIcon: Icon(icon, color: const Color(0xFF2FD885)),
        filled: true,
        fillColor: Colors.black.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2FD885), width: 2),
        ),
      ),
      validator: validator,
    );
  }
}

// This class remains unchanged.
class CurvedBottomClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 30);
    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - 30,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

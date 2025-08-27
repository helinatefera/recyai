// register_page_location_later.dart
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:animate_do/animate_do.dart';

class RegisterPage extends StatefulWidget {
  final VoidCallback onSignInTap;

  const RegisterPage({super.key, required this.onSignInTap});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  File? _profileImage;
  String? _locationText = "Location not granted";
  bool _loading = false;
  Position? _userPosition;

  @override
  void initState() {
    super.initState();
    _tryPrefetchLocationSilently();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _tryPrefetchLocationSilently() async {
    try {
      if (!mounted) return;
      final services = await Geolocator.isLocationServiceEnabled();
      if (!services) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return; // do not request here; we only auto-fill later if user grants
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _userPosition = pos;
        _locationText = "${pos.latitude}, ${pos.longitude}";
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _requestLocationAndUpdateIfGranted() async {
    try {
      if (!mounted) return;
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return; 
      }

      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _userPosition = pos;
        _locationText = "${pos.latitude}, ${pos.longitude}";
      });

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'location': GeoPoint(pos.latitude, pos.longitude),
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
    
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
      setState(() {
        _profileImage = File(((compressedFile as File?)?.path ?? file.path));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _profileImage = File(picked.path));
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_profileImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a profile image")),
      );
      return;
    }
    if (mounted) setState(() => _loading = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final uid = userCredential.user!.uid;

      String imageUrl = '';
      try {
        final ref = FirebaseStorage.instance
            .ref()
            .child('images/profile')
            .child('$uid.jpg');
        await ref.putFile(
          _profileImage!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        imageUrl = await ref.getDownloadURL();
      } catch (_) {}

      // Create user WITHOUT location if not granted yet.
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': _nameController.text.trim(),
        'email': userCredential.user!.email,
        'photoUrl': imageUrl.isEmpty ? null : imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Attempt to fill location immediately if already available/granted.
      await _requestLocationAndUpdateIfGranted();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Registration successful")));

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const Scaffold(
            body: Center(child: Text("Home Page")),
          ),
        ),
        (Route<dynamic> route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('images/auth.jpg', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.6)),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.transparent),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    FadeInDown(
                      duration: const Duration(milliseconds: 800),
                      child: Column(
                        children: [
                          Image.asset('images/logono.png', height: 100),
                          const SizedBox(height: 12),
                          const Text(
                            "Recy.AI",
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF31CF94),
                              letterSpacing: 1.2,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 10,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Create your account",
                            style: TextStyle(fontSize: 16, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    FadeInUp(
                      duration: const Duration(milliseconds: 1000),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: _pickImage,
                                  child: Stack(
                                    alignment: Alignment.bottomCenter,
                                    children: [
                                      CircleAvatar(
                                        radius: 50,
                                        backgroundColor: Colors.white.withOpacity(0.2),
                                        backgroundImage: _profileImage != null
                                            ? FileImage(_profileImage!)
                                            : null,
                                        child: _profileImage == null
                                            ? const Icon(Icons.camera_alt, size: 32, color: Colors.white70)
                                            : null,
                                      ),
                                      Positioned(
                                        bottom: 12,
                                        right: 12,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withOpacity(0.3),
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          child: const Icon(Icons.edit, color: Colors.white, size: 16),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _nameController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _inputDecoration(
                                    label: "Full Name",
                                    icon: Icons.person_outline,
                                  ),
                                  validator: (val) =>
                                      val == null || val.isEmpty ? "Enter name" : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _emailController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _inputDecoration(
                                    label: "Email",
                                    icon: Icons.email_outlined,
                                  ),
                                  validator: (val) {
                                    if (val == null || val.isEmpty) return "Enter email";
                                    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                    if (!regex.hasMatch(val)) return "Enter a valid email";
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _inputDecoration(
                                    label: "Password",
                                    icon: Icons.lock_outline,
                                  ),
                                  validator: (val) =>
                                      val == null || val.length < 6 ? "Min 6 chars" : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  obscureText: true,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _inputDecoration(
                                    label: "Confirm Password",
                                    icon: Icons.lock_outline,
                                  ),
                                  validator: (val) =>
                                      val != _passwordController.text ? "Passwords do not match" : null,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_outlined, color: Colors.white70),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _locationText ?? "",
                                        style: const TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: _requestLocationAndUpdateIfGranted,
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Colors.white24),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text("Add location"),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                _loading
                                    ? const CircularProgressIndicator(color: Colors.white)
                                    : SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          onPressed: _register,
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(vertical: 14),
                                            backgroundColor: Colors.white.withOpacity(0.25),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            elevation: 0,
                                          ),
                                          icon: const Icon(Icons.person_add, color: Colors.white),
                                          label: const Text(
                                            "Register",
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: widget.onSignInTap,
                                  child: const Text(
                                    "Already have an account? Sign in",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({required String label, required IconData icon}) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.white70),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

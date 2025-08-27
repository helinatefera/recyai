import 'package:flutter/material.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'pages/screen/brand.dart';
import 'pages/screen/challenge.dart';
import 'pages/screen/login.dart';
import 'pages/screen/scan.dart';
import 'pages/screen/setting.dart';
import 'pages/screen/signup.dart';
import 'pages/screen/track_screen.dart';
import 'pages/services/notification_service.dart';
import 'pages/widgets/navigation.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';
import 'pages/admin/admin_requests_page.dart';


final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

Future<void> initializeApp() async {
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    name: 'Recy.ai',
    options: DefaultFirebaseOptions.currentPlatform,
  );
  NotificationService.configureNavigation(navKey); 
  await NotificationService.init();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeApp();
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
    appleProvider: AppleProvider.deviceCheck,
  );
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  final Future<void> Function()? onAppReady;
  const MyApp({super.key, this.onAppReady});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.onAppReady != null) {
        await widget.onAppReady!();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recy.AI',
      theme: ThemeData(primarySwatch: Colors.green),
      routes: {
        '/admin/requests': (_) => const AdminRequestsPage(), // <-- add
      },
      home: FutureBuilder(
        future: initializeApp(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const EcoSplash();
          } else if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text('Error initializing app: ${snapshot.error}'),
              ),
            );
          } else {
            return StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const EcoSplash();
                }
                if (snapshot.hasData) {
                  return const HomeScreen();
                }
                return snapshot.hasData ? const HomeScreen() : const AuthSwitcher();
              },
            );
          }
        },
      ),
    );
  }
}

class EcoSplash extends StatelessWidget {
  const EcoSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('images/logo.png', height: 100),
            const SizedBox(height: 12),
            const Text(
              "Recy.AI",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0E607C),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2; // Start with Scan screen as default

  // Screens corresponding to each navigation item
  final List<Widget> _screens = [
    const BrandsScreen(),
    const TrackScreen(),
    const Scan(),
    const ChallengesScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: _screens[_currentIndex],
      bottomNavigationBar: Navigation(
        currentIndex: _currentIndex,
        onItemTapped: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}

class AuthSwitcher extends StatefulWidget {
  const AuthSwitcher({super.key});

  @override
  State<AuthSwitcher> createState() => _AuthSwitcherState();
}

class _AuthSwitcherState extends State<AuthSwitcher> {
  bool showLogin = true;

  void toggle() => setState(() => showLogin = !showLogin);

  @override
  Widget build(BuildContext context) {
    return showLogin
        ? LoginPage(onRegisterTap: toggle)
        : RegisterPage(onSignInTap: toggle);
  }
}

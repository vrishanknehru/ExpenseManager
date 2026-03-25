import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:expense_manager/screens/login_page.dart';
import 'package:expense_manager/screens/employee/employee_home.dart';
import 'package:expense_manager/screens/admin/admin_dashboard.dart';
import 'package:expense_manager/theme/app_theme.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Skip Hive and Supabase for now - test basic app load
  GoogleFonts.config.allowRuntimeFetching = true;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  Widget? _home;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
    _listenConnectivity();
  }

  void _listenConnectivity() {
    Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted && offline != _isOffline) {
        setState(() => _isOffline = offline);
      }
    });
  }

  Future<void> _checkAuth() async {
    final session = Supabase.instance.client.auth.currentSession;
    final box = Hive.box('userBox');

    if (session != null) {
      // Active auth session — use cached profile data
      final savedUserId = box.get('userId') as String?;
      final savedEmail = box.get('email') as String?;
      final savedRole = box.get('role') as String?;
      final savedUsername = box.get('username') as String?;

      if (savedUserId != null && savedEmail != null && savedRole != null) {
        if (savedRole == 'admin') {
          _home = AdminDashboard(
              userId: savedUserId,
              email: savedEmail,
              username: savedUsername);
        } else {
          _home = EmployeeHome(
              userId: savedUserId,
              email: savedEmail,
              username: savedUsername);
        }
      } else {
        // Auth session exists but no cached profile — re-fetch
        try {
          final email = session.user.email!;
          final profile = await Supabase.instance.client
              .from('users')
              .select('id, role, username')
              .eq('email', email)
              .maybeSingle();

          if (profile != null) {
            final userId = profile['id'] as String;
            final role = profile['role']?.toString().toLowerCase();
            final username = profile['username'] as String?;

            await box.put('userId', userId);
            await box.put('email', email);
            await box.put('role', role);
            await box.put('username', username);

            if (role == 'admin') {
              _home = AdminDashboard(
                  userId: userId, email: email, username: username);
            } else {
              _home = EmployeeHome(
                  userId: userId, email: email, username: username);
            }
          }
        } catch (e) {
          print('AUTH_GATE: Failed to fetch profile: $e');
        }
      }
    } else {
      // No auth session — clear stale Hive data
      await box.clear();
    }

    if (mounted) {
      setState(() {
        _home ??= const LoginScreen();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      children: [
        _home!,
        if (_isOffline)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              child: Container(
                color: AppColors.rejected,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4,
                  bottom: 8,
                ),
                child: Center(
                  child: Text(
                    'You are offline',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

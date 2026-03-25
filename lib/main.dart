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
  print('===== MAIN START =====');

  try {
    print('MAIN: Initializing Flutter widgets...');
    WidgetsFlutterBinding.ensureInitialized();
    print('MAIN: Flutter initialized ✓');

    print('MAIN: Setting screen orientation...');
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    print('MAIN: Screen orientation set ✓');

    print('MAIN: Loading .env file...');
    try {
      await dotenv.load();
      print('MAIN: .env loaded ✓');
    } catch (e) {
      print('MAIN: .env load failed (expected on web): $e');
    }

    print('MAIN: Initializing Hive...');
    await Hive.initFlutter();
    print('MAIN: Hive init ✓');

    print('MAIN: Opening userBox...');
    await Hive.openBox('userBox');
    print('MAIN: userBox opened ✓');

    print('MAIN: Reading Supabase credentials...');
    final supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: dotenv.env['SUPABASE_URL'] ?? '');
    final supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: dotenv.env['SUPABASE_ANON_KEY'] ?? '');

    print('MAIN: SUPABASE_URL present: ${supabaseUrl.isNotEmpty}');
    print('MAIN: SUPABASE_ANON_KEY present: ${supabaseKey.isNotEmpty}');

    if (supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty) {
      print('MAIN: Initializing Supabase...');
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseKey,
      );
      print('MAIN: Supabase initialized ✓');
    } else {
      print('MAIN: WARNING - Supabase credentials missing, skipping init');
    }

    print('MAIN: Setting up GoogleFonts...');
    GoogleFonts.config.allowRuntimeFetching = true;
    print('MAIN: GoogleFonts configured ✓');

    print('MAIN: Running app...');
    runApp(const MyApp());
    print('MAIN: App running ✓');
  } catch (e, st) {
    print('===== MAIN ERROR =====');
    print('ERROR: $e');
    print('STACK: $st');
    print('===== MAIN ERROR END =====');
    rethrow;
  }
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
    print('AUTHGATE: initState called');
    super.initState();
    _checkAuth();
    _listenConnectivity();
  }

  void _listenConnectivity() {
    print('AUTHGATE: Setting up connectivity listener...');
    Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (mounted && offline != _isOffline) {
        setState(() => _isOffline = offline);
      }
    });
  }

  Future<void> _checkAuth() async {
    print('AUTHGATE: Checking authentication...');
    try {
      print('AUTHGATE: Getting Supabase session...');
      final session = Supabase.instance.client.auth.currentSession;
      print('AUTHGATE: Session obtained: ${session != null}');

      print('AUTHGATE: Getting Hive box...');
      final box = Hive.box('userBox');
      print('AUTHGATE: Hive box obtained ✓');

      if (session != null) {
        print('AUTHGATE: User logged in');
        // Active auth session — use cached profile data
        final savedUserId = box.get('userId') as String?;
        final savedEmail = box.get('email') as String?;
        final savedRole = box.get('role') as String?;
        final savedUsername = box.get('username') as String?;

        if (savedUserId != null && savedEmail != null && savedRole != null) {
          print('AUTHGATE: Using cached profile: $savedRole');
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
          print('AUTHGATE: No cached profile, fetching from server...');
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

              print('AUTHGATE: Profile cached: $role');
              if (role == 'admin') {
                _home = AdminDashboard(
                    userId: userId, email: email, username: username);
              } else {
                _home = EmployeeHome(
                    userId: userId, email: email, username: username);
              }
            }
          } catch (e) {
            print('AUTHGATE: Failed to fetch profile: $e');
          }
        }
      } else {
        print('AUTHGATE: No session - clearing cache and showing login');
        // No auth session — clear stale Hive data
        await box.clear();
      }

      if (mounted) {
        setState(() {
          _home ??= const LoginScreen();
          _isLoading = false;
        });
        print('AUTHGATE: UI updated ✓');
      }
    } catch (e, st) {
      print('AUTHGATE: ERROR in _checkAuth');
      print('ERROR: $e');
      print('STACK: $st');
      if (mounted) {
        setState(() {
          _home = const LoginScreen();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('AUTHGATE: build() - isLoading: $_isLoading');

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
              color: Colors.red,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: const Text(
                  '⚠️ Offline',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

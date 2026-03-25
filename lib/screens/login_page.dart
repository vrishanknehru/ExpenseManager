import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_manager/theme/app_theme.dart';
import 'employee/employee_home.dart';
import 'admin/admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _obscurePassword = true;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  String errorMessage = '';

  final supabase = Supabase.instance.client;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _animController.forward();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Please enter both email and password.';
        isLoading = false;
      });
      return;
    }

    try {
      // Authenticate with Supabase Auth
      final authResponse = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (authResponse.user == null) {
        setState(() {
          errorMessage = 'Invalid login credentials';
        });
        return;
      }

      print('LOGIN_DEBUG: Auth successful for ${authResponse.user!.email}');

      // Look up role and profile from users table
      final userProfile = await supabase
          .from('users')
          .select('id, role, username')
          .eq('email', email)
          .maybeSingle();

      if (userProfile == null) {
        setState(() {
          errorMessage = 'User profile not found. Contact your administrator.';
        });
        return;
      }

      final userId = userProfile['id'] as String;
      final role = userProfile['role']?.toString().toLowerCase();
      final username = userProfile['username'] as String?;

      print('LOGIN_DEBUG: User profile found - role: $role, username: $username');

      // Cache user data in Hive for quick access
      final box = Hive.box('userBox');
      await box.put('userId', userId);
      await box.put('email', email);
      await box.put('role', role);
      await box.put('username', username);

      _handleNavigation(role, userId, email, username);
    } on AuthException catch (e) {
      print('LOGIN_DEBUG: AuthException: ${e.message}');
      setState(() {
        errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Login failed. Please try again.';
      });
      print('LOGIN_DEBUG: Sign-in caught exception: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _handleNavigation(
    String? role,
    String userId,
    String email,
    String? username,
  ) {
    if (role == 'admin') {
      Navigator.pushReplacement(
        context,
        AppPageRoute(
          page: AdminDashboard(
              userId: userId, email: email, username: username),
        ),
      );
    } else if (role == 'employee') {
      Navigator.pushReplacement(
        context,
        AppPageRoute(
          page: EmployeeHome(
              userId: userId, email: email, username: username),
        ),
      );
    } else {
      setState(() {
        errorMessage = 'Unknown user role. Please contact support.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 48),
                  // App icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Expense Manager',
                    style: GoogleFonts.poppins(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Track, submit and manage\nyour reimbursements',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      color: AppColors.textHint,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('Email'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'you@company.com',
                            prefixIcon: Icon(Icons.mail_outline_rounded,
                                size: 18, color: AppColors.textHint),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildLabel('Password'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded,
                                size: 18, color: AppColors.textHint),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 18,
                                color: AppColors.textHint,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Forgot password? Contact IT',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                        if (errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.rejectedBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 16, color: AppColors.rejected),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    errorMessage,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.rejected,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _signIn,
                            child: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text('Sign In',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    )),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/screens/login_page.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

class ProfilePage extends StatelessWidget {
  final String userId;
  final String email;
  final String? username;

  const ProfilePage({
    super.key,
    required this.userId,
    required this.email,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = username ?? email;
    final initials = displayName.substring(0, 1).toUpperCase();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(
              child: Text(
                initials,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.processingBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Employee',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.processing,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  icon: Icons.badge_outlined,
                  label: 'Employee ID',
                  value: userId.length >= 8 ? userId.substring(0, 8) : userId,
                ),
                const Divider(height: 1),
                _buildInfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email,
                ),
                const Divider(height: 1),
                _buildInfoRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Username',
                  value: username ?? 'Not set',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                'Sign Out',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.rejected,
                side: const BorderSide(color: AppColors.rejected, width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Expense Manager v1.0.0',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textHint),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    await Hive.box('userBox').clear();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }
}

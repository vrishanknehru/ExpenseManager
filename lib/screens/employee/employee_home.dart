import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:expense_manager/screens/employee/take_img.dart';
import 'package:expense_manager/screens/employee/history_page.dart';
import 'package:expense_manager/screens/employee/profile_page.dart';
import 'package:expense_manager/theme/app_theme.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_manager/screens/login_page.dart';
import 'package:expense_manager/screens/employee/bill_viewer_page.dart';
import 'package:intl/intl.dart';

class EmployeeHome extends StatefulWidget {
  final String userId;
  final String email;
  final String? username;

  const EmployeeHome({
    super.key,
    required this.userId,
    required this.email,
    this.username,
  });

  @override
  State<EmployeeHome> createState() => _EmployeeHomeState();
}

class _EmployeeHomeState extends State<EmployeeHome> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> userBills = [];
  bool isLoading = true;
  int _currentNavIndex = 0;
  final Set<String> _dismissedRejections = {};

  @override
  void initState() {
    super.initState();
    print(
      'EMPLOYEE_HOME_DEBUG: Initial userId received: "${widget.userId}" (length: ${widget.userId.length})',
    );
    print('EMPLOYEE_HOME_DEBUG: Username received: "${widget.username}"');
    _checkUserAndFetchBills();
  }

  Future<void> _checkUserAndFetchBills() async {
    setState(() {
      isLoading = true;
    });

    try {
      if (widget.userId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Invalid user ID received. Please log in again."),
            ),
          );
          _navigateToLogin();
        }
        return;
      }

      final userResponse = await supabase
          .from('users')
          .select('id, role, username')
          .eq('id', widget.userId)
          .eq('email', widget.email)
          .maybeSingle();

      if (userResponse == null ||
          userResponse['role']?.toString().toLowerCase() != 'employee') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Authentication/Role invalid. Please log in again.",
              ),
            ),
          );
          _navigateToLogin();
        }
        return;
      }

      final userId = userResponse['id'] as String;

      final billsResponse = await supabase
          .from('bills')
          .select(
            'id, purpose, source, amount, date, invoice_no, description, status, created_at, image_url, generated_pdf_url, admin_notes',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(5);

      setState(() {
        userBills = List<Map<String, dynamic>>.from(billsResponse);
        isLoading = false;
      });
    } catch (e) {
      print("Error in EmployeeHome: $e");
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load data: ${e.toString()}")),
        );
      }
    }
  }

  void _navigateToLogin() async {
    await supabase.auth.signOut();
    await Hive.box('userBox').clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  int get _pendingCount => userBills
      .where((b) => b['status']?.toString().toLowerCase() == 'pending')
      .length;
  int get _approvedCount => userBills
      .where((b) => b['status']?.toString().toLowerCase() == 'approved')
      .length;
  int get _rejectedCount => userBills
      .where((b) => b['status']?.toString().toLowerCase() == 'rejected')
      .length;
  int get _undismissedRejectedCount => userBills
      .where((b) {
        final status = b['status']?.toString().toLowerCase();
        final id = '${b['id']}';
        return status == 'rejected' && !_dismissedRejections.contains(id);
      })
      .length;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _buildBody(),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          onTap: (index) {
            setState(() => _currentNavIndex = index);
            if (index == 0) {
              _checkUserAndFetchBills();
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_rounded),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
      floatingActionButton: _currentNavIndex == 0
          ? FloatingActionButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  AppPageRoute(
                    page: TakeImagePage(
                        userId: widget.userId, userEmail: widget.email),
                  ),
                );
                _checkUserAndFetchBills();
              },
              child: const Icon(Icons.add_rounded, size: 28),
            )
          : null,
    );
  }

  Widget _buildBody() {
    switch (_currentNavIndex) {
      case 1:
        return HistoryPage(
          userId: widget.userId,
          email: widget.email,
          username: widget.username,
          embedded: true,
        );
      case 2:
        return ProfilePage(
          userId: widget.userId,
          email: widget.email,
          username: widget.username,
        );
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    if (isLoading) return _buildLoadingState();

    return RefreshIndicator(
      onRefresh: _checkUserAndFetchBills,
      color: AppColors.textPrimary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildStats()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Bills',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (userBills.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() => _currentNavIndex = 1);
                      },
                      child: Text(
                        'See All',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_undismissedRejectedCount > 0)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                padding: const EdgeInsets.only(left: 14, top: 4, bottom: 4, right: 4),
                decoration: BoxDecoration(
                  color: AppColors.rejectedBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$_undismissedRejectedCount rejected bill${_undismissedRejectedCount > 1 ? 's' : ''} need${_undismissedRejectedCount == 1 ? 's' : ''} attention',
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.rejected,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.rejected),
                      onPressed: () {
                        setState(() {
                          for (final bill in userBills) {
                            if (bill['status']?.toString().toLowerCase() == 'rejected') {
                              _dismissedRejections.add('${bill['id']}');
                            }
                          }
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ),
            ),
          if (userBills.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildBillCard(userBills[index]),
                    );
                  },
                  childCount: userBills.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                (widget.username ?? widget.email)
                    .substring(0, 1)
                    .toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: AppColors.textHint,
                  ),
                ),
                Text(
                  widget.username ?? widget.email,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _checkUserAndFetchBills,
            child: const Icon(Icons.refresh_rounded,
                color: AppColors.textHint, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _buildStatItem('Total', userBills.length, AppColors.textPrimary),
          _buildStatItem('Pending', _pendingCount, AppColors.pending),
          _buildStatItem('Approved', _approvedCount, AppColors.approved),
          _buildStatItem('Rejected', _rejectedCount, AppColors.rejected),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: AppColors.textHint,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillCard(Map<String, dynamic> entry) {
    final bool isRejected =
        entry['status']?.toString().toLowerCase() == 'rejected';
    final String adminNotes = entry['admin_notes']?.toString() ?? '';
    final String status = entry['status']?.toString() ?? 'pending';

    String formattedBillDate = 'N/A';
    if (entry['date'] != null) {
      try {
        final DateTime parsedBillDate = DateTime.parse(entry['date']);
        formattedBillDate = DateFormat('MMM dd, yyyy').format(parsedBillDate);
      } catch (e) {
        print("Error parsing bill date for display: $e");
        formattedBillDate = entry['date'].toString().split('T')[0];
      }
    }

    return ScaleTap(
      onTap: () {
        final billUrl = entry['image_url'];
        if (billUrl != null) {
          Navigator.push(
            context,
            AppPageRoute(page: BillViewerPage(billData: entry)),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("No bill image/PDF found for this entry.")),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRejected
                ? AppColors.rejected.withAlpha(60)
                : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        '\u20B9',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry['purpose'] ?? 'N/A',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$formattedBillDate  \u00B7  ${entry['source'] ?? 'N/A'}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\u20B9${(entry['amount'] as num?)?.toStringAsFixed(2) ?? 'N/A'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      StatusChip(status: status),
                    ],
                  ),
                ],
              ),
            ),
            if (isRejected && adminNotes.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                decoration: const BoxDecoration(
                  color: AppColors.rejectedBg,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  adminNotes,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.rejected,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.receipt_long_rounded,
                size: 32, color: AppColors.textHint),
          ),
          const SizedBox(height: 16),
          Text(
            'No bills yet',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to submit your first expense',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              ShimmerBlock(width: 40, height: 40, borderRadius: 12),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBlock(width: 80, height: 12, borderRadius: 6),
                  const SizedBox(height: 8),
                  ShimmerBlock(width: 140, height: 18, borderRadius: 6),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          ShimmerBlock(width: double.infinity, height: 72, borderRadius: 12),
          const SizedBox(height: 28),
          ...List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ShimmerBlock(
                  width: double.infinity, height: 68, borderRadius: 12),
            ),
          ),
        ],
      ),
    );
  }
}

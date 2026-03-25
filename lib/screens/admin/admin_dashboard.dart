import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_application_1/screens/login_page.dart';
import 'package:flutter_application_1/screens/employee/bill_viewer_page.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:intl/intl.dart';

class AdminDashboard extends StatefulWidget {
  final String userId;
  final String email;
  final String? username;

  const AdminDashboard({
    super.key,
    required this.userId,
    required this.email,
    this.username,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> allBills = [];
  bool isLoading = true;
  String? errorMessage;
  String _filterStatus = 'all';
  String _searchQuery = '';
  bool _showAnalytics = false;

  // Pagination
  static const int _pageSize = 20;
  int _displayCount = _pageSize;

  Map<String, String> userNames = {};
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkAdminRoleAndFetchBills();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminRoleAndFetchBills() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final userResponse = await supabase
          .from('users')
          .select('role')
          .eq('id', widget.userId)
          .eq('email', widget.email)
          .maybeSingle();

      if (userResponse == null ||
          userResponse['role']?.toString().toLowerCase() != 'admin') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Access Denied: You are not an admin."),
            ),
          );
          _navigateToLogin();
        }
        return;
      }

      final usersData = await supabase.from('users').select('id, username');
      userNames = {
        for (var user in usersData)
          user['id'] as String: user['username'] as String,
      };

      final billsResponse = await supabase
          .from('bills')
          .select(
            'id, user_id, purpose, amount, date, status, image_url, generated_pdf_url, source, invoice_no, description, created_at, admin_notes',
          )
          .order('date', ascending: false);

      setState(() {
        allBills = List<Map<String, dynamic>>.from(billsResponse);
        isLoading = false;
        _displayCount = _pageSize;
      });
    } catch (e) {
      print("Error fetching bills for admin: $e");
      setState(() {
        errorMessage = 'Failed to load bills: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  Future<void> _updateBillStatusWithRemarks(
    String billId,
    String newStatus,
  ) async {
    final TextEditingController remarksController = TextEditingController();
    final bool isRejection = newStatus == 'rejected';
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            isRejection ? 'Reject Bill' : 'Approve Bill',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isRejection
                      ? 'Please provide a reason for rejection.'
                      : 'Add optional remarks for this approval.',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: remarksController,
                  decoration: InputDecoration(
                    hintText: isRejection
                        ? "Reason for rejection (required)"
                        : "Optional remarks",
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Cancel',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textSecondary)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isRejection ? AppColors.rejected : AppColors.approved,
              ),
              child: Text(isRejection ? 'Reject' : 'Approve'),
              onPressed: () async {
                if (isRejection && remarksController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Please provide a reason for rejection.')),
                  );
                  return;
                }
                Navigator.of(context).pop();
                await _performStatusUpdate(
                    billId, newStatus, remarksController.text);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _performStatusUpdate(
    String billId,
    String newStatus,
    String remarks,
  ) async {
    setState(() {
      isLoading = true;
    });
    try {
      // Audit trail: record who approved/rejected and when
      await supabase.from('bills').update({
        'status': newStatus,
        'admin_notes': remarks,
        'approved_by': widget.userId,
        'status_updated_at': DateTime.now().toIso8601String(),
      }).eq('id', billId);

      // If approved, call the send-approval-email edge function via HTTP
      if (newStatus == 'approved') {
        try {
          final updatedBill = await supabase
              .from('bills')
              .select()
              .eq('id', billId)
              .single();

          final supabaseUrl = dotenv.env['SUPABASE_URL']!;
          final supabaseKey = dotenv.env['SUPABASE_ANON_KEY']!;

          final emailResponse = await http.post(
            Uri.parse('$supabaseUrl/functions/v1/send-approval-email'),
            headers: {
              'Authorization': 'Bearer $supabaseKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'record': updatedBill}),
          );

          print(
              'DEBUG: Email function response: ${emailResponse.statusCode} - ${emailResponse.body}');

          if (emailResponse.statusCode != 200) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Bill approved, but email notification failed.')),
              );
            }
          }
        } catch (emailError) {
          print('DEBUG: Failed to send approval email: $emailError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Bill approved, but email notification failed.')),
            );
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bill $newStatus successfully!')),
        );
      }
      _checkAdminRoleAndFetchBills();
    } catch (e) {
      print("Error updating bill status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to update status: ${e.toString()}')),
        );
      }
      setState(() {
        isLoading = false;
      });
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

  List<Map<String, dynamic>> get _filteredBills {
    var bills = allBills;

    // Filter by status
    if (_filterStatus != 'all') {
      bills = bills
          .where(
              (b) => b['status']?.toString().toLowerCase() == _filterStatus)
          .toList();
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      bills = bills.where((b) {
        final employee =
            (userNames[b['user_id']] ?? '').toLowerCase();
        final purpose = (b['purpose'] ?? '').toString().toLowerCase();
        final invoice = (b['invoice_no'] ?? '').toString().toLowerCase();
        final amount = (b['amount'] ?? '').toString();
        return employee.contains(q) ||
            purpose.contains(q) ||
            invoice.contains(q) ||
            amount.contains(q);
      }).toList();
    }

    return bills;
  }

  /// Bills shown on current page
  List<Map<String, dynamic>> get _paginatedBills {
    final filtered = _filteredBills;
    if (_displayCount >= filtered.length) return filtered;
    return filtered.sublist(0, _displayCount);
  }

  int _countByStatus(String status) => allBills
      .where((b) => b['status']?.toString().toLowerCase() == status)
      .length;

  void _exportCsv() {
    final csvBuffer = StringBuffer();
    csvBuffer.writeln(
        'Employee,Purpose,Amount,Date,Invoice No,Source,Status,Admin Notes,Submitted');
    for (final bill in _filteredBills) {
      final employee = userNames[bill['user_id']] ?? 'Unknown';
      final purpose = (bill['purpose'] ?? '').toString().replaceAll('"', '""');
      final amount = bill['amount'] ?? '';
      final date = bill['date'] ?? '';
      final invoice =
          (bill['invoice_no'] ?? '').toString().replaceAll('"', '""');
      final source = bill['source'] ?? '';
      final status = bill['status'] ?? '';
      final notes =
          (bill['admin_notes'] ?? '').toString().replaceAll('"', '""');
      final created = bill['created_at'] ?? '';
      csvBuffer.writeln(
          '"$employee","$purpose","$amount","$date","$invoice","$source","$status","$notes","$created"');
    }

    Clipboard.setData(ClipboardData(text: csvBuffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('CSV copied to clipboard. Paste into Excel or Google Sheets.'),
        ),
      );
    }
  }

  // Analytics helpers
  Map<String, double> _monthlySpend() {
    final Map<String, double> monthly = {};
    final now = DateTime.now();
    // Initialize last 6 months
    for (int i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      monthly[DateFormat('MMM yy').format(d)] = 0;
    }
    for (final bill in allBills) {
      if (bill['status']?.toString().toLowerCase() != 'approved') continue;
      if (bill['created_at'] == null) continue;
      try {
        final dt = DateTime.parse(bill['created_at']);
        final key = DateFormat('MMM yy').format(dt);
        if (monthly.containsKey(key)) {
          monthly[key] = monthly[key]! + (bill['amount'] as num).toDouble();
        }
      } catch (_) {}
    }
    return monthly;
  }

  Map<String, double> _categorySpend() {
    final Map<String, double> cats = {};
    for (final bill in allBills) {
      if (bill['status']?.toString().toLowerCase() != 'approved') continue;
      final purpose = bill['purpose'] ?? 'Other';
      cats[purpose] =
          (cats[purpose] ?? 0) + (bill['amount'] as num).toDouble();
    }
    // Sort by value descending, take top 5
    final sorted = cats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5);
    return {for (var e in top) e.key: e.value};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: isLoading
            ? _buildLoadingState()
            : errorMessage != null
                ? _buildErrorState()
                : RefreshIndicator(
                    onRefresh: _checkAdminRoleAndFetchBills,
                    color: AppColors.textPrimary,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader()),
                        SliverToBoxAdapter(child: _buildStatsRow()),
                        SliverToBoxAdapter(child: _buildSearchBar()),
                        SliverToBoxAdapter(child: _buildFilterChips()),
                        if (_showAnalytics)
                          SliverToBoxAdapter(child: _buildAnalyticsSection()),
                        if (_filteredBills.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Text('No bills found',
                                  style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.textHint,
                                      fontSize: 15)),
                            ),
                          )
                        else ...[
                          SliverPadding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 4, 20, 12),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: _buildBillCard(
                                        _paginatedBills[index]),
                                  );
                                },
                                childCount: _paginatedBills.length,
                              ),
                            ),
                          ),
                          if (_displayCount < _filteredBills.length)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 0, 20, 24),
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _displayCount += _pageSize;
                                    });
                                  },
                                  child: Text(
                                    'Load more (${_filteredBills.length - _displayCount} remaining)',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.rejectedBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.cloud_off_rounded,
                  size: 28, color: AppColors.rejected),
            ),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(errorMessage!,
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textHint, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkAdminRoleAndFetchBills,
              child: const Text('Retry'),
            ),
          ],
        ),
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
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: AppColors.textSecondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: AppColors.textHint)),
                Text('Dashboard',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _showAnalytics = !_showAnalytics),
            child: Icon(
              _showAnalytics
                  ? Icons.bar_chart_rounded
                  : Icons.bar_chart_rounded,
              color: _showAnalytics
                  ? AppColors.textPrimary
                  : AppColors.textHint,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _exportCsv,
            child: const Icon(Icons.download_rounded,
                color: AppColors.textHint, size: 20),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _checkAdminRoleAndFetchBills,
            child: const Icon(Icons.refresh_rounded,
                color: AppColors.textHint, size: 20),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: _navigateToLogin,
            child: const Icon(Icons.logout_rounded,
                color: AppColors.textHint, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _buildStatItem('Total', allBills.length, AppColors.textPrimary),
          _buildStatItem(
              'Pending', _countByStatus('pending'), AppColors.pending),
          _buildStatItem(
              'Approved', _countByStatus('approved'), AppColors.approved),
          _buildStatItem(
              'Rejected', _countByStatus('rejected'), AppColors.rejected),
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() {
          _searchQuery = value;
          _displayCount = _pageSize;
        }),
        decoration: InputDecoration(
          hintText: 'Search by employee, purpose, invoice...',
          prefixIcon: const Icon(Icons.search_rounded,
              size: 18, color: AppColors.textHint),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _displayCount = _pageSize;
                    });
                  },
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.textHint),
                )
              : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = [
      ('all', 'All', allBills.length),
      ('pending', 'Pending', _countByStatus('pending')),
      ('approved', 'Approved', _countByStatus('approved')),
      ('rejected', 'Rejected', _countByStatus('rejected')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: filters.map((f) {
          final isSelected = _filterStatus == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _filterStatus = f.$1;
                _displayCount = _pageSize;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f.$2,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white24
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${f.$3}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textHint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAnalyticsSection() {
    final monthly = _monthlySpend();
    final categories = _categorySpend();
    final maxMonthly =
        monthly.values.isEmpty ? 1.0 : monthly.values.reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Approved Spend (Last 6 Months)',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            SizedBox(
              height: 160,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxMonthly * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final label = monthly.keys.elementAt(group.x.toInt());
                        return BarTooltipItem(
                          '$label\n\u20B9${rod.toY.toStringAsFixed(0)}',
                          GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= monthly.length) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              monthly.keys.elementAt(idx),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10, color: AppColors.textHint),
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: monthly.entries.toList().asMap().entries.map((e) {
                    return BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.value,
                          color: AppColors.textPrimary,
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Top Categories (Approved)',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              ...categories.entries.map((e) {
                final total = categories.values.reduce((a, b) => a + b);
                final pct = total > 0 ? e.value / total : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              e.key,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, color: AppColors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '\u20B9${e.value.toStringAsFixed(0)}',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 5,
                          backgroundColor: AppColors.surfaceVariant,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBillCard(Map<String, dynamic> bill) {
    final String employeeUsername =
        userNames[bill['user_id']] ?? 'Unknown User';
    final String status = bill['status']?.toString() ?? 'pending';
    final bool isPending = status.toLowerCase() == 'pending';

    String formattedBillDate = bill['date'] ?? 'N/A';
    try {
      if (bill['date'] != null) {
        formattedBillDate = DateFormat('MMM dd, yyyy').format(DateTime.parse(bill['date']));
      }
    } catch (_) {}

    String formattedUploadDate = 'N/A';
    if (bill['created_at'] != null) {
      try {
        formattedUploadDate = DateFormat('MMM dd, yyyy').format(DateTime.parse(bill['created_at']));
      } catch (_) {
        formattedUploadDate = bill['created_at'].toString().split('T')[0];
      }
    }

    return ScaleTap(
      onTap: () {
        Navigator.push(
          context,
          AppPageRoute(
            page: BillViewerPage(billData: bill, isAdmin: true),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
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
                        employeeUsername
                            .substring(0, 1)
                            .toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
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
                          employeeUsername,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$formattedBillDate  \u00B7  Uploaded $formattedUploadDate',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\u20B9${(bill['amount'] as num?)?.toStringAsFixed(2) ?? 'N/A'}',
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
              if (isPending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _updateBillStatusWithRemarks(
                            bill['id'], 'rejected'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rejected,
                          side: const BorderSide(
                              color: AppColors.rejected, width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Reject',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _updateBillStatusWithRemarks(
                            bill['id'], 'approved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.approved,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Approve',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              ShimmerBlock(width: 40, height: 40, borderRadius: 12),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBlock(width: 50, height: 12, borderRadius: 6),
                  const SizedBox(height: 8),
                  ShimmerBlock(width: 100, height: 18, borderRadius: 6),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          ShimmerBlock(width: double.infinity, height: 72, borderRadius: 12),
          const SizedBox(height: 20),
          const LinearProgressIndicator(),
          const SizedBox(height: 20),
          ...List.generate(
            4,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ShimmerBlock(
                  width: double.infinity, height: 76, borderRadius: 12),
            ),
          ),
        ],
      ),
    );
  }
}

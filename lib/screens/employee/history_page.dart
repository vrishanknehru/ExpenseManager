import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/screens/employee/bill_viewer_page.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatefulWidget {
  final String userId;
  final String email;
  final String? username;
  final bool embedded;

  const HistoryPage({
    super.key,
    required this.userId,
    required this.email,
    this.username,
    this.embedded = false,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _allUserBills = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _fetchAllBills();
  }

  Future<void> _fetchAllBills() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userId = widget.userId;

      final billsResponse = await supabase
          .from('bills')
          .select(
            'id, purpose, source, amount, date, invoice_no, description, status, created_at, image_url, generated_pdf_url, admin_notes',
          )
          .eq('user_id', userId)
          .order('date', ascending: false);

      setState(() {
        _allUserBills = List<Map<String, dynamic>>.from(billsResponse);
        _isLoading = false;
      });
    } catch (e) {
      print("Error fetching all bills for history: $e");
      setState(() {
        _errorMessage = "Failed to load history: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredBills {
    if (_filterStatus == 'all') return _allUserBills;
    return _allUserBills
        .where((b) => b['status']?.toString().toLowerCase() == _filterStatus)
        .toList();
  }

  int _countByStatus(String status) => _allUserBills
      .where((b) => b['status']?.toString().toLowerCase() == status)
      .length;

  /// Group bills by month (e.g., "March 2026", "February 2026")
  Map<String, List<Map<String, dynamic>>> _groupByMonth() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final bill in _filteredBills) {
      String monthKey = 'Unknown';
      if (bill['date'] != null) {
        try {
          final dt = DateTime.parse(bill['date']);
          monthKey = DateFormat('MMMM yyyy').format(dt);
        } catch (_) {}
      }
      grouped.putIfAbsent(monthKey, () => []);
      grouped[monthKey]!.add(bill);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.embedded) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoadingState();

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: AppColors.rejected),
            const SizedBox(height: 12),
            Text(_errorMessage!,
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.rejected, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _fetchAllBills,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_allUserBills.isEmpty) {
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
              child: const Icon(Icons.history_rounded,
                  size: 32, color: AppColors.textHint),
            ),
            const SizedBox(height: 16),
            Text(
              'No history yet',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your submitted bills will appear here',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: AppColors.textHint),
            ),
          ],
        ),
      );
    }

    final grouped = _groupByMonth();
    final months = grouped.keys.toList();

    return RefreshIndicator(
      onRefresh: _fetchAllBills,
      color: AppColors.textPrimary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: months.length + 1, // +1 for filter chips header
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All', 'all', _allUserBills.length),
                    const SizedBox(width: 8),
                    _buildFilterChip('Pending', 'pending', _countByStatus('pending')),
                    const SizedBox(width: 8),
                    _buildFilterChip('Approved', 'approved', _countByStatus('approved')),
                    const SizedBox(width: 8),
                    _buildFilterChip('Rejected', 'rejected', _countByStatus('rejected')),
                  ],
                ),
              ),
            );
          }
          final monthIndex = index - 1;
          final month = months[monthIndex];
          final bills = grouped[month]!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (monthIndex > 0) const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, top: 4),
                child: Text(
                  month,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textHint,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              ...bills.map((bill) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _buildBillCard(bill),
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String status, int count) {
    final bool isSelected = _filterStatus == status;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.textPrimary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.textPrimary : AppColors.border,
          ),
        ),
        child: Text(
          '$label $count',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildBillCard(Map<String, dynamic> entry) {
    final String status = entry['status']?.toString() ?? 'pending';

    String formattedDate = 'N/A';
    if (entry['created_at'] != null) {
      try {
        final DateTime parsedCreatedAt = DateTime.parse(entry['created_at']);
        formattedDate = DateFormat('MMM dd, yyyy').format(parsedCreatedAt);
      } catch (e) {
        print("Error parsing created_at for display: $e");
        formattedDate = entry['created_at'].toString().split('T')[0];
      }
    }

    return ScaleTap(
      onTap: () {
        final billUrl = entry['image_url'];
        if (billUrl != null) {
          Navigator.push(
            context,
            AppPageRoute(
              page: BillViewerPage(billData: entry, isAdmin: false),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("No bill image/PDF found for this entry.")),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
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
                    '$formattedDate  \u00B7  ${entry['source'] ?? 'N/A'}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
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
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 20),
          ...List.generate(
            5,
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

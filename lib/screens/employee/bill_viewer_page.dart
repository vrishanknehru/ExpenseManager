import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:expense_manager/screens/employee/network_pdf_viewer_page.dart';
import 'package:expense_manager/theme/app_theme.dart';

class BillViewerPage extends StatefulWidget {
  final Map<String, dynamic> billData;
  final bool isAdmin;

  const BillViewerPage({
    super.key,
    required this.billData,
    this.isAdmin = false,
  });

  @override
  State<BillViewerPage> createState() => _BillViewerPageState();
}

class _BillViewerPageState extends State<BillViewerPage> {
  String? _localPdfPath;
  bool _isLoadingPdf = true;
  String? _pdfError;

  late String _billUrl;
  late String _purpose;
  late String _source;
  late String _amount;
  late String _billDate;
  late String _invoiceNo;
  late String _description;
  late String _status;
  late String _claimedAtDateOnly;
  late String _adminNotes;
  late String _generatedPdfUrl;

  @override
  void initState() {
    super.initState();

    _purpose = widget.billData['purpose'] ?? 'N/A';
    _source = widget.billData['source'] ?? 'N/A';
    _amount =
        (widget.billData['amount'] as num?)?.toStringAsFixed(2) ?? 'N/A';
    _billDate = widget.billData['date'] ?? 'N/A';
    _invoiceNo = widget.billData['invoice_no'] ?? 'N/A';
    _description = widget.billData['description'] ?? 'N/A';
    _status =
        widget.billData['status']?.toString().toLowerCase() ?? 'unknown';
    _billUrl = widget.billData['image_url'] ?? '';
    _adminNotes = widget.billData['admin_notes'] ?? '';
    _generatedPdfUrl = widget.billData['generated_pdf_url'] ?? '';

    if (widget.billData['created_at'] != null) {
      try {
        final DateTime parsedCreatedAt =
            DateTime.parse(widget.billData['created_at']);
        _claimedAtDateOnly =
            DateFormat('MMM dd, yyyy').format(parsedCreatedAt);
      } catch (e) {
        print("DEBUG: Error parsing created_at: $e");
        _claimedAtDateOnly =
            widget.billData['created_at'].toString().split('T')[0];
      }
    } else {
      _claimedAtDateOnly = 'N/A';
    }

    print('DEBUG BILLVIEWER: Page loaded. Bill URL: $_billUrl');
    print('DEBUG BILLVIEWER: Generated PDF URL: $_generatedPdfUrl');
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    if (_billUrl.isEmpty || !_billUrl.toLowerCase().endsWith('.pdf')) {
      print('DEBUG: Not a PDF or URL is empty. Skipping PDF load.');
      setState(() {
        _isLoadingPdf = false;
      });
      return;
    }

    if (kIsWeb) {
      setState(() {
        _isLoadingPdf = false;
      });
      return;
    }

    try {
      print('DEBUG: Attempting to download PDF from: $_billUrl');
      final response = await http.get(Uri.parse(_billUrl));
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/temp_bill_${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        await file.writeAsBytes(response.bodyBytes);
        setState(() {
          _localPdfPath = file.path;
          _isLoadingPdf = false;
        });
        print('DEBUG: PDF downloaded to: $_localPdfPath');
      } else {
        throw Exception(
            'Failed to download PDF: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Error loading PDF: $e');
      setState(() {
        _pdfError = 'Failed to load PDF: ${e.toString()}';
        _isLoadingPdf = false;
      });
    }
  }

  @override
  void dispose() {
    if (!kIsWeb &&
        _localPdfPath != null &&
        File(_localPdfPath!).existsSync()) {
      File(_localPdfPath!).deleteSync();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isPdf = _billUrl.toLowerCase().endsWith('.pdf');

    return Scaffold(
      appBar: AppBar(
        title: Text(_claimedAtDateOnly),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Amount',
                        style: GoogleFonts.plusJakartaSans(
                            color: Colors.white54, fontSize: 13),
                      ),
                      StatusChip(status: _status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '\u20B9$_amount',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _purpose,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Details card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Details',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildDetailRow('Bill Date', _billDate),
                  _buildDetailRow('Uploaded', _claimedAtDateOnly),
                  _buildDetailRow('Invoice No.', _invoiceNo),
                  _buildDetailRow('Source', _source),
                  _buildDetailRow('Description', _description),
                  if (_adminNotes.isNotEmpty &&
                      (_status == 'rejected' || widget.isAdmin))
                    _buildDetailRow('Admin Remarks', _adminNotes,
                        valueColor: AppColors.rejected),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Documents section
            Text(
              'Documents',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Original Bill
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Text(
                      'Original Bill',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: _buildAttachedBillContent(isPdf),
                  ),
                  if (_generatedPdfUrl.isNotEmpty) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      child: Text(
                        'Generated Claim PDF',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: _buildGeneratedPdfContent(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachedBillContent(bool isPdf) {
    if (_billUrl.isEmpty) {
      return _buildPlaceholder(
          'No attached bill found', Icons.receipt_long_rounded);
    }

    if (isPdf) {
      if (_isLoadingPdf) {
        return _buildLoadingCard();
      }
      if (kIsWeb) {
        return _buildActionButton(
          icon: Icons.open_in_new_rounded,
          label: 'View PDF in Browser',
          onTap: () async {
            final url = Uri.parse(_billUrl);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
        );
      }
      if (_localPdfPath != null) {
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              AppPageRoute(
                page: NetworkPdfViewerPage(pdfUrl: _billUrl),
              ),
            );
          },
          child: Container(
            height: MediaQuery.of(context).size.height * 0.5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: IgnorePointer(
                ignoring: true,
                child: PDFView(
                  filePath: _localPdfPath!,
                  enableSwipe: true,
                  swipeHorizontal: true,
                  autoSpacing: false,
                  pageFling: true,
                  pageSnap: true,
                  onError: (error) {
                    print('DEBUG: PDFView error: $error');
                    setState(() =>
                        _pdfError = 'Error rendering PDF: $error');
                  },
                  onRender: (pages) =>
                      print('DEBUG: PDF rendered $pages pages'),
                  onViewCreated: (PDFViewController vc) =>
                      print('DEBUG: PDFView created'),
                ),
              ),
            ),
          ),
        );
      }
      return _buildPlaceholder(
        _pdfError ?? 'Could not load PDF',
        Icons.error_outline_rounded,
      );
    }

    // Image bill
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: const Text("Bill Image"),
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              backgroundColor: Colors.black,
              body: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: CachedNetworkImage(
                    imageUrl: _billUrl,
                    placeholder: (context, url) =>
                        const CircularProgressIndicator(
                            color: Colors.white),
                    errorWidget: (context, url, error) => const Icon(
                        Icons.error,
                        color: Colors.red,
                        size: 50),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: _billUrl,
            placeholder: (context, url) => Container(
              height: 200,
              color: AppColors.surfaceVariant,
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) {
              print(
                  'DEBUG: CachedNetworkImage error: $error (URL: $url)');
              return _buildPlaceholder(
                  'Failed to load image', Icons.broken_image_rounded);
            },
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratedPdfContent() {
    if (_generatedPdfUrl.isEmpty) {
      return _buildPlaceholder(
          'No generated PDF available', Icons.picture_as_pdf_rounded);
    }

    if (kIsWeb) {
      return _buildActionButton(
        icon: Icons.picture_as_pdf_rounded,
        label: 'View Generated PDF',
        onTap: () async {
          final url = Uri.parse(_generatedPdfUrl);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        },
      );
    }

    return _buildActionButton(
      icon: Icons.picture_as_pdf_rounded,
      label: 'View Generated PDF',
      onTap: () {
        Navigator.push(
          context,
          AppPageRoute(
            page: NetworkPdfViewerPage(pdfUrl: _generatedPdfUrl),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(
                color: AppColors.textHint, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Loading PDF...',
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textHint,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: valueColor ?? AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

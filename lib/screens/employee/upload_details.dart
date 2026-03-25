import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:expense_manager/screens/employee/local_image_viewer.dart';
import 'package:expense_manager/screens/employee/local_pdf_viewer.dart';
import 'package:expense_manager/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:expense_manager/screens/employee/employee_home.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class UploadDetails extends StatefulWidget {
  final String? scannedAmount;
  final String? scannedInvoice;
  final String? scannedDate;
  final File? imageFile;
  final Uint8List? imageBytes;
  final String? fileName;
  final String userId;
  final String userEmail;
  final String? username;

  const UploadDetails({
    super.key,
    this.scannedAmount,
    this.scannedInvoice,
    this.scannedDate,
    this.imageFile,
    this.imageBytes,
    this.fileName,
    required this.userId,
    required this.userEmail,
    this.username,
  });

  @override
  State<UploadDetails> createState() => _UploadDetailsState();
}

class _UploadDetailsState extends State<UploadDetails> {
  final _dateController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedPurpose;
  String? _selectedSource;
  bool _isSubmitting = false;
  String _uploadStatus = '';
  double _uploadProgress = 0;

  String _descriptionHintText = "Enter detailed description of the expense";

  final List<String> purposeOptions = [
    "Team Dinner/Lunch",
    "Team Member Birthday",
    "Team Member Farewell",
    "Team Education",
    "Team Activity",
    "Travel & Hotel Stay",
    "Visa Application",
    "Domestic Travel",
    "International Roaming",
    "Taxable Wellness Grant",
    "Other",
  ];

  final Map<String, String> purposeRemarksMap = {
    "Team Dinner/Lunch":
        "Mention DM name / count of attendees / brief purpose",
    "Team Member Birthday":
        "Mention birthday person's name / what was bought",
    "Team Member Farewell":
        "Mention farewell person's name / reason for leaving",
    "Team Education": "Mention course/training name / key takeaways",
    "Team Activity": "Mention activity details / participants",
    "Travel & Hotel Stay":
        "Mention destination / dates / reason for travel",
    "Visa Application": "Mention country / reason for visa",
    "Domestic Travel": "Mention origin-destination / dates",
    "International Roaming": "Mention country / duration of roaming",
    "Taxable Wellness Grant":
        "Mention item/service purchased / benefit",
    "Other": "Please specify details of the expense",
  };

  final List<String> sourceOptions = ["Personal Card", "Company Card"];

  @override
  void initState() {
    super.initState();

    if (widget.scannedDate != null) {
      _dateController.text = widget.scannedDate!;
    }
    if (widget.scannedInvoice != null) {
      _invoiceController.text = widget.scannedInvoice!;
    }
    if (widget.scannedAmount != null) {
      final cleanAmount = widget.scannedAmount!.replaceAll(
        RegExp(r'[^\d.]'),
        '',
      );
      _amountController.text = cleanAmount;
    }
  }

  Future<void> _submitData() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _uploadProgress = 0;
    });

    final supabase = Supabase.instance.client;
    String? publicUrl;
    String? generatedPdfPublicUrl;

    try {
      final userId = widget.userId;

      if (userId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Error: User ID missing. Please try logging in again."),
            ),
          );
        }
        print(
            'DEBUG_UPLOAD: Aborting submission because userId is empty.');
        return;
      }

      final bool hasFile =
          kIsWeb ? widget.imageBytes != null : widget.imageFile != null;
      if (_selectedPurpose == null ||
          _selectedSource == null ||
          _dateController.text.isEmpty ||
          _invoiceController.text.isEmpty ||
          _amountController.text.isEmpty ||
          _descriptionController.text.isEmpty ||
          !hasFile) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    "Please fill all fields and attach an image.")),
          );
        }
        return;
      }

      double? amount;
      try {
        amount = double.parse(_amountController.text);
        if (amount <= 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Amount must be greater than zero.")),
            );
          }
          return;
        }
        if (amount > 1000000) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Amount exceeds maximum limit of ₹10,00,000.")),
            );
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Please enter a valid amount.")),
          );
        }
        return;
      }

      // Validate date is not in the future and not too old
      try {
        final billDate = DateTime.parse(_dateController.text);
        final now = DateTime.now();
        if (billDate.isAfter(now.add(const Duration(days: 1)))) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Bill date cannot be in the future.")),
            );
          }
          return;
        }
      } catch (_) {
        // Date parsing failed — will be caught by empty check above
      }

      // Check for duplicate invoice number
      if (_invoiceController.text.isNotEmpty) {
        try {
          final existingList = await supabase
              .from('bills')
              .select('id')
              .eq('invoice_no', _invoiceController.text);
          print('DEBUG_UPLOAD: Duplicate check result: $existingList');
          if (existingList.isNotEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("A bill with this invoice number already exists."),
                ),
              );
            }
            return;
          }
        } catch (e) {
          print('DEBUG_UPLOAD: Duplicate check failed: $e');
        }
      }

      // Validate file size (max 10MB)
      final int maxFileSize = 10 * 1024 * 1024;
      if (kIsWeb && widget.imageBytes != null && widget.imageBytes!.length > maxFileSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("File size exceeds 10MB limit.")),
          );
        }
        return;
      }
      if (!kIsWeb && widget.imageFile != null && widget.imageFile!.lengthSync() > maxFileSize) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("File size exceeds 10MB limit.")),
          );
        }
        return;
      }

      // Upload Original Image File
      setState(() {
        _uploadStatus = 'Uploading bill image...';
        _uploadProgress = 0.2;
      });
      final String fileExt = kIsWeb
          ? (widget.fileName?.split('.').last.toLowerCase() ?? 'jpg')
          : widget.imageFile!.path.split('.').last.toLowerCase();
      String uploadFileName =
          'bill_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      String storageFilePath = 'bills/$userId/$uploadFileName';
      print(
          'DEBUG_UPLOAD: Full storage file path: $storageFilePath');

      try {
        String uploadedFileNameResponse;
        if (kIsWeb) {
          uploadedFileNameResponse = await supabase.storage
              .from('receipts')
              .uploadBinary(storageFilePath, widget.imageBytes!);
        } else {
          uploadedFileNameResponse = await supabase.storage
              .from('receipts')
              .upload(storageFilePath, widget.imageFile!);
        }

        print(
            'DEBUG_UPLOAD: Raw response from upload (original): $uploadedFileNameResponse');

        if (uploadedFileNameResponse.isEmpty) {
          throw Exception(
              'Storage upload returned empty path for original image.');
        }

        publicUrl = supabase.storage
            .from('receipts')
            .getPublicUrl(storageFilePath);
        print(
            'DEBUG_UPLOAD: Public URL generated (original): $publicUrl');
      } on StorageException catch (se) {
        print(
            'DEBUG_UPLOAD: StorageException: ${se.message} (Status: ${se.statusCode})');
        throw Exception('Storage upload error: ${se.message}');
      } catch (e) {
        print(
            'DEBUG_UPLOAD: Unexpected error during original file upload: $e');
        throw Exception(
            'Original file upload failed: ${e.toString()}');
      }

      // Generate and Upload Generated PDF
      setState(() {
        _uploadStatus = 'Generating PDF...';
        _uploadProgress = 0.5;
      });
      try {
        print(
            'DEBUG_UPLOAD: Generating PDF from form details...');

        final generatedPdfBytes =
            await _generatePdfBytesFromDetails();

        String generatedPdfFileName =
            'generated_bill_${DateTime.now().millisecondsSinceEpoch}.pdf';
        String generatedPdfStoragePath =
            'generated_pdfs/$userId/$generatedPdfFileName';

        String uploadedGeneratedPdfResponse;
        if (kIsWeb) {
          uploadedGeneratedPdfResponse = await supabase.storage
              .from('receipts')
              .uploadBinary(
                generatedPdfStoragePath,
                generatedPdfBytes,
                fileOptions: const FileOptions(
                    contentType: 'application/pdf'),
              );
        } else {
          final tempDir = await getTemporaryDirectory();
          final generatedPdfFile =
              File('${tempDir.path}/$generatedPdfFileName');
          await generatedPdfFile.writeAsBytes(generatedPdfBytes);
          uploadedGeneratedPdfResponse = await supabase.storage
              .from('receipts')
              .upload(
                generatedPdfStoragePath,
                generatedPdfFile,
                fileOptions: const FileOptions(
                    contentType: 'application/pdf'),
              );
        }

        print(
            'DEBUG_UPLOAD: Raw response (generated PDF): $uploadedGeneratedPdfResponse');

        if (uploadedGeneratedPdfResponse.isEmpty) {
          throw Exception(
              'Storage upload for generated PDF returned empty path.');
        }

        generatedPdfPublicUrl = supabase.storage
            .from('receipts')
            .getPublicUrl(generatedPdfStoragePath);
        print(
            'DEBUG_UPLOAD: Generated PDF Public URL: $generatedPdfPublicUrl');
      } on StorageException catch (se) {
        print(
            'DEBUG_UPLOAD: StorageException (PDF): ${se.message}');
        generatedPdfPublicUrl = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "Warning: Failed to upload generated PDF: ${se.message}")),
          );
        }
      } catch (e) {
        print(
            'DEBUG_UPLOAD: Unexpected error during PDF creation/upload: $e');
        generatedPdfPublicUrl = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "Warning: Failed to create/upload generated PDF: ${e.toString()}")),
          );
        }
      }

      // Insert Bill Details into Database
      setState(() {
        _uploadStatus = 'Saving to database...';
        _uploadProgress = 0.85;
      });
      await supabase.from('bills').insert({
        'user_id': userId,
        'purpose': _selectedPurpose,
        'source': _selectedSource,
        'date': _dateController.text,
        'invoice_no': _invoiceController.text,
        'amount': amount,
        'description': _descriptionController.text,
        'image_url': publicUrl,
        'generated_pdf_url': generatedPdfPublicUrl,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Bill submitted successfully!")),
        );
        Navigator.pushReplacement(
          context,
          AppPageRoute(
            page: EmployeeHome(
              userId: userId,
              email: widget.userEmail,
              username: widget.username,
            ),
          ),
        );
      }
    } on PostgrestException catch (e) {
      print('Upload failed: PostgrestException: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Database error: ${e.message}")),
        );
      }
    } catch (e) {
      print('Upload failed: Unexpected error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Upload failed: ${e.toString()}")),
        );
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<Uint8List> _generatePdfBytesFromDetails() async {
    final pdf = pw.Document();

    String userNameForPdf = widget.username ?? widget.userEmail;
    final String employeeCode = widget.userId.length >= 8
        ? widget.userId.substring(0, 8)
        : widget.userId;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(40),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'EXPENSE CLAIM',
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey900,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Invoice No: ${_invoiceController.text}',
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Date',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey500,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          _dateController.text,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Divider(color: PdfColors.grey300, thickness: 1),
                pw.SizedBox(height: 24),

                // Employee details
                pw.Text(
                  'EMPLOYEE DETAILS',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey500,
                    letterSpacing: 1,
                  ),
                ),
                pw.SizedBox(height: 10),
                _pdfDetailRow('Name', userNameForPdf),
                _pdfDetailRow('Employee Code', employeeCode),
                _pdfDetailRow('Purpose', _selectedPurpose ?? 'N/A'),
                _pdfDetailRow(
                    'Source', _selectedSource ?? 'N/A'),
                pw.SizedBox(height: 24),
                pw.Divider(color: PdfColors.grey300, thickness: 1),
                pw.SizedBox(height: 24),

                // Expense details
                pw.Text(
                  'EXPENSE DETAILS',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey500,
                    letterSpacing: 1,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Table.fromTextArray(
                  headers: ['Description', 'Amount (Rs.)'],
                  data: [
                    [
                      _descriptionController.text,
                      'Rs. ${_amountController.text}',
                    ],
                  ],
                  border: pw.TableBorder.all(
                      color: PdfColors.grey300, width: 0.5),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                    color: PdfColors.white,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey800),
                  cellStyle: const pw.TextStyle(fontSize: 11),
                  cellAlignment: pw.Alignment.centerLeft,
                  cellPadding: const pw.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1),
                  },
                ),
                pw.SizedBox(height: 20),

                // Total
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      'Total: Rs. ${_amountController.text}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 40),

                // Footer
                pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Generated on ${DateTime.now().toIso8601String().split('T')[0]}',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey400,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _pdfDetailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColors.grey600,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    _invoiceController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _showFullScreenImage() {
    if (kIsWeb && widget.imageBytes != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text("Bill Preview"),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            backgroundColor: Colors.black,
            body: Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(widget.imageBytes!,
                    fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      );
    } else if (!kIsWeb && widget.imageFile != null) {
      String fileExtension =
          widget.imageFile!.path.split('.').last.toLowerCase();
      if (fileExtension == 'jpg' ||
          fileExtension == 'jpeg' ||
          fileExtension == 'png') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                LocalImageViewerPage(imageFile: widget.imageFile!),
          ),
        );
      } else if (fileExtension == 'pdf') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                LocalPdfViewerPage(pdfFile: widget.imageFile!),
          ),
        );
      }
    }
  }

  Widget _buildUploadOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.symmetric(
              vertical: 32, horizontal: 28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceVariant,
                ),
                child: const Icon(
                  Icons.cloud_upload_rounded,
                  size: 28,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: _uploadProgress),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _uploadStatus,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '${(_uploadProgress * 100).toInt()}%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Upload Details"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image preview
                GestureDetector(
                  onTap: _showFullScreenImage,
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildPreview(),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                    BorderRadius.circular(6),
                              ),
                              child: Text('Tap to preview',
                                  style:
                                      GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontSize: 11)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Form fields
                Text('Expense Details',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2)),
                const SizedBox(height: 16),

                _buildLabel('Purpose of Expense'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      hintText: 'Select purpose'),
                  initialValue: _selectedPurpose,
                  items: purposeOptions.map((purpose) {
                    return DropdownMenuItem(
                        value: purpose, child: Text(purpose));
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedPurpose = value;
                      _descriptionHintText =
                          purposeRemarksMap[value] ?? '';
                    });
                  },
                ),
                const SizedBox(height: 14),

                _buildLabel('Source of Payment'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      hintText: 'Select source'),
                  initialValue: _selectedSource,
                  items: sourceOptions.map((source) {
                    return DropdownMenuItem(
                        value: source, child: Text(source));
                  }).toList(),
                  onChanged: (value) =>
                      setState(() => _selectedSource = value),
                ),
                const SizedBox(height: 14),

                _buildLabel('Date'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _dateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: Icon(Icons.calendar_today_rounded,
                        size: 18),
                  ),
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      _dateController.text =
                          DateFormat('yyyy-MM-dd').format(picked);
                    }
                  },
                ),
                const SizedBox(height: 14),

                _buildLabel('Invoice Number'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _invoiceController,
                  decoration: const InputDecoration(
                      hintText: 'Enter invoice number'),
                ),
                const SizedBox(height: 14),

                _buildLabel('Amount'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixText: '\u20B9 ',
                    prefixStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: 14),

                _buildLabel('Description'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration:
                      InputDecoration(hintText: _descriptionHintText),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitData,
                    child: Text('Submit Bill',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          if (_isSubmitting) _buildUploadOverlay(),
        ],
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

  Widget _buildPreview() {
    if (kIsWeb && widget.imageBytes != null) {
      final ext =
          widget.fileName?.split('.').last.toLowerCase() ?? '';
      if (ext == 'pdf') {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf_rounded,
                  size: 40, color: AppColors.textHint),
              const SizedBox(height: 8),
              Text('PDF attached',
                  style: GoogleFonts.plusJakartaSans(
                      color: AppColors.textHint, fontSize: 13)),
            ],
          ),
        );
      }
      return Image.memory(widget.imageBytes!,
          fit: BoxFit.contain);
    } else if (!kIsWeb && widget.imageFile != null) {
      return _buildFilePreview(widget.imageFile!);
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.image_not_supported_rounded,
              size: 36, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text('No image selected',
              style: GoogleFonts.plusJakartaSans(
                  color: AppColors.textHint, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildFilePreview(File file) {
    print('DEBUG: _buildFilePreview called for: ${file.path}');
    if (!file.existsSync()) {
      return Center(
        child: Text('File not found',
            style: GoogleFonts.plusJakartaSans(
                color: AppColors.rejected)),
      );
    }

    String fileExtension =
        file.path.split('.').last.toLowerCase();

    if (fileExtension == 'pdf') {
      return IgnorePointer(
        ignoring: true,
        child: SizedBox(
          height: 160,
          width: double.infinity,
          child: PDFView(
            filePath: file.path,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            pageSnap: true,
            onError: (error) =>
                print('DEBUG: PDFView preview error: $error'),
            onRender: (pages) =>
                print('DEBUG: PDF preview rendered $pages pages'),
          ),
        ),
      );
    } else if (fileExtension == 'jpg' ||
        fileExtension == 'jpeg' ||
        fileExtension == 'png') {
      return Image.file(file, fit: BoxFit.contain);
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insert_drive_file_rounded,
                size: 40, color: AppColors.textHint),
            const SizedBox(height: 8),
            Text(
              file.path.split('/').last,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: AppColors.textHint),
            ),
          ],
        ),
      );
    }
  }

}

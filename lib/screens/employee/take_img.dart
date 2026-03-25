import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:expense_manager/screens/employee/upload_details.dart';
import 'package:expense_manager/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class TakeImagePage extends StatefulWidget {
  final String userId;
  final String userEmail;

  const TakeImagePage({
    super.key,
    required this.userId,
    required this.userEmail,
  });

  @override
  State<TakeImagePage> createState() => _TakeImagePageState();
}

class _TakeImagePageState extends State<TakeImagePage> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isProcessing = false;
  double _progress = 0;
  String _progressLabel = '';

  Future<Map<String, String?>> _performServerOcr(
      List<int> imageBytes) async {
    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final supabaseKey = dotenv.env['SUPABASE_ANON_KEY']!;
    final base64Image = base64Encode(imageBytes);

    try {
      print('DEBUG: Calling server-side OCR...');
      setState(() {
        _progress = 0.6;
        _progressLabel = 'Extracting details...';
      });
      final response = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/ocr-extract'),
        headers: {
          'Authorization': 'Bearer $supabaseKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'image': base64Image}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(
            'DEBUG: OCR response: ${response.body.substring(0, (response.body.length).clamp(0, 200))}');
        setState(() => _progress = 1.0);

        // Check if OCR returned actual data or just nulls/error
        if (data['error'] != null) {
          print('DEBUG: OCR returned error: ${data['error']}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'OCR error: ${data['error']}. Please fill details manually.')),
            );
          }
          return {'amount': null, 'invoice_no': null, 'date': null};
        }

        return {
          'amount': data['amount']?.toString(),
          'invoice_no': data['invoice_no']?.toString(),
          'date': data['date']?.toString(),
        };
      } else {
        print(
            'DEBUG: OCR request failed with status ${response.statusCode}: ${response.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'OCR extraction failed. Please fill details manually.')),
          );
        }
      }
    } catch (e) {
      print('DEBUG: OCR request error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Could not connect to OCR service: ${e.toString().length > 80 ? '${e.toString().substring(0, 80)}...' : e}')),
        );
      }
    }

    return {'amount': null, 'invoice_no': null, 'date': null};
  }

  Future<void> _pickAndProcessFile(
    BuildContext context, {
    required bool isPdf,
    ImageSource? imageSource,
  }) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _progress = 0.1;
      _progressLabel = 'Selecting file...';
    });

    File? selectedFile;
    Uint8List? fileBytes;
    String? fileName;
    String? fileExtension;

    try {
      if (isPdf) {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          withData: kIsWeb,
        );
        if (result != null &&
            result.files.single.bytes != null &&
            kIsWeb) {
          fileBytes = result.files.single.bytes!;
          fileName = result.files.single.name;
          fileExtension = 'pdf';
          print('DEBUG: PDF picked (web): $fileName');
        } else if (result != null &&
            result.files.single.path != null &&
            !kIsWeb) {
          selectedFile = File(result.files.single.path!);
          fileName = result.files.single.name;
          fileExtension = 'pdf';
          print('DEBUG: PDF picked: ${selectedFile.path}');
        }
      } else {
        if (imageSource == null) {
          throw Exception(
              'ImageSource must be provided for image picking.');
        }
        final XFile? pickedXFile = await _imagePicker.pickImage(
          source: imageSource,
        );
        if (pickedXFile != null) {
          fileBytes = await pickedXFile.readAsBytes();
          fileName = pickedXFile.name;
          fileExtension = fileName.split('.').last.toLowerCase();
          if (!kIsWeb) {
            selectedFile = File(pickedXFile.path);
          }
          print('DEBUG: Image picked: $fileName');
        }
      }

      setState(() {
        _progress = 0.3;
        _progressLabel = 'Processing file...';
      });

      final bool hasFile =
          kIsWeb ? fileBytes != null : selectedFile != null;
      if (!hasFile) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No file selected.')),
          );
        }
        return;
      }

      if (!kIsWeb && selectedFile != null && !selectedFile.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Selected file does not exist on device.')),
          );
        }
        return;
      }

      String? scannedAmount;
      String? scannedInvoice;
      String? scannedDate;

      if (fileExtension == 'jpg' ||
          fileExtension == 'jpeg' ||
          fileExtension == 'png') {
        setState(() {
          _progress = 0.4;
          _progressLabel = 'Running OCR scan...';
        });
        print('DEBUG: Sending image to server-side OCR...');
        final imageBytes =
            fileBytes ?? await selectedFile!.readAsBytes();
        final ocrResult = await _performServerOcr(imageBytes);

        scannedAmount = ocrResult['amount'];
        scannedInvoice = ocrResult['invoice_no'];
        scannedDate = ocrResult['date'];

        print(
            'DEBUG: OCR extracted - amount: $scannedAmount, invoice: $scannedInvoice, date: $scannedDate');
      } else if (fileExtension == 'pdf') {
        print('DEBUG: PDF selected. OCR skipped.');
        setState(() {
          _progress = 1.0;
          _progressLabel = 'PDF ready';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'PDF selected. Please fill details manually.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Unsupported file type. Please select an image (jpg/png) or PDF.')),
          );
        }
        return;
      }

      _navigateToUploadDetails(
        scannedAmount: scannedAmount,
        scannedInvoice: scannedInvoice,
        scannedDate: scannedDate,
        imageFile: selectedFile,
        imageBytes: fileBytes,
        fileName: fileName,
        userId: widget.userId,
        userEmail: widget.userEmail,
      );
    } catch (e) {
      print("DEBUG: Error during file picking or processing: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text("Failed to process file: ${e.toString()}")),
        );
      }
    } finally {
      setState(() {
        _isProcessing = false;
        _progress = 0;
      });
    }
  }

  void _navigateToUploadDetails({
    String? scannedAmount,
    String? scannedInvoice,
    String? scannedDate,
    File? imageFile,
    Uint8List? imageBytes,
    String? fileName,
    required String userId,
    required String userEmail,
  }) {
    if (mounted) {
      Navigator.push(
        context,
        AppPageRoute(
          page: UploadDetails(
            scannedAmount: scannedAmount,
            scannedInvoice: scannedInvoice,
            scannedDate: scannedDate,
            imageFile: imageFile,
            imageBytes: imageBytes,
            fileName: fileName,
            userId: userId,
            userEmail: userEmail,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Bill'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isProcessing
                ? _buildProcessingState()
                : _buildPickerState(),
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingState() {
    return Column(
      key: const ValueKey('processing'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.document_scanner_rounded,
              size: 36, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Text(
          _progressLabel,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Extracting invoice details',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, color: AppColors.textHint),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _progress),
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
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toInt()}%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPickerState() {
    return Column(
      key: const ValueKey('picker'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.receipt_long_rounded,
              size: 36, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Text(
          'Add your bill',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Take a photo or upload a file',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, color: AppColors.textHint),
        ),
        const SizedBox(height: 28),
        _buildOptionCard(
          icon: Icons.camera_alt_rounded,
          label: 'Take Photo',
          subtitle: 'Use your camera',
          onTap: () => _pickAndProcessFile(context,
              isPdf: false, imageSource: ImageSource.camera),
        ),
        const SizedBox(height: 8),
        _buildOptionCard(
          icon: Icons.photo_library_rounded,
          label: 'Choose from Gallery',
          subtitle: 'Select an image',
          onTap: () => _pickAndProcessFile(context,
              isPdf: false, imageSource: ImageSource.gallery),
        ),
        const SizedBox(height: 8),
        _buildOptionCard(
          icon: Icons.picture_as_pdf_rounded,
          label: 'Upload PDF',
          subtitle: 'Select a PDF file',
          onTap: () => _pickAndProcessFile(context, isPdf: true),
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ScaleTap(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }
}

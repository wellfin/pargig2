import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/file_saver.dart';

/// Everything that appears on a payment invoice.
class InvoiceData {
  final String jobTitle;
  final String workerName;
  final String payerName;
  final double amount;
  final String methodLabel;
  final String? transactionId;
  final String jobId;
  final DateTime paidAt;
  final bool isCod;

  const InvoiceData({
    required this.jobTitle,
    required this.workerName,
    required this.payerName,
    required this.amount,
    required this.methodLabel,
    required this.jobId,
    required this.paidAt,
    this.transactionId,
    this.isCod = false,
  });

  /// Invoice number derived from the job id, so the same job always
  /// produces the same reference — re-downloading does not mint a new one.
  String get invoiceNumber {
    final tail = jobId.length >= 6
        ? jobId.substring(jobId.length - 6).toUpperCase()
        : jobId.toUpperCase();
    return 'INV-$tail';
  }
}

/// Builds and shares a payment invoice as a real PDF.
///
/// `Printing.sharePdf` hands the bytes to the OS share/save sheet, which
/// is what makes this work on modern Android without asking for storage
/// permission: the user picks Files, Drive, WhatsApp or wherever, and the
/// system does the writing. Saving to a hard-coded Downloads path would
/// need MANAGE_EXTERNAL_STORAGE on Android 11+ and still fail on iOS.
class InvoicePdf {
  InvoicePdf._();

  static const _orange = PdfColor.fromInt(0xFFFF6900);
  static const _ink = PdfColor.fromInt(0xFF101828);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFE5E7EB);
  static const _wash = PdfColor.fromInt(0xFFF9FAFB);

  /// The rupee sign is absent from the default PDF font, so it renders as
  /// a blank box. Google Fonts' Noto Sans carries it.
  ///
  /// This downloads on first use and is cached afterwards. If the device
  /// is offline the package falls back to Helvetica, which has no Unicode
  /// support at all — so every string this file draws itself is plain
  /// ASCII ("Rs", "-", never a rupee sign or an em dash). Only user data
  /// (a job title in Hindi, say) can still degrade, and only offline.
  static Future<pw.ThemeData> _theme() async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    return pw.ThemeData.withFont(base: regular, bold: bold);
  }

  static String _money(double v) => 'Rs ${v.toStringAsFixed(2)}';

  static String _date(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day} ${months[d.month - 1]} ${d.year}, $h:$m $ap';
  }

  /// Renders the invoice and returns the raw PDF bytes.
  static Future<Uint8List> build(InvoiceData data) async {
    final doc = pw.Document(
      title: '${data.invoiceNumber} - Pargig',
      author: 'Pargig',
    );
    final theme = await _theme();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(data),
            pw.SizedBox(height: 26),
            _parties(data),
            pw.SizedBox(height: 22),
            _lineItems(data),
            pw.SizedBox(height: 18),
            _paymentDetails(data),
            pw.Spacer(),
            _footer(),
          ],
        ),
      ),
    );
    return doc.save();
  }

  /// Builds the PDF and saves it straight to the device.
  ///
  /// Downloads rather than shares: the button says Download, so asking
  /// the user to pick an app to send it to is a step they did not ask
  /// for. On Android it lands in the public Downloads folder; on iOS, in
  /// the app's folder in Files.
  ///
  /// Returns where it landed, or null if the save failed — the caller
  /// then offers the share sheet so the invoice is not simply lost.
  static Future<String?> download(InvoiceData data) async {
    final bytes = await build(data);
    return FileSaver.saveToDownloads(bytes, '${data.invoiceNumber}.pdf');
  }

  /// Last resort when a direct save is refused by the OS.
  static Future<void> share(InvoiceData data) async {
    final bytes = await build(data);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${data.invoiceNumber}.pdf',
    );
  }

  // ------------------------------------------------------------ sections

  static pw.Widget _header(InvoiceData data) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'PARGIG',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: _orange,
                letterSpacing: 1.2,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Post Any Need. Take Any Job',
              style: const pw.TextStyle(fontSize: 9, color: _muted),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'PAYMENT INVOICE',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: _ink,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              data.invoiceNumber,
              style: const pw.TextStyle(fontSize: 10, color: _muted),
            ),
            pw.Text(
              _date(data.paidAt),
              style: const pw.TextStyle(fontSize: 10, color: _muted),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _parties(InvoiceData data) {
    pw.Widget party(String label, String name) => pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8.5, color: _muted),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            name.trim().isEmpty ? '-' : name,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ],
      ),
    );

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _wash,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        children: [
          party('PAID BY', data.payerName),
          pw.SizedBox(width: 16),
          party('PAID TO', data.workerName),
        ],
      ),
    );
  }

  static pw.Widget _lineItems(InvoiceData data) {
    return pw.Column(
      children: [
        // Header strip
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _ink,
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'DESCRIPTION',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.Text(
                'AMOUNT',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: _line),
              right: pw.BorderSide(color: _line),
              bottom: pw.BorderSide(color: _line),
            ),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      data.jobTitle.trim().isEmpty ? 'Service' : data.jobTitle,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Service completed and payment released',
                      style: const pw.TextStyle(fontSize: 9, color: _muted),
                    ),
                  ],
                ),
              ),
              pw.Text(
                _money(data.amount),
                style: const pw.TextStyle(fontSize: 11, color: _ink),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        // Total
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFFFF7ED),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'TOTAL PAID',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  pw.Text(
                    _money(data.amount),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: _orange,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _paymentDetails(InvoiceData data) {
    pw.Widget row(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 110,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 9.5, color: _muted),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 9.5, color: _ink),
            ),
          ),
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Payment details',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 6),
        row('Payment method', data.methodLabel),
        // Cash has no gateway reference; saying so beats an empty row the
        // reader takes for missing data.
        row(
          'Transaction ID',
          (data.transactionId ?? '').trim().isNotEmpty
              ? data.transactionId!
              : (data.isCod ? 'Cash on delivery' : '-'),
        ),
        row('Job reference', data.jobId),
        row('Status', 'PAID'),
      ],
    );
  }

  static pw.Widget _footer() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: _line),
        pw.SizedBox(height: 6),
        pw.Text(
          'This is a computer-generated invoice and does not require a '
          'signature.',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Pargig - for questions about this payment, use Get Help on the '
          'service in the app.',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    );
  }
}

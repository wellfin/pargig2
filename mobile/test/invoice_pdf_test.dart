import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/utils/invoice_pdf.dart';

InvoiceData sample({
  String? txn = 'TXNMU11KD07FD5',
  bool isCod = false,
  String title = 'cleaning',
}) =>
    InvoiceData(
      jobTitle: title,
      workerName: 'dev',
      payerName: 'Rohan Sharma',
      amount: 230,
      methodLabel: 'PhonePe',
      transactionId: txn,
      jobId: '6aa79acca87b0c8ba444bda0',
      paidAt: DateTime(2026, 9, 14, 15, 0),
      isCod: isCod,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invoice number is derived from the job id and is stable', () {
    final a = sample();
    final b = sample();
    expect(a.invoiceNumber, 'INV-44BDA0');
    // Re-downloading the same job must not mint a new reference.
    expect(a.invoiceNumber, b.invoiceNumber);
  });

  test('a short job id does not crash the reference', () {
    final d = InvoiceData(
      jobTitle: 'x',
      workerName: 'w',
      payerName: 'p',
      amount: 1,
      methodLabel: 'Cash',
      jobId: 'abc',
      paidAt: DateTime(2026, 1, 1),
    );
    expect(d.invoiceNumber, 'INV-ABC');
  });

  test('builds a real, non-trivial PDF', () async {
    final bytes = await InvoicePdf.build(sample());

    // %PDF- magic number: proves it is a genuine PDF, not an empty buffer.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));

    // %%EOF terminator at the tail.
    final tail = String.fromCharCodes(
      bytes.skip(bytes.length - 40).toList(),
    );
    expect(tail.contains('%%EOF'), isTrue);
  });

  test('renders for cash-on-delivery, which has no transaction id',
      () async {
    // The null-txn path is the one most likely to blow up on a null deref.
    final bytes = await InvoicePdf.build(sample(txn: null, isCod: true));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('survives an empty job title and a long one', () async {
    expect(
      (await InvoicePdf.build(sample(title: ''))).length,
      greaterThan(1000),
    );
    expect(
      (await InvoicePdf.build(sample(title: 'A' * 300))).length,
      greaterThan(1000),
    );
  });
}

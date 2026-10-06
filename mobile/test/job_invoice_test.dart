import 'package:flutter_test/flutter_test.dart';
import 'package:pargig/utils/job_invoice.dart';

Map<String, dynamic> paidJob({
  Map<String, dynamic>? payment,
  String? releasedAt = '2026-09-14T09:30:00.000Z',
}) =>
    {
      '_id': '6aa79acca87b0c8ba444bda0',
      'title': 'Deep cleaning',
      'status': 'completed',
      'paymentReleasedAt': releasedAt,
      'jobgiver': {'name': 'Rohan Sharma'},
      'selectedJobtaker': {'name': 'Dev Kumar'},
      'payment': payment ??
          {
            'amount': 230,
            'method': 'PhonePe',
            'transactionId': 'TXNMU11KD07FD5',
            'isCod': false,
            'releasedAt': '2026-09-14T09:30:00.000Z',
          },
    };

void main() {
  test('giver side: payer is me, worker is the hired taker', () {
    final inv = invoiceFromJob(paidJob(), asWorker: false, myName: 'Rohan')!;
    expect(inv.payerName, 'Rohan');
    expect(inv.workerName, 'Dev Kumar');
    expect(inv.amount, 230);
    expect(inv.methodLabel, 'PhonePe');
    expect(inv.transactionId, 'TXNMU11KD07FD5');
    expect(inv.invoiceNumber, 'INV-44BDA0');
  });

  test('worker side: payer is the job giver, worker is me', () {
    final inv = invoiceFromJob(paidJob(), asWorker: true, myName: 'Dev')!;
    expect(inv.payerName, 'Rohan Sharma');
    expect(inv.workerName, 'Dev');
  });

  test('same job gives the same invoice number from either side', () {
    final a = invoiceFromJob(paidJob(), asWorker: false, myName: 'x')!;
    final b = invoiceFromJob(paidJob(), asWorker: true, myName: 'y')!;
    expect(a.invoiceNumber, b.invoiceNumber);
  });

  test('dated when the money moved, not when opened', () {
    final inv = invoiceFromJob(paidJob(), asWorker: false, myName: 'x')!;
    expect(inv.paidAt.toUtc(), DateTime.utc(2026, 9, 14, 9, 30));
  });

  test('no invoice until paid', () {
    expect(
      invoiceFromJob(paidJob(releasedAt: null), asWorker: false, myName: 'x'),
      isNull,
    );
  });

  test('no invoice when the payment summary is missing or zero', () {
    final noPayment = paidJob()..['payment'] = null;
    expect(invoiceFromJob(noPayment, asWorker: true, myName: 'x'), isNull);
    expect(
      invoiceFromJob(paidJob(payment: {'amount': 0}),
          asWorker: true, myName: 'x'),
      isNull,
    );
  });

  test('cash job: COD label, no transaction id', () {
    final inv = invoiceFromJob(
      paidJob(payment: {'amount': 500, 'isCod': true}),
      asWorker: true,
      myName: 'Dev',
    )!;
    expect(inv.isCod, isTrue);
    expect(inv.methodLabel, 'Cash on Delivery');
    expect(inv.transactionId, isNull);
  });
}

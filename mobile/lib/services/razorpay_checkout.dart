import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

/// How a trip through Razorpay's checkout sheet ended.
enum CheckoutOutcome {
  /// The payer paid. [CheckoutResult.paymentId] and
  /// [CheckoutResult.signature] are what the server verifies.
  paid,

  /// The payer backed out. Not an error — nothing has been charged, and
  /// the screen should offer to try again rather than apologise.
  cancelled,

  /// The attempt failed: declined card, no network, bad credentials.
  failed,
}

class CheckoutResult {
  final CheckoutOutcome outcome;
  final String? paymentId;
  final String? orderId;
  final String? signature;

  /// Something worth showing a person. Razorpay's own messages are
  /// usually fit to read ("Payment failed: card declined"); the raw
  /// JSON blob they sometimes send instead is not, and is dropped.
  final String? message;

  const CheckoutResult._(
    this.outcome, {
    this.paymentId,
    this.orderId,
    this.signature,
    this.message,
  });

  bool get paid => outcome == CheckoutOutcome.paid;
  bool get cancelled => outcome == CheckoutOutcome.cancelled;
}

/// Opens Razorpay's checkout sheet and waits for it to close.
///
/// The plugin is event-based — you register handlers and the result
/// arrives later — which is awkward inside a screen that just wants to
/// await a payment. This wraps it in a Future and guarantees exactly
/// one answer: handlers are cleared the moment one arrives, so a stray
/// second event cannot complete the same future twice.
///
/// Nothing about the gateway is compiled in. The key id and order id
/// both come from the backend, which reads them from whatever an admin
/// saved in the panel. A key change takes effect on the next payment,
/// with no app release.
class RazorpayCheckout {
  /// Guards against the checkout never calling back at all — a native
  /// crash, or an Activity killed behind the sheet. Without it the
  /// payment screen would spin forever with no way out.
  static const _timeout = Duration(minutes: 10);

  static Future<CheckoutResult> open({
    required String keyId,
    required String orderId,
    required num amount,
    required String name,
    String? description,
    String? contact,
    String? email,
    String currency = 'INR',
  }) async {
    final razorpay = Razorpay();
    final done = Completer<CheckoutResult>();

    void finish(CheckoutResult result) {
      if (done.isCompleted) return;
      done.complete(result);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      finish(
        CheckoutResult._(
          CheckoutOutcome.paid,
          paymentId: r.paymentId,
          // Razorpay echoes the order id back; preferring its copy over
          // ours means a mismatch shows up as a failed signature check
          // on the server instead of being papered over here.
          orderId: r.orderId ?? orderId,
          signature: r.signature,
        ),
      );
    });

    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      final cancelled = r.code == Razorpay.PAYMENT_CANCELLED;
      finish(
        CheckoutResult._(
          cancelled ? CheckoutOutcome.cancelled : CheckoutOutcome.failed,
          message: cancelled ? null : _readable(r.message),
        ),
      );
    });

    // Paytm and the like hand the payment off to another app. We get
    // told which one and nothing else, so there is no signature to
    // verify — the webhook is what confirms these.
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      finish(
        CheckoutResult._(
          CheckoutOutcome.failed,
          message:
              'Payment was handed to ${r.walletName ?? 'another app'}. '
              'If it went through, the payment will appear shortly.',
        ),
      );
    });

    try {
      razorpay.open({
        'key': keyId,
        'order_id': orderId,
        // Razorpay counts in paise. The order already fixes the amount
        // server-side, so this is what the sheet displays rather than
        // what gets charged — but a mismatch looks like a bug to the
        // payer, so it has to agree.
        'amount': (amount * 100).round(),
        'currency': currency,
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'prefill': {
          if (contact != null && contact.isNotEmpty) 'contact': contact,
          if (email != null && email.isNotEmpty) 'email': email,
        },
        'theme': {'color': '#FF6900'},
        // Keep the payer inside the sheet: dismissing by tapping outside
        // reads as a cancel we never hear about.
        'modal': {'confirm_close': true},
      });
    } catch (e) {
      razorpay.clear();
      return CheckoutResult._(
        CheckoutOutcome.failed,
        message: 'Could not open the payment screen: $e',
      );
    }

    try {
      return await done.future.timeout(
        _timeout,
        onTimeout: () => const CheckoutResult._(
          CheckoutOutcome.failed,
          message: 'The payment screen did not respond. '
              'If money was taken, it will be confirmed automatically.',
        ),
      );
    } finally {
      razorpay.clear();
    }
  }

  /// Razorpay sometimes puts a JSON error body in `message`. Showing
  /// that to a person is worse than showing nothing.
  static String? _readable(String? message) {
    final m = message?.trim();
    if (m == null || m.isEmpty) return null;
    if (m.startsWith('{') || m.startsWith('[')) return null;
    return m;
  }
}

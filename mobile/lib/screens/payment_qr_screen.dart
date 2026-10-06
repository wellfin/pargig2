import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/api_client.dart';
import '../api/home_api.dart';
import '../state/auth_state.dart';
import 'payment_status_screen.dart';

/// Args for Navigator.pushNamed('/payment-qr', ...).
class PaymentQrArgs {
  final String jobId;
  final num? amount;
  final String? jobTitle;
  final String? clientName;
  const PaymentQrArgs({
    required this.jobId,
    this.amount,
    this.jobTitle,
    this.clientName,
  });
}

/// Figma "Payment / BHIM UPI" — shown after the worker taps Request
/// to Pay on /payment-request with UPI selected. Renders a scannable
/// UPI deeplink QR (`upi://pay?pa=...&pn=...&am=...&cu=INR`) the
/// client can scan with any UPI app, the worker's merchant info
/// (name + a Q-prefixed terminal id), and the same Cash / UPI /
/// Card chooser at the bottom — tapping a different method pops
/// back to /payment-request so the worker can switch.
class PaymentQrScreen extends StatefulWidget {
  const PaymentQrScreen({super.key});

  @override
  State<PaymentQrScreen> createState() => _PaymentQrScreenState();
}

class _PaymentQrScreenState extends State<PaymentQrScreen> {
  PaymentQrArgs? _args;

  // Gateway order backing this QR. The server builds the pay URI so the
  // amount and payee can't drift from what will actually be settled.
  String? _orderId;
  String? _payUri;
  bool _isDummyGateway = false;
  bool _confirming = false;
  String? _orderError;

  Timer? _poll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is PaymentQrArgs) {
      setState(() => _args = raw);
      _openOrder(raw.jobId);
      _startPolling(raw.jobId);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _openOrder(String jobId) async {
    try {
      final order = await HomeApi.createPaymentOrder(jobId);
      if (!mounted) return;
      setState(() {
        _orderId = (order['orderId'] ?? '').toString();
        final uri = (order['payUri'] ?? '').toString();
        _payUri = uri.isEmpty ? null : uri;
        _isDummyGateway = order['isDummy'] == true;
        _orderError = null;
      });
    } catch (e) {
      if (!mounted) return;
      // The QR still renders from locally-known details, so the client can
      // pay by scanning even if the order call failed.
      setState(
        () => _orderError = e is ApiException ? e.message : e.toString(),
      );
    }
  }

  /// Watches for the payment landing, whether it was confirmed in-app or
  /// settled by the client from their own side.
  void _startPolling(String jobId) {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      try {
        final job = await HomeApi.jobById(jobId);
        if (!mounted) return;
        if (job['paymentReleasedAt'] != null) _goToReceipt(job);
      } catch (_) {
        // Next tick retries.
      }
    });
  }

  /// Stand-in for the client actually paying. Only offered while the
  /// backend runs the dummy gateway — with a real PSP the confirmation
  /// arrives from the provider and this control disappears.
  Future<void> _markPaid() async {
    final args = _args;
    final orderId = _orderId;
    if (args == null || orderId == null || orderId.isEmpty || _confirming) {
      return;
    }
    setState(() {
      _confirming = true;
      _orderError = null;
    });
    try {
      await HomeApi.confirmPaymentOrder(args.jobId, orderId: orderId);
      if (!mounted) return;
      final job = await HomeApi.jobById(args.jobId);
      if (!mounted) return;
      _goToReceipt(job);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _orderError = e is ApiException ? e.message : e.toString();
      });
    }
  }

  void _goToReceipt(Map<String, dynamic> job) {
    if (!mounted) return;
    _poll?.cancel();
    final args = _args;
    if (args == null) return;
    final giver = job['jobgiver'] is Map ? job['jobgiver'] as Map : const {};
    final price = (job['finalPrice'] ?? job['proposedBudget'] ?? 0) as num;
    final tip = (job['tip'] ?? 0) as num;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/payment-status',
      (_) => false,
      arguments: PaymentStatusArgs(
        jobId: args.jobId,
        jobTitle: (job['title'] ?? args.jobTitle ?? 'Job').toString(),
        workerName:
            (job['selectedJobtaker'] is Map
                    ? (job['selectedJobtaker'] as Map)['name']
                    : null)
                ?.toString() ??
            'Worker',
        amount: (args.amount ?? (price + tip)).toDouble(),
        methodLabel: 'UPI',
        isCod: false,
        role: PaymentStatusRole.payee,
        clientName: (giver['name'] ?? args.clientName ?? 'Client').toString(),
      ),
    );
  }

  String _workerName(AuthState auth) {
    final n = (auth.user?['name'] ?? '').toString().trim();
    return n.isEmpty ? 'Pargig Worker' : n;
  }

  String _workerUpi(AuthState auth) {
    final upi = (auth.user?['upiId'] ?? '').toString().trim();
    if (upi.isNotEmpty && upi.contains('@')) return upi;
    // Fallback so the QR is at least scannable in demo builds before
    // workers set a real VPA on their profile.
    final id = (auth.user?['_id'] ?? '').toString();
    final tail = id.length >= 8 ? id.substring(id.length - 8) : id;
    return 'pargig.$tail@ybl';
  }

  /// Stable-looking merchant id derived from the jobId so the screen
  /// renders the same Q-number on every visit for the same job.
  String _merchantId(String jobId) {
    if (jobId.isEmpty) return 'Q00000000';
    final tail = jobId.length >= 8 ? jobId.substring(jobId.length - 8) : jobId;
    final digits = tail.codeUnits.map((c) => (c % 10).toString()).join();
    return 'Q${digits.padLeft(8, '0').substring(0, 8)}';
  }

  String _upiPayload({
    required String payeeVpa,
    required String payeeName,
    num? amount,
    required String note,
  }) {
    final params = <String, String>{
      'pa': payeeVpa,
      'pn': payeeName,
      'cu': 'INR',
      'tn': note,
    };
    if (amount != null) params['am'] = amount.toStringAsFixed(2);
    final qs = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
    return 'upi://pay?$qs';
  }

  void _switchMethod(String method) {
    // UPI tab is the one we're already on — no-op.
    if (method == 'upi') return;
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final args = _args;
    final jobId = args?.jobId ?? '';
    final payeeName = _workerName(auth);
    final payeeVpa = _workerUpi(auth);
    final amount = args?.amount;
    final note =
        'Pargig job ${jobId.isEmpty ? '' : '#${jobId.substring(0, jobId.length.clamp(0, 6))}'}'
            .trim();

    // Prefer the URI the gateway issued: it's tied to the order that will
    // actually be settled. The locally-built one is a fallback so the QR
    // still scans if the order call failed.
    final upi =
        _payUri ??
        _upiPayload(
          payeeVpa: payeeVpa,
          payeeName: payeeName,
          amount: amount,
          note: note,
        );

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                const SizedBox(height: 6),
                const _BhimUpiBadge(),
                const SizedBox(height: 18),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFE5E7EB),
                        width: 0.8,
                      ),
                    ),
                    child: QrImageView(
                      data: upi,
                      version: QrVersions.auto,
                      size: 230,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF101828),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    payeeName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    _merchantId(jobId),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF374151),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                const Center(
                  child: Text(
                    'Terminal 1',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ),
                if (amount != null) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEDD4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text(
                        '₹${amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFF6900),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _waitingRow(),
                if (_isDummyGateway) ...[
                  const SizedBox(height: 14),
                  _simulateButton(),
                ],
                if (_orderError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _orderError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _methodChooser(),
        ],
      ),
    );
  }

  /// The screen keeps watching for the payment in the background, so the
  /// worker doesn't have to do anything once the client scans.
  Widget _waitingRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B7280)),
          ),
        ),
        SizedBox(width: 10),
        Text(
          'Waiting for payment…',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }

  /// Testing affordance for the stand-in gateway: settles the job as if
  /// the client had paid, so the full workflow can be walked end to end.
  /// Rendered only when the backend reports it's running the dummy
  /// provider — wiring a real PSP removes it without a code change here.
  Widget _simulateButton() {
    return Column(
      children: [
        SizedBox(
          height: 46,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _confirming ? null : _markPaid,
            icon: _confirming
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF16A34A),
                      ),
                    ),
                  )
                : const Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: Color(0xFF16A34A),
                  ),
            label: Text(
              _confirming ? 'Confirming…' : 'Mark as paid (test)',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF16A34A),
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFF0FDF4),
              side: const BorderSide(color: Color(0xFF86EFAC), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Test gateway — no real money moves.',
          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
      ],
    );
  }

  Widget _methodChooser() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: const [
                Text(
                  'Payment Method ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
                Text(
                  '* ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF6900),
                  ),
                ),
                Text(
                  '(Required)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF6900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MethodTile(
                    icon: Icons.currency_rupee,
                    label: 'Cash',
                    selected: false,
                    onTap: () => _switchMethod('cash'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MethodTile(
                    icon: Icons.smartphone,
                    label: 'UPI',
                    selected: true,
                    onTap: () => _switchMethod('upi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MethodTile(
                    icon: Icons.credit_card,
                    label: 'Card',
                    selected: false,
                    onTap: () => _switchMethod('card'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF408EE0)),
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 8,
        16,
        12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: const Color(0x33FFFFFF),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onBack,
                child: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Payment',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Text-based BHIM UPI badge — matches the Figma logo without an
/// image asset. Two-tone wordmark: dark BHIM, orange ▶ separator,
/// dark UPI, with an orange underline running the full width.
class _BhimUpiBadge extends StatelessWidget {
  const _BhimUpiBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'BHIM',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101828),
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.play_arrow, size: 18, color: Color(0xFFFF6900)),
              SizedBox(width: 4),
              Text(
                'UPI',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101828),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(width: 110, height: 2, color: const Color(0xFFFF6900)),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MethodTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF408EE0) : const Color(0xFFE5E7EB),
            width: selected ? 1.6 : 0.8,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? const Color(0xFF408EE0)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected
                    ? const Color(0xFF408EE0)
                    : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

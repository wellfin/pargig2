import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/auth_state.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is PaymentQrArgs) {
      setState(() => _args = raw);
    }
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
    final digits = tail.codeUnits
        .map((c) => (c % 10).toString())
        .join();
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
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
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
    final note = 'Pargig job ${jobId.isEmpty ? '' : '#${jobId.substring(0, jobId.length.clamp(0, 6))}'}'
        .trim();

    final upi = _upiPayload(
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
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
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
              ],
            ),
          ),
          _methodChooser(),
        ],
      ),
    );
  }

  Widget _methodChooser() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
          ),
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
                child: const Icon(Icons.arrow_back,
                    size: 18, color: Colors.white),
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
              Icon(Icons.play_arrow,
                  size: 18, color: Color(0xFFFF6900)),
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
          Container(
            width: 110,
            height: 2,
            color: const Color(0xFFFF6900),
          ),
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
            color: selected
                ? const Color(0xFF408EE0)
                : const Color(0xFFE5E7EB),
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

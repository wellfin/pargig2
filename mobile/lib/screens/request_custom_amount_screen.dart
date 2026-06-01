import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'request_sent_screen.dart';

/// Args passed via `Navigator.pushNamed('/request-custom-amount', ...)`.
class RequestCustomAmountArgs {
  final String jobId;
  final String jobTitle;
  final num originalAmount;
  final String? category; // e.g. "Cleaning" — shown as a tag
  final String? clientName; // e.g. "Priya Sharma"
  final bool isUrgent;

  const RequestCustomAmountArgs({
    required this.jobId,
    required this.jobTitle,
    required this.originalAmount,
    this.category,
    this.clientName,
    this.isUrgent = false,
  });
}

/// Full-screen "Request Custom Amount" module from the Figma frame.
/// Lets the user pick from quick suggestions (±10% / ±20% of the
/// original amount) or type their own number, write an explanatory
/// message, and submit to `POST /api/jobs/:id/interest`.
class RequestCustomAmountScreen extends StatefulWidget {
  const RequestCustomAmountScreen({super.key});

  @override
  State<RequestCustomAmountScreen> createState() =>
      _RequestCustomAmountScreenState();
}

class _RequestCustomAmountScreenState
    extends State<RequestCustomAmountScreen> {
  RequestCustomAmountArgs? _args;
  final _amountCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;
  int _messageLen = 0;
  static const _maxMessage = 500;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is RequestCustomAmountArgs) {
      _args = raw;
      // Seed the amount field with the suggested price so users can
      // edit from there.
      _amountCtrl.text = raw.originalAmount.toInt().toString();
    }
    _messageCtrl.addListener(() {
      if (mounted) setState(() => _messageLen = _messageCtrl.text.length);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  List<_Suggestion> _suggestions(num original) {
    final base = original.toDouble();
    return [
      _Suggestion(pct: -20, value: (base * 0.80).round()),
      _Suggestion(pct: -10, value: (base * 0.90).round()),
      _Suggestion(pct: 10, value: (base * 1.10).round()),
      _Suggestion(pct: 20, value: (base * 1.20).round()),
    ];
  }

  Future<void> _submit() async {
    final args = _args;
    if (args == null || _submitting) return;
    final amountStr = _amountCtrl.text.trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Add a short message explaining your request');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.post('/jobs/${args.jobId}/interest', {
        'proposedPrice': amount,
        'message': message,
      });
      if (!mounted) return;
      // Show the dedicated "Request Sent!" confirmation (with the
      // chosen amount baked into the message), then return to /home.
      await Navigator.pushReplacementNamed(
        context,
        '/request-sent',
        arguments: RequestSentArgs(customAmount: amount),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  void _applySuggestion(int value) {
    _amountCtrl.text = value.toString();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.6,
        scrolledUnderElevation: 0.6,
        foregroundColor: const Color(0xFF101828),
        title: const Text(
          'Request Custom Amount',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF101828),
          ),
        ),
      ),
      body: args == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Couldn't load the job — go back and try again.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                ),
              ),
            )
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _jobSummaryCard(args),
                          const SizedBox(height: 14),
                          _whyCard(),
                          const SizedBox(height: 18),
                          const _SectionLabel('Quick Suggestions'),
                          const SizedBox(height: 10),
                          _suggestionsGrid(args.originalAmount),
                          const SizedBox(height: 18),
                          const _SectionLabel('Your Requested Amount *'),
                          const SizedBox(height: 8),
                          _amountField(),
                          const SizedBox(height: 18),
                          const _SectionLabel('Message to Client *'),
                          const SizedBox(height: 8),
                          _messageField(),
                          const SizedBox(height: 4),
                          _charCounter(),
                          const SizedBox(height: 16),
                          _tipsCard(),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _submitting ? null : _submit,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(
                                color: Color(0xFFFF6900),
                                width: 1.4,
                              ),
                              foregroundColor: const Color(0xFFFF6900),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        Color(0xFFFF6900),
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Send Request to Client',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Client will review and respond to your request',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ----- sub-widgets ----------------------------------------------------

  Widget _jobSummaryCard(RequestCustomAmountArgs args) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            args.isUrgent ? 'Urgent: ${args.jobTitle}' : args.jobTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (args.clientName != null && args.clientName!.isNotEmpty)
                Expanded(
                  child: Text(
                    'Client: ${args.clientName}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4A5565),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (args.category != null && args.category!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD4),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    args.category!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFF54900),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Original Amount',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '₹${args.originalAmount.toInt()}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
        ],
      ),
    );
  }

  Widget _whyCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDBEAFE), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF408EE0)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Why customize?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF408EE0),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'If you think the job requires more/less effort, '
                  'request a fair amount with a clear explanation',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E3A8A),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _suggestionsGrid(num original) {
    final items = _suggestions(original);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 68,
      ),
      itemBuilder: (_, i) {
        final s = items[i];
        final isDiscount = s.pct < 0;
        final pctColor =
            isDiscount ? const Color(0xFFE7000B) : const Color(0xFF16A34A);
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _applySuggestion(s.value),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFE5E7EB),
                  width: 0.8,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '₹${s.value}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.pct > 0 ? '+' : ''}${s.pct}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: pctColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _amountField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          const Text(
            '₹',
            style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF101828),
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '800',
                hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: TextField(
        controller: _messageCtrl,
        minLines: 4,
        maxLines: 8,
        maxLength: _maxMessage,
        style: const TextStyle(fontSize: 14, color: Color(0xFF101828)),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          counterText: '',
          hintText:
              "Explain why you're requesting this amount... "
              "(e.g., 'Based on the job description, I'll need additional "
              "materials and 2 extra hours')",
          hintStyle: TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _charCounter() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '$_messageLen/$_maxMessage characters',
        style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
      ),
    );
  }

  Widget _tipsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD9B3), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  size: 16, color: Color(0xFF7E2A0C)),
              SizedBox(width: 6),
              Text(
                'Tips for Better Approval',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7E2A0C),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _Tip('Be specific about what\'s included in your price'),
          _Tip('Mention materials, time, or expertise required'),
          _Tip('Stay professional and polite'),
          _Tip('Be reasonable with your pricing'),
        ],
      ),
    );
  }
}

class _Suggestion {
  final int pct;
  final int value;
  const _Suggestion({required this.pct, required this.value});
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF101828),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '•',
            style: TextStyle(
              color: Color(0xFFFF6900),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF7E2A0C),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

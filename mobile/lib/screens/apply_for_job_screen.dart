import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'job_accepted_screen.dart';

/// Apply-for-Job screen — Figma "Apply for Job" frame. Reached by tapping
/// the Apply button on /job-details. Posts to
/// `POST /api/jobs/:id/interest` with `{ proposedPrice, message }`, then
/// pops back with `true` so the previous screen can refresh.
class ApplyForJobArgs {
  final String jobId;
  final String jobTitle;
  final num suggestedPrice; // job.proposedBudget — used as placeholder
  // Tip the poster added on the job — display-only, kept separate from
  // suggestedPrice so the raw base price is still what's submitted as
  // proposedPrice on apply.
  final num tip;
  // 'fixed' or 'open'. When the poster set a Fixed Price, the job-taker
  // can't negotiate, so the "Your Proposal" section is hidden. The
  // proposal is only shown when the poster is 'open' to offers.
  final String priceMode;
  final bool isUrgent;

  const ApplyForJobArgs({
    required this.jobId,
    required this.jobTitle,
    required this.suggestedPrice,
    this.tip = 0,
    this.priceMode = 'open',
    this.isUrgent = false,
  });
}

class ApplyForJobScreen extends StatefulWidget {
  const ApplyForJobScreen({super.key});

  @override
  State<ApplyForJobScreen> createState() => _ApplyForJobScreenState();
}

class _ApplyForJobScreenState extends State<ApplyForJobScreen> {
  ApplyForJobArgs? _args;
  final _proposal = TextEditingController();
  final _price = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is ApplyForJobArgs) {
      _args = raw;
      // Prefill the offer with the poster's figure rather than showing it
      // as a grey hint over an empty box.
      //
      // With a hint the number looked like it was already the offer, so
      // workers tapped Apply without typing — and a blank field silently
      // submits the poster's own price. That is why an open-to-offers job
      // sometimes kept the original amount: the worker never actually
      // named one. Prefilled, the number on screen IS the number sent,
      // and changing it is obviously possible.
      if (raw.priceMode != 'fixed' && raw.suggestedPrice > 0) {
        _price.text = raw.suggestedPrice.toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _proposal.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final args = _args;
    if (args == null || _submitting) return;
    // Proposal is only collected when the poster is open to offers.
    // For Fixed Price jobs the proposal section is hidden, so don't
    // require a message.
    final bool showProposal = args.priceMode != 'fixed';
    final message = _proposal.text.trim();
    if (showProposal && message.isEmpty) {
      setState(() => _error = 'Tell the poster why you’re a fit');
      return;
    }
    final priceStr = _price.text.trim();
    final num price = priceStr.isEmpty
        ? args.suggestedPrice
        : (double.tryParse(priceStr) ?? -1);
    // Zero was accepted here and then silently became the poster's price
    // on the backend (`proposedPrice || job.proposedBudget`), so a worker
    // who typed 0 saw their offer ignored with no explanation.
    if (price <= 0) {
      setState(
        () => _error = showProposal
            ? 'Enter the amount you want for this job'
            : 'Enter a valid price',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ApiClient.post('/jobs/${args.jobId}/interest', {
        'proposedPrice': price,
        'message': message,
      });
      if (!mounted) return;
      // Replace the apply screen with the "Job Accepted!" arrival-type
      // chooser. From there Confirm & Continue clears the stack to /home.
      Navigator.pushReplacementNamed(
        context,
        '/job-accepted',
        arguments: JobAcceptedArgs(
          jobId: args.jobId,
          jobTitle: args.jobTitle,
          isUrgent: args.isUrgent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: () => Navigator.maybePop(context)),
            if (args == null)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "Couldn't load this job — go back and try again.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Text(
                      args.jobTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      args.priceMode == 'fixed'
                          ? 'Review and submit your application'
                          : 'Share your proposal and pricing',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF4A5565),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // "Your Proposal" only shows when the poster is open to
                    // offers. Fixed Price jobs skip it entirely.
                    if (args.priceMode != 'fixed') ...[
                      const _Label('Your Proposal'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: TextField(
                          controller: _proposal,
                          minLines: 4,
                          maxLines: 8,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF101828),
                          ),
                          decoration: const InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Why are you the best fit for this job?',
                            hintStyle: TextStyle(
                              color: Color(0xFF9CA3AF),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    // Price input only for "Open to Offers" jobs — the worker
                    // proposes their price. Fixed-price jobs hide it; the
                    // worker applies at the poster's set price.
                    if (args.priceMode != 'fixed') ...[
                      const _Label('Your Price'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '₹',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _price,
                                keyboardType: TextInputType.number,
                                maxLength: 5,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(5),
                                ],
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF101828),
                                ),
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  counterText: '',
                                  border: InputBorder.none,
                                  hintText: args.suggestedPrice.toStringAsFixed(
                                    0,
                                  ),
                                  hintStyle: const TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        args.tip > 0
                            ? 'Suggested: ₹${args.suggestedPrice.toStringAsFixed(0)}'
                                  ' + ₹${args.tip.toStringAsFixed(0)} tip'
                                  ' = ₹${(args.suggestedPrice + args.tip).toStringAsFixed(0)}'
                            : 'Suggested: ₹${args.suggestedPrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ] else ...[
                      const _Label('Job Price'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              '₹',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              (args.suggestedPrice + args.tip).toStringAsFixed(
                                0,
                              ),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF101828),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'fixed',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            if (args.tip > 0) ...[
                              const SizedBox(width: 8),
                              Text(
                                '(incl. ₹${args.tip.toStringAsFixed(0)} tip)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Fixed-price job — submit your application to apply at '
                        'this price.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
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
            // SafeArea(top:false) reserves the system nav-bar inset so the
            // button is never clipped by the gesture bar on tall phones.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: _SubmitButton(
                  loading: _submitting,
                  onTap: args == null || _submitting ? null : _submit,
                ),
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          const Text(
            'Apply for Job',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF101828),
        height: 1.4,
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;
  const _SubmitButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
          foregroundColor: const Color(0xFF101828),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF101828)),
                ),
              )
            : const Text(
                'Submit Application',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                ),
              ),
      ),
    );
  }
}

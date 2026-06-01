import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../state/auth_state.dart';

/// Args for Navigator.pushNamed('/select-payment-method', ...).
class SelectPaymentMethodArgs {
  final num amount;
  const SelectPaymentMethodArgs({required this.amount});
}

/// Figma "Select Payment Method" — reached from Add Money once a
/// quick-add or custom amount has been picked. Lists wallet apps
/// (Paytm/PhonePe/Google Pay/Amazon Pay/Freecharge) above a saved-
/// cards group with an "+ Add Card" affordance. Pops with `true`
/// after the (mock) top-up completes so the caller stack refreshes.
///
/// Real gateway hand-off isn't wired yet — the Continue button still
/// calls the existing /payments/wallet/topup mock-credit endpoint
/// with the selected amount, then surfaces the chosen method label
/// in the success snackbar so QA can verify which row was active.
class SelectPaymentMethodScreen extends StatefulWidget {
  const SelectPaymentMethodScreen({super.key});

  @override
  State<SelectPaymentMethodScreen> createState() =>
      _SelectPaymentMethodScreenState();
}

class _SelectPaymentMethodScreenState extends State<SelectPaymentMethodScreen> {
  SelectPaymentMethodArgs? _args;

  static const List<_Wallet> _wallets = [
    _Wallet(
      id: 'paytm',
      label: 'Paytm Wallet & UPI',
      accent: Color(0xFF00B9F1),
      mono: 'P',
    ),
    _Wallet(
      id: 'phonepe',
      label: 'PhonePe',
      accent: Color(0xFF5F259F),
      mono: 'P',
    ),
    _Wallet(
      id: 'gpay',
      label: 'Google Pay',
      accent: Color(0xFF4285F4),
      mono: 'G',
    ),
    _Wallet(
      id: 'amazonpay',
      label: 'Amazon Pay',
      accent: Color(0xFFFF9900),
      mono: 'a',
    ),
    _Wallet(
      id: 'freecharge',
      label: 'Freecharge',
      accent: Color(0xFFFFB400),
      mono: 'f',
    ),
  ];

  // Saved cards — placeholder list. Replace with `/payments/cards` once
  // the saved-card service exists; the UI binds to the same shape.
  static const List<_Card> _cards = [
    _Card(
      id: 'card1',
      bank: 'HDFC Debit Card',
      last4: '9232',
      holder: 'Pawan Kumar Prakash',
      expires: '12/2020',
    ),
    _Card(
      id: 'card2',
      bank: 'HDFC Debit Card',
      last4: '9232',
      holder: 'Pawan Kumar Prakash',
      expires: '12/2020',
    ),
    _Card(
      id: 'card3',
      bank: 'HDFC Debit Card',
      last4: '9232',
      holder: 'Pawan Kumar Prakash',
      expires: '12/2020',
    ),
  ];

  String? _selectedId;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is SelectPaymentMethodArgs) {
      setState(() => _args = raw);
    }
  }

  String? get _selectedLabel {
    if (_selectedId == null) return null;
    for (final w in _wallets) {
      if (w.id == _selectedId) return w.label;
    }
    for (final c in _cards) {
      if (c.id == _selectedId) return '${c.bank} ****${c.last4}';
    }
    return null;
  }

  Future<void> _continue() async {
    final amount = _args?.amount ?? 0;
    final method = _selectedLabel;
    if (amount <= 0 || method == null || _busy) return;
    final auth = context.read<AuthState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.post('/payments/wallet/topup', {'amount': amount});
      await auth.refreshMe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ₹${amount.toInt()} via $method'),
        ),
      );
      // Pop twice — once for this screen, once for AddMoney — back
      // to the Wallet so the balance / transactions refresh.
      Navigator.pop(context, true);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  void _onAddCard() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add card — coming soon'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  void _onEditCard(_Card card) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Edit ${card.bank} ****${card.last4} — coming soon'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = !_busy && _selectedId != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          _Header(onBack: () => Navigator.maybePop(context)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
              children: [
                _SectionLabel('Wallet'),
                const SizedBox(height: 6),
                _Group(
                  children: List.generate(_wallets.length, (i) {
                    final w = _wallets[i];
                    final isLast = i == _wallets.length - 1;
                    return Column(
                      children: [
                        _WalletRow(
                          wallet: w,
                          selected: _selectedId == w.id,
                          onTap: () => setState(() => _selectedId = w.id),
                        ),
                        if (!isLast)
                          const Divider(
                            height: 1,
                            thickness: 0.6,
                            color: Color(0xFFF1F5F9),
                            indent: 64,
                          ),
                      ],
                    );
                  }),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Credit / Debit Cards',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      GestureDetector(
                        onTap: _onAddCard,
                        child: const Text(
                          '+ Add Card',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                _Group(
                  children: List.generate(_cards.length, (i) {
                    final c = _cards[i];
                    final isLast = i == _cards.length - 1;
                    return Column(
                      children: [
                        _CardRow(
                          card: c,
                          selected: _selectedId == c.id,
                          onTap: () => setState(() => _selectedId = c.id),
                          onEdit: () => _onEditCard(c),
                        ),
                        if (!isLast)
                          const Divider(
                            height: 1,
                            thickness: 0.6,
                            color: Color(0xFFF1F5F9),
                            indent: 64,
                          ),
                      ],
                    );
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          _Footer(
            enabled: canContinue,
            busy: _busy,
            onTap: _continue,
          ),
        ],
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
      decoration: const BoxDecoration(color: Color(0xFF2D2D2D)),
      padding: EdgeInsets.fromLTRB(
        4, MediaQuery.of(context).padding.top + 6, 16, 12,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          const Text(
            'Select Payment Method',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      child: Column(children: children),
    );
  }
}

class _WalletRow extends StatelessWidget {
  final _Wallet wallet;
  final bool selected;
  final VoidCallback onTap;
  const _WalletRow({
    required this.wallet,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              _BrandIcon(label: wallet.mono, color: wallet.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  wallet.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF101828),
                  ),
                ),
              ),
              _RadioDot(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  final _Card card;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  const _CardRow({
    required this.card,
    required this.selected,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF60A5FA), Color(0xFFA78BFA)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.credit_card,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${card.bank} ****${card.last4}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.holder,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    Text(
                      'Expires ${card.expires}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onEdit,
                child: Row(
                  children: const [
                    Icon(Icons.edit_outlined,
                        size: 14, color: Color(0xFFDC2626)),
                    SizedBox(width: 2),
                    Text(
                      'Edit',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _RadioDot(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandIcon extends StatelessWidget {
  final String label;
  final Color color;
  const _BrandIcon({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 0.8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1,
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFFFF6900) : const Color(0xFFD1D5DB),
          width: 1.6,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFFFF6900),
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

class _Footer extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  const _Footer({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? const Color(0xFFFF6900) : const Color(0xFFD1D5DB);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB), width: 0.6),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SizedBox(
          height: 50,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: enabled ? onTap : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: BorderSide(color: fg, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFFFF6900)),
                    ),
                  )
                : Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Wallet {
  final String id;
  final String label;
  final Color accent;
  final String mono;
  const _Wallet({
    required this.id,
    required this.label,
    required this.accent,
    required this.mono,
  });
}

class _Card {
  final String id;
  final String bank;
  final String last4;
  final String holder;
  final String expires;
  const _Card({
    required this.id,
    required this.bank,
    required this.last4,
    required this.holder,
    required this.expires,
  });
}

import 'package:flutter/material.dart';

import '../api/issues_api.dart';
import 'need_help_describe_screen.dart' show DescribeIssueArgs;

/// What Need Help is being raised about.
class NeedHelpArgs {
  final String jobId;
  final String jobTitle;

  /// Which side is complaining. Decides which catalogue of issue types
  /// is offered — a giver's list and a worker's list share almost
  /// nothing, because they are complaints about opposite people.
  final bool isJobGiver;

  const NeedHelpArgs({
    required this.jobId,
    required this.jobTitle,
    this.isJobGiver = true,
  });
}

/// Need Help, step 1 — Select Issue.
///
/// Fixed categories rather than a free-text box first: the category
/// decides which sub-issues the next step offers, and support routes on
/// it. The free text comes after, when there is something to attach it
/// to.
///
/// Six categories for a job giver, seven for a job taker.
class NeedHelpTypeScreen extends StatefulWidget {
  const NeedHelpTypeScreen({super.key});

  @override
  State<NeedHelpTypeScreen> createState() => _NeedHelpTypeScreenState();
}

class _NeedHelpTypeScreenState extends State<NeedHelpTypeScreen> {
  NeedHelpArgs? _args;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is NeedHelpArgs) _args = raw;
  }

  Future<void> _pick(IssueType type) async {
    final args = _args;
    if (args == null) return;
    final filed = await Navigator.pushNamed(
      context,
      '/need-help-describe',
      arguments: DescribeIssueArgs(
        jobId: args.jobId,
        jobTitle: args.jobTitle,
        issueType: type,
      ),
    );
    // Carry the result back to Job Details so it can flip its button
    // without refetching.
    if (filed == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final types = issueTypesFor(isJobGiver: _args?.isJobGiver ?? true);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF101828),
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleSpacing: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Need Help',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101828),
              ),
            ),
            Text(
              'Select Issue',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              'SELECT ISSUE TYPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEDEFF3)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < types.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 0.7,
                      indent: 58,
                      color: Color(0xFFF1F5F9),
                    ),
                  _TypeRow(type: types[i], onTap: () => _pick(types[i])),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  final IssueType type;
  final VoidCallback onTap;
  const _TypeRow({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: type.iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: Icon(type.icon, size: 17, color: type.iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101828),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      type.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 19,
                color: Color(0xFFCBD5E1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

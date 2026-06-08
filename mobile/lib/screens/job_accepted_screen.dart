import 'package:flutter/material.dart';

import 'immediate_job_active_screen.dart';
import 'important_notice_dialog.dart';

/// Args for Navigator.pushNamed('/job-accepted', arguments: ...)
class JobAcceptedArgs {
  final String jobId;
  final String jobTitle;
  final String? locationText; // e.g. "Koramangala, Bangalore"
  final DateTime? scheduledAt;
  final bool isUrgent;

  const JobAcceptedArgs({
    required this.jobId,
    required this.jobTitle,
    this.locationText,
    this.scheduledAt,
    this.isUrgent = false,
  });
}

/// "Job Accepted!" screen shown after a job-taker accepts an urgent
/// job from the popup OR submits an Apply-for-Job application. Lets
/// the user pick how they'll arrive (Immediate vs Scheduled) and
/// confirms. On Confirm, clears the stack back to /home.
class JobAcceptedScreen extends StatefulWidget {
  const JobAcceptedScreen({super.key});

  @override
  State<JobAcceptedScreen> createState() => _JobAcceptedScreenState();
}

class _JobAcceptedScreenState extends State<JobAcceptedScreen> {
  JobAcceptedArgs? _args;
  // 0 = Immediate, 1 = Scheduled. The available option is driven by
  // whether the job was marked Urgent: urgent jobs only allow Immediate
  // arrival, non-urgent jobs only allow Scheduled arrival.
  int _arrivalIndex = 0;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  bool _showMissingFieldsError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is JobAcceptedArgs) {
      _args = raw;
      // Urgent => Immediate only (0); not urgent => Scheduled only (1).
      _arrivalIndex = raw.isUrgent ? 0 : 1;
    }
  }

  String _formatTime(DateTime dt) {
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ap';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _scheduledDate ?? _args?.scheduledAt ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _scheduledDate = picked;
        _showMissingFieldsError = false;
      });
    }
  }

  Future<void> _pickTime() async {
    final initial = _scheduledTime ??
        (_args?.scheduledAt != null
            ? TimeOfDay.fromDateTime(_args!.scheduledAt!)
            : TimeOfDay.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null && mounted) {
      setState(() {
        _scheduledTime = picked;
        _showMissingFieldsError = false;
      });
    }
  }

  Future<void> _confirm() async {
    final args = _args!;
    // For Scheduled, both date AND time are required before we open
    // the Important Notice modal. Show inline red helper text on the
    // button row instead of throwing the user into the modal.
    if (_arrivalIndex == 1 &&
        (_scheduledDate == null || _scheduledTime == null)) {
      setState(() => _showMissingFieldsError = true);
      return;
    }
    final acknowledged = await ImportantNoticeDialog.show(context);
    if (!mounted || !acknowledged) return;
    // Build the countdown duration for the active screen.
    //   - Immediate: 15 minutes (the default in ImmediateJobArgs)
    //   - Scheduled: from NOW until the user's chosen date+time. The
    //     scheduled screen reuses the same countdown widget; the only
    //     difference is the starting value.
    int? reachSeconds;
    DateTime? targetDt;
    if (_arrivalIndex == 1) {
      final d = _scheduledDate!;
      final t = _scheduledTime!;
      targetDt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      final diff = targetDt.difference(DateTime.now()).inSeconds;
      // Clamp to 0 if user somehow picked a past time; the active
      // screen will show "Time Up" right away in that case.
      reachSeconds = diff < 0 ? 0 : diff;
    }
    Navigator.pushReplacementNamed(
      context,
      '/immediate-job-active',
      arguments: ImmediateJobArgs(
        jobId: args.jobId,
        jobTitle: args.jobTitle,
        locationText: args.locationText,
        // Scheduled path passes the chosen target time so the
        // summary card reflects what the user picked, not the job's
        // original scheduledAt.
        scheduledAt: targetDt ?? args.scheduledAt,
        isUrgent: args.isUrgent,
        reachWithinSeconds: reachSeconds ?? 15 * 60,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = _args;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: args == null
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
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
                children: [
                  // Green check + heading
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        color: Color(0xFFDCFCE7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_outline,
                        size: 52,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Job Accepted!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "You've successfully accepted this job",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Job summary card
                  _jobSummary(args),

                  const SizedBox(height: 22),
                  const Text(
                    'Choose your arrival type',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF101828),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Urgent jobs => show only the Immediate option.
                  if (args.isUrgent)
                    _ArrivalCard(
                      selected: _arrivalIndex == 0,
                      title: 'Immediate Job',
                      subtitle: 'Reach within 10-15 minutes',
                      iconBg: const Color(0xFFFF6900),
                      iconChild: const Icon(Icons.flash_on,
                          color: Colors.white, size: 18),
                      accent: Icons.flash_on,
                      accentColor: const Color(0xFFFF6900),
                      onTap: () => setState(() => _arrivalIndex = 0),
                    ),
                  // Non-urgent jobs => show only the Scheduled option.
                  if (!args.isUrgent)
                    _ArrivalCard(
                      selected: _arrivalIndex == 1,
                      title: 'Scheduled Job',
                      subtitle: _arrivalIndex == 1
                          ? 'Choose your arrival date & time'
                          : 'Reach before job start time',
                      iconBg: _arrivalIndex == 1
                          ? const Color(0xFF408EE0)
                          : const Color(0xFFF3F4F6),
                      iconChild: Icon(
                        Icons.calendar_today_outlined,
                        color: _arrivalIndex == 1
                            ? Colors.white
                            : const Color(0xFF6B7280),
                        size: 18,
                      ),
                      accent: Icons.event,
                      accentColor: const Color(0xFFFF6900),
                      tint: _arrivalIndex == 1
                          ? const Color(0xFFEFF6FF)
                          : null,
                      borderColor: _arrivalIndex == 1
                          ? const Color(0xFF408EE0)
                          : null,
                      selectedDotColor: _arrivalIndex == 1
                          ? const Color(0xFF408EE0)
                          : const Color(0xFFFF6900),
                      onTap: () => setState(() => _arrivalIndex = 1),
                    ),
                  if (_arrivalIndex == 1) ...[
                    const SizedBox(height: 14),
                    _SchedulePicker(
                      date: _scheduledDate,
                      time: _scheduledTime,
                      jobStart: args.scheduledAt,
                      onPickDate: _pickDate,
                      onPickTime: _pickTime,
                    ),
                  ],

                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _confirm,
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
                      child: const Text(
                        'Confirm & Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (_showMissingFieldsError) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Please select both date and time to continue',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFE7000B),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _jobSummary(JobAcceptedArgs args) {
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
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
              height: 1.3,
            ),
          ),
          if (args.locationText != null && args.locationText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('📍 ', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: Text(
                    args.locationText!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4A5565),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (args.scheduledAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time,
                    size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                Text(
                  _formatTime(args.scheduledAt!),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF4A5565),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrivalCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final Color iconBg;
  final Widget iconChild;
  final IconData accent;
  final Color accentColor;
  final VoidCallback onTap;
  // Optional overrides so the Scheduled card can tint blue when
  // selected (per Figma) while Immediate stays orange.
  final Color? tint; // background when selected
  final Color? borderColor; // border when selected
  final Color? selectedDotColor; // fill of the radio dot

  const _ArrivalCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.iconBg,
    required this.iconChild,
    required this.accent,
    required this.accentColor,
    required this.onTap,
    this.tint,
    this.borderColor,
    this.selectedDotColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTint = tint ?? const Color(0xFFFFF7ED);
    final effectiveBorder = borderColor ?? const Color(0xFFFF6900);
    final effectiveDot = selectedDotColor ?? const Color(0xFFFF6900);
    return Material(
      color: selected ? effectiveTint : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? effectiveBorder : const Color(0xFFE5E7EB),
              width: selected ? 1.4 : 0.8,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: iconChild,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(accent, size: 14, color: accentColor),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              // Right-side radio indicator
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? effectiveDot : const Color(0xFFD1D5DB),
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: effectiveDot,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SchedulePicker extends StatelessWidget {
  final DateTime? date;
  final TimeOfDay? time;
  final DateTime? jobStart;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  const _SchedulePicker({
    required this.date,
    required this.time,
    required this.jobStart,
    required this.onPickDate,
    required this.onPickTime,
  });

  String _dateLabel() {
    if (date == null) return 'DD/MM/YYYY';
    final d = date!.day.toString().padLeft(2, '0');
    final m = date!.month.toString().padLeft(2, '0');
    return '$d/$m/${date!.year}';
  }

  String _timeLabel() {
    if (time == null) return '--:-- AM';
    final h24 = time!.hour;
    final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final mm = time!.minute.toString().padLeft(2, '0');
    final ap = h24 < 12 ? 'AM' : 'PM';
    return '${h12.toString().padLeft(2, '0')} : $mm $ap';
  }

  String? _jobStartLabel() {
    if (jobStart == null) return null;
    final dt = jobStart!.toLocal();
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final mm = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ap';
  }

  @override
  Widget build(BuildContext context) {
    final js = _jobStartLabel();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Select Arrival Date & Time',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF408EE0),
            ),
          ),
          const SizedBox(height: 12),
          const _PickerLabel(text: 'Date', required: true),
          const SizedBox(height: 6),
          _PickerField(
            text: _dateLabel(),
            filled: date != null,
            onTap: onPickDate,
          ),
          const SizedBox(height: 12),
          const _PickerLabel(text: 'Time', required: true),
          const SizedBox(height: 6),
          _PickerField(
            text: _timeLabel(),
            filled: time != null,
            onTap: onPickTime,
          ),
          if (js != null) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFBFDBFE),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.access_time,
                          size: 14, color: Color(0xFF408EE0)),
                      SizedBox(width: 6),
                      Text(
                        'Job Start Time',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF408EE0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    js,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded,
                          size: 14, color: Color(0xFFCA8A04)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Arrive 5-10 minutes before this time',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF408EE0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickerLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _PickerLabel({required this.text, this.required = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF408EE0),
        ),
        children: [
          TextSpan(text: text),
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Color(0xFFE7000B)),
            ),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  final String text;
  final bool filled;
  final VoidCallback onTap;
  const _PickerField({
    required this.text,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFBFDBFE),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: filled
                  ? const Color(0xFF101828)
                  : const Color(0xFF9CA3AF),
            ),
          ),
        ),
      ),
    );
  }
}

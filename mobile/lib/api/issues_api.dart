import 'package:flutter/material.dart';

import 'api_client.dart';

/// One of the six choices on the Need Help "Select Issue" screen.
///
/// Display copy lives here rather than on the server: the icons and
/// colours are design decisions, and the machine value is the only part
/// both sides have to agree on.
class IssueType {
  final String value;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  const IssueType({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });
}

/// The six a JOB GIVER can choose: complaints about the work.
const kGiverIssueTypes = <IssueType>[
  IssueType(
    value: 'service_quality',
    title: 'Service Quality Issue',
    subtitle: 'Work not done properly or below expectations',
    icon: Icons.star_outline,
    iconColor: Color(0xFFF59E0B),
    iconBg: Color(0xFFFEF3C7),
  ),
  IssueType(
    value: 'payment',
    title: 'Payment Issue',
    subtitle: 'Problems with payment or charges',
    icon: Icons.credit_card_outlined,
    iconColor: Color(0xFF2563EB),
    iconBg: Color(0xFFDBEAFE),
  ),
  IssueType(
    value: 'worker_behavior',
    title: 'Worker Behavior',
    subtitle: 'Unprofessional or inappropriate behavior',
    icon: Icons.person_outline,
    iconColor: Color(0xFFE11D48),
    iconBg: Color(0xFFFFE4E6),
  ),
  IssueType(
    value: 'wrong_service',
    title: 'Wrong Service Provided',
    subtitle: 'Different service than what was booked',
    icon: Icons.build_outlined,
    iconColor: Color(0xFF7C3AED),
    iconBg: Color(0xFFEDE9FE),
  ),
  IssueType(
    value: 'safety',
    title: 'Safety Concern',
    subtitle: 'Safety related issue during the service',
    icon: Icons.gpp_maybe_outlined,
    iconColor: Color(0xFFDC2626),
    iconBg: Color(0xFFFEE2E2),
  ),
  IssueType(
    value: 'other',
    title: 'Other Issue',
    subtitle: 'Any other problem not listed above',
    icon: Icons.help_outline,
    iconColor: Color(0xFF6B7280),
    iconBg: Color(0xFFF3F4F6),
  ),
];

/// The seven a JOB TAKER can choose: complaints about the client.
///
/// A different catalogue rather than a filtered one — "Payment Issue"
/// means being overcharged to a giver and not being paid at all to a
/// worker, and one label cannot carry both.
const kTakerIssueTypes = <IssueType>[
  IssueType(
    value: 'payment_not_received',
    title: 'Payment Not Received',
    subtitle: 'Not paid, underpaid, or still waiting',
    icon: Icons.credit_card_outlined,
    iconColor: Color(0xFF2563EB),
    iconBg: Color(0xFFDBEAFE),
  ),
  IssueType(
    value: 'requirement_changed',
    title: 'Job Requirement Changed',
    subtitle: 'The work was not what was agreed',
    icon: Icons.star_outline,
    iconColor: Color(0xFFF59E0B),
    iconBg: Color(0xFFFEF3C7),
  ),
  IssueType(
    value: 'additional_work',
    title: 'Additional Work Requested',
    subtitle: 'Asked to do more than was booked',
    icon: Icons.person_outline,
    iconColor: Color(0xFFE11D48),
    iconBg: Color(0xFFFFE4E6),
  ),
  IssueType(
    value: 'access_not_provided',
    title: 'Material/Access Not Provided',
    subtitle: 'Could not start or finish the work',
    icon: Icons.build_outlined,
    iconColor: Color(0xFF7C3AED),
    iconBg: Color(0xFFEDE9FE),
  ),
  IssueType(
    value: 'giver_unavailable',
    title: 'Job Giver Unavailable',
    subtitle: 'Nobody there or not reachable',
    icon: Icons.gpp_maybe_outlined,
    iconColor: Color(0xFFDC2626),
    iconBg: Color(0xFFFEE2E2),
  ),
  IssueType(
    value: 'giver_behaviour',
    title: 'Behaviour/Safety Concern',
    subtitle: 'Unsafe, rude or inappropriate treatment',
    icon: Icons.help_outline,
    iconColor: Color(0xFF6B7280),
    iconBg: Color(0xFFF3F4F6),
  ),
  IssueType(
    value: 'other',
    title: 'Other Issue',
    subtitle: 'Any other problem not listed above',
    icon: Icons.help_outline,
    iconColor: Color(0xFF6B7280),
    iconBg: Color(0xFFF3F4F6),
  ),
];

/// The catalogue for whoever is looking.
List<IssueType> issueTypesFor({required bool isJobGiver}) =>
    isJobGiver ? kGiverIssueTypes : kTakerIssueTypes;

IssueType? issueTypeFor(String value, {bool isJobGiver = true}) {
  for (final t in issueTypesFor(isJobGiver: isJobGiver)) {
    if (t.value == value) return t;
  }
  return null;
}

/// The sub-issues offered under each type.
///
/// Mirrors the server's own list. The server filters anything it does not
/// recognise, so an out-of-date copy here can only ever offer too much,
/// never file something the type does not mean.
const kSubIssues = <String, List<String>>{
  // ---- job giver ----
  'service_quality': [
    'Work Not Completed',
    'Poor Quality Work',
    'Property Damage',
  ],
  'payment': [
    'Overcharged',
    'Charged Twice',
    'Refund Not Received',
    'Extra Charges Demanded',
  ],
  'worker_behavior': [
    'Rude Behaviour',
    'Arrived Late',
    'Did Not Arrive',
    'Unprofessional Conduct',
  ],
  'wrong_service': [
    'Different Service Performed',
    'Incomplete Scope',
    'Wrong Address Attended',
  ],
  'safety': [
    'Unsafe Work Practice',
    'Damage Risk Ignored',
    'Felt Unsafe',
    'No Safety Equipment',
  ],
  // ---- job taker ----
  'payment_not_received': [
    'Not Paid At All',
    'Paid Less Than Agreed',
    'Payment Still Pending',
  ],
  'requirement_changed': [
    'Different Work On Arrival',
    'Scope Increased',
    'Location Changed',
  ],
  'additional_work': [
    'Extra Work Without Pay',
    'Asked To Stay Longer',
    'Work Outside Agreement',
  ],
  'access_not_provided': [
    'No Materials Provided',
    'Could Not Enter Property',
    'No Power Or Water',
  ],
  'giver_unavailable': [
    'Nobody At The Location',
    'Not Reachable On Call',
    'Cancelled On Arrival',
  ],
  'giver_behaviour': [
    'Rude Behaviour',
    'Unsafe Conditions',
    'Felt Unsafe',
    'Threatened Or Harassed',
  ],

  // ---- shared ----
  'other': <String>[],
};

/// Need Help — a user's completed-job history and the issues they have
/// raised against it. Serves both sides; `isJobGiver` picks which.
class IssuesApi {
  IssuesApi._();

  /// Completed jobs for the signed-in user, each carrying any issue they
  /// have already raised against it.
  static Future<List<Map<String, dynamic>>> jobHistory({
    required bool isJobGiver,
  }) async {
    final res = await ApiClient.get(
      '/issues/job-history',
      query: {'role': isJobGiver ? 'jobgiver' : 'jobtaker'},
    );
    final raw = res is Map ? res['jobs'] : res;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Files an issue against one completed job.
  static Future<Map<String, dynamic>> submit({
    required String jobId,
    required String issueType,
    required String description,
    List<String> subIssues = const [],
    List<String> photos = const [],
  }) async {
    final res = await ApiClient.post('/issues', {
      'jobId': jobId,
      'issueType': issueType,
      'description': description,
      if (subIssues.isNotEmpty) 'subIssues': subIssues,
      if (photos.isNotEmpty) 'photos': photos,
    });
    return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
  }

  /// Uploads one photo and returns its stored URL.
  ///
  /// Reuses the job-photo endpoint rather than adding a parallel one: it
  /// already routes through the same S3-or-disk storage, so issue photos
  /// land wherever job media does.
  static Future<String?> uploadPhoto(String filePath) async {
    final res = await ApiClient.postFile(
      '/jobs/photo',
      field: 'photo',
      filePath: filePath,
    );
    if (res is Map && res['url'] is String) return res['url'] as String;
    return null;
  }
}

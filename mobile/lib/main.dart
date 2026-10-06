import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'config.dart';
import 'state/auth_state.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/otp_screen.dart';
import 'screens/terms_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/profile_setup_address_screen.dart';
import 'screens/profile_setup_skills_screen.dart';
import 'screens/role_chooser_screen.dart';
import 'screens/find_work_setup_screen.dart';
import 'screens/hire_workers_setup_screen.dart';
import 'screens/location_picker_screen.dart';
import 'screens/home_screen.dart';
import 'screens/search_jobs_screen.dart';
import 'screens/job_list_results_screen.dart';
import 'screens/apply_for_job_screen.dart';
import 'screens/request_custom_amount_screen.dart';
import 'screens/request_sent_screen.dart';
import 'screens/my_reviews_screen.dart';
import 'screens/job_history_screen.dart';
import 'screens/job_history_detail_screen.dart';
import 'screens/need_help_type_screen.dart';
import 'screens/need_help_describe_screen.dart';
import 'screens/issue_submitted_screen.dart';
import 'screens/wallet_screen.dart';
import 'screens/add_money_screen.dart';
import 'screens/select_payment_method_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/job_accepted_screen.dart';
import 'screens/immediate_job_active_screen.dart';
import 'screens/my_jobs_screen.dart';
import 'screens/job_status_screen.dart';
import 'screens/enter_otp_screen.dart';
import 'screens/job_started_screen.dart';
import 'screens/complete_job_screen.dart';
import 'screens/job_completed_screen.dart';
import 'screens/rate_experience_screen.dart';
import 'screens/rating_thanks_screen.dart';
import 'screens/payment_request_screen.dart';
import 'screens/payment_qr_screen.dart';
import 'screens/post_job_screen.dart';
import 'screens/post_job_step2_screen.dart';
import 'screens/job_details_screen.dart';
import 'screens/applicants_screen.dart';
import 'screens/cancel_job_screen.dart';
import 'screens/my_posted_jobs_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/nearby_workers_screen.dart';
import 'screens/release_payment_screen.dart';
import 'screens/money_added_screen.dart';
import 'screens/payment_status_screen.dart';
import 'screens/select_release_payment_method_screen.dart';
import 'screens/refer_earn_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/server_settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  try {
    await Firebase.initializeApp();
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    // Firebase is optional during dev — the API auth flow does not depend on it.
    debugPrint('Firebase init skipped: $e');
  }
  runApp(const PargigApp());
}

class PargigApp extends StatelessWidget {
  const PargigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AuthState())],
      child: MaterialApp(
        title: 'Pargig',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF5F6FA),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          // Inputs default to "naked" — no fill, no border. Each screen
          // wraps TextFields in its own styled Container (e.g. the gray
          // pill in profile-setup, post-job, search). That avoids the
          // double-rounded look caused by the theme drawing its own fill
          // inside the custom container.
          inputDecorationTheme: const InputDecorationTheme(
            filled: false,
            fillColor: Colors.transparent,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
          ),
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/onboarding': (_) => const OnboardingScreen(),
          '/login': (_) => const LoginScreen(),
          '/otp': (_) => const OtpScreen(),
          '/terms': (_) => const TermsScreen(),
          '/profile-setup': (_) => const ProfileSetupScreen(),
          '/profile-setup/address': (_) => const ProfileSetupAddressScreen(),
          '/profile-setup/skills': (_) => const ProfileSetupSkillsScreen(),
          '/role-chooser': (_) => const RoleChooserScreen(),
          '/find-work-setup': (_) => const FindWorkSetupScreen(),
          '/hire-workers-setup': (_) => const HireWorkersSetupScreen(),
          '/pick-location': (_) => const LocationPickerScreen(),
          '/home': (_) => const HomeScreen(),
          '/search': (_) => const SearchJobsScreen(),
          '/job-list-results': (_) => const JobListResultsScreen(),
          '/apply-for-job': (_) => const ApplyForJobScreen(),
          '/request-custom-amount': (_) => const RequestCustomAmountScreen(),
          '/request-sent': (_) => const RequestSentScreen(),
          '/wallet': (_) => const WalletScreen(),
          // My Services: service history.
          '/my-reviews': (_) => const MyReviewsScreen(),
          // My Services on the profile opens Job History: the giver's
          // completed jobs, and the way into Need Help from each one.
          '/my-services': (_) => const JobHistoryScreen(),
          '/job-history-detail': (_) => const JobHistoryDetailScreen(),
          '/need-help': (_) => const NeedHelpTypeScreen(),
          '/need-help-describe': (_) => const NeedHelpDescribeScreen(),
          '/issue-submitted': (_) => const IssueSubmittedScreen(),

          '/add-money': (_) => const AddMoneyScreen(),
          '/money-added': (_) => const MoneyAddedScreen(),
          '/select-payment-method': (_) => const SelectPaymentMethodScreen(),
          '/messages': (_) => const MessagesScreen(),
          '/chat': (_) => const ChatScreen(),
          '/job-accepted': (_) => const JobAcceptedScreen(),
          '/immediate-job-active': (_) => const ImmediateJobActiveScreen(),
          '/my-jobs': (_) => const MyJobsScreen(),
          '/job-status': (_) => const JobStatusScreen(),
          '/enter-otp': (_) => const EnterOtpScreen(),
          '/job-started': (_) => const JobStartedScreen(),
          '/complete-job': (_) => const CompleteJobScreen(),
          '/job-completed': (_) => const JobCompletedScreen(),
          '/rate-experience': (_) => const RateExperienceScreen(),
          '/rating-thanks': (_) => const RatingThanksScreen(),
          '/payment-request': (_) => const PaymentRequestScreen(),
          '/payment-qr': (_) => const PaymentQrScreen(),
          '/post-job': (_) => const PostJobScreen(),
          '/post-job/step2': (_) => const PostJobStep2Screen(),
          '/job-details': (_) => const JobDetailsScreen(),
          '/applicants': (_) => const ApplicantsScreen(),
          '/cancel-job': (_) => const CancelJobScreen(),
          '/my-posted-jobs': (_) => const MyPostedJobsScreen(),
          '/profile': (_) => const ProfileScreen(),
          '/edit-profile': (_) => const EditProfileScreen(),
          '/notifications': (_) => const NotificationsScreen(),
          '/nearby-workers': (_) => const NearbyWorkersScreen(),
          '/release-payment': (_) => const ReleasePaymentScreen(),
          '/select-release-payment-method': (_) =>
              const SelectReleasePaymentMethodScreen(),
          '/payment-status': (_) => const PaymentStatusScreen(),
          '/refer-earn': (_) => const ReferEarnScreen(),
          '/settings': (_) => const SettingsScreen(),
          '/server': (_) => const ServerSettingsScreen(),
        },
      ),
    );
  }
}

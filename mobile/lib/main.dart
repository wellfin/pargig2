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
import 'screens/home_screen.dart';
import 'screens/search_jobs_screen.dart';
import 'screens/post_job_screen.dart';
import 'screens/post_job_step2_screen.dart';
import 'screens/job_details_screen.dart';
import 'screens/applicants_screen.dart';
import 'screens/cancel_job_screen.dart';
import 'screens/my_posted_jobs_screen.dart';
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
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState()),
      ],
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
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
          '/home': (_) => const HomeScreen(),
          '/search': (_) => const SearchJobsScreen(),
          '/post-job': (_) => const PostJobScreen(),
          '/post-job/step2': (_) => const PostJobStep2Screen(),
          '/job-details': (_) => const JobDetailsScreen(),
          '/applicants': (_) => const ApplicantsScreen(),
          '/cancel-job': (_) => const CancelJobScreen(),
          '/my-posted-jobs': (_) => const MyPostedJobsScreen(),
          '/server': (_) => const ServerSettingsScreen(),
        },
      ),
    );
  }
}

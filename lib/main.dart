import 'package:flutter/material.dart';

import 'models/auth_models.dart';
import 'screens/auth_page.dart';
import 'screens/email_verification_page.dart';
import 'screens/home_page.dart';
import 'screens/password_reset_page.dart';
import 'services/auth_api.dart';

void main() {
  runApp(const StudyRoomBookingApp());
}

class StudyRoomBookingApp extends StatefulWidget {
  const StudyRoomBookingApp({super.key});

  @override
  State<StudyRoomBookingApp> createState() => _StudyRoomBookingAppState();
}

class _StudyRoomBookingAppState extends State<StudyRoomBookingApp> {
  final AuthApi _authApi = AuthApi();
  LoginSession? _session;

  @override
  Widget build(BuildContext context) {
    final verificationToken = _emailVerificationToken();
    final passwordResetToken = _passwordResetToken();
    return MaterialApp(
      title: '自习室预约',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF27332D),
          primary: const Color(0xFF27332D),
          secondary: const Color(0xFFC9A227),
          surface: const Color(0xFFFFFCF6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFBF8F1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD7CDBB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD7CDBB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFC9A227), width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ),
      home: verificationToken != null
          ? EmailVerificationPage(
              authApi: _authApi,
              token: verificationToken,
              onBackToLogin: () => setState(() => _session = null),
            )
          : passwordResetToken != null
          ? PasswordResetPage(
              authApi: _authApi,
              token: passwordResetToken,
              onBackToLogin: () => setState(() => _session = null),
            )
          : _session == null
          ? AuthPage(
              authApi: _authApi,
              onAuthenticated: (session) => setState(() => _session = session),
            )
          : HomePage(
              session: _session!,
              onLogout: () => setState(() => _session = null),
            ),
    );
  }

  String? _emailVerificationToken() {
    final uri = Uri.base;
    if (uri.path.endsWith('/verify-email')) {
      return uri.queryParameters['token'];
    }
    if (uri.fragment.isNotEmpty) {
      final fragmentUri = Uri.parse(
        uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}',
      );
      if (fragmentUri.path.endsWith('/verify-email')) {
        return fragmentUri.queryParameters['token'];
      }
    }
    return null;
  }

  String? _passwordResetToken() {
    final uri = Uri.base;
    if (uri.path.endsWith('/reset-password')) {
      return uri.queryParameters['token'];
    }
    if (uri.fragment.isNotEmpty) {
      final fragmentUri = Uri.parse(
        uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}',
      );
      if (fragmentUri.path.endsWith('/reset-password')) {
        return fragmentUri.queryParameters['token'];
      }
    }
    return null;
  }
}

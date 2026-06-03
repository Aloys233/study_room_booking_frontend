import 'package:flutter/material.dart';

import 'models/auth_models.dart';
import 'screens/auth_page.dart';
import 'screens/email_verification_page.dart';
import 'screens/home_page.dart';
import 'screens/password_reset_page.dart';
import 'services/auth_api.dart';
import 'services/auth_session_store.dart';

void main() {
  runApp(const StudyRoomBookingApp());
}

typedef AuthApiFactory = AuthApi Function({String? accessToken});

AuthApi _defaultAuthApiFactory({String? accessToken}) {
  return AuthApi(accessToken: accessToken);
}

class StudyRoomBookingApp extends StatefulWidget {
  const StudyRoomBookingApp({
    super.key,
    AuthApiFactory authApiFactory = _defaultAuthApiFactory,
    AuthSessionStore? sessionStore,
  }) : _authApiFactory = authApiFactory,
       _sessionStore = sessionStore;

  final AuthApiFactory _authApiFactory;
  final AuthSessionStore? _sessionStore;

  @override
  State<StudyRoomBookingApp> createState() => _StudyRoomBookingAppState();
}

class _StudyRoomBookingAppState extends State<StudyRoomBookingApp> {
  late final AuthApi _authApi = widget._authApiFactory();
  late final AuthSessionStore _sessionStore =
      widget._sessionStore ?? AuthSessionStore();
  LoginSession? _session;
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final storedSession = await _sessionStore.loadSession();
      if (storedSession == null) {
        if (mounted) setState(() => _restoringSession = false);
        return;
      }

      final authApi = widget._authApiFactory(
        accessToken: storedSession.accessToken,
      );
      final user = await authApi.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _session = LoginSession(
          accessToken: storedSession.accessToken,
          user: user,
        );
        _restoringSession = false;
      });
    } catch (_) {
      await _sessionStore.clearSession();
      if (mounted) {
        setState(() {
          _session = null;
          _restoringSession = false;
        });
      }
    }
  }

  Future<void> _setSession(LoginSession? session) async {
    setState(() => _session = session);
    if (session == null) {
      await _sessionStore.clearSession();
    } else {
      await _sessionStore.saveSession(session);
    }
  }

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
              onBackToLogin: () => _setSession(null),
            )
          : passwordResetToken != null
          ? PasswordResetPage(
              authApi: _authApi,
              token: passwordResetToken,
              onBackToLogin: () => _setSession(null),
            )
          : _restoringSession
          ? const _SessionRestorePage()
          : _session == null
          ? AuthPage(
              authApi: _authApi,
              onAuthenticated: _setSession,
            )
          : HomePage(
              session: _session!,
              onLogout: () => _setSession(null),
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

class _SessionRestorePage extends StatelessWidget {
  const _SessionRestorePage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

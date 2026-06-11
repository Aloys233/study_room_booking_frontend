import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'models/auth_models.dart';
import 'screens/auth_page.dart';
import 'screens/home_page.dart';
import 'services/auth_api.dart';
import 'services/auth_session_store.dart';

const _sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue:
      'https://51fa6fcee0c91a0c535ca34a99737998@o4511504349396992.ingest.us.sentry.io/4511505048666112',
);

Future<void> main() async {
  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    options.environment = kReleaseMode ? 'production' : 'development';
    options.tracesSampleRate = 1.0;
    options.debug = !kReleaseMode;
  }, appRunner: () => runApp(SentryWidget(child: const StudyRoomBookingApp())));
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
      home: _restoringSession
          ? const _SessionRestorePage()
          : _session == null
          ? AuthPage(authApi: _authApi, onAuthenticated: _setSession)
          : HomePage(session: _session!, onLogout: () => _setSession(null)),
    );
  }
}

class _SessionRestorePage extends StatelessWidget {
  const _SessionRestorePage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

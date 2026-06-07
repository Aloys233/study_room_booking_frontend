import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import '../services/auth_api.dart';
import '../widgets/app_notification.dart';
import '../widgets/altcha_widget.dart';

enum AuthMode { login, register }

class AuthPage extends StatefulWidget {
  const AuthPage({
    super.key,
    required this.authApi,
    required this.onAuthenticated,
  });

  final AuthApi authApi;
  final ValueChanged<LoginSession> onAuthenticated;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const _altchaChallengeUrl = '$_apiBaseUrl/api/auth/altcha/challenge';

  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  AuthMode _mode = AuthMode.login;
  bool _obscurePassword = true;
  bool _submitting = false;
  int _altchaVersion = 0;
  String _altchaPayload = '';

  bool get _isRegister => _mode == AuthMode.register;

  @override
  void dispose() {
    _accountController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    if (_altchaPayload.isEmpty) {
      _showMessage('请先完成人机验证');
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_isRegister) {
        await widget.authApi.registerStudent(
          email: _accountController.text.trim(),
          realName: _nameController.text.trim(),
          password: _passwordController.text,
          altchaPayload: _altchaPayload,
        );
        if (!mounted) return;
        setState(() {
          _mode = AuthMode.login;
          _confirmPasswordController.clear();
          _resetAltcha();
        });
        _showMessage('请查收邮箱完成验证，验证后可返回登录', title: '注册成功');
      } else {
        final session = await widget.authApi.loginUser(
          loginName: _accountController.text.trim(),
          password: _passwordController.text,
          altchaPayload: _altchaPayload,
        );
        if (!mounted) return;
        widget.onAuthenticated(session);
      }
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(_resetAltcha);
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      setState(_resetAltcha);
      _showMessage('网络异常，请检查服务是否可用');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _switchMode(AuthMode mode) {
    if (_mode == mode || _submitting) {
      return;
    }
    setState(() {
      _mode = mode;
      _formKey.currentState?.reset();
      _confirmPasswordController.clear();
      _resetAltcha();
    });
  }

  void _resetAltcha() {
    _altchaPayload = '';
    _altchaVersion++;
  }

  void _showMessage(String message, {String? title}) {
    AppNotification.show(context, title: title, message: message);
  }

  Future<void> _showPasswordResetDialog() async {
    final formKey = GlobalKey<FormState>();
    final accountController = TextEditingController(
      text: _accountController.text.trim(),
    );
    final emailController = TextEditingController();
    var submitting = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('找回密码'),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('输入账号和绑定邮箱，系统会发送密码重置邮件。'),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: accountController,
                        enabled: !submitting,
                        decoration: const InputDecoration(
                          labelText: '学号 / 工号 / 邮箱',
                          prefixIcon: Icon(Icons.account_circle_rounded),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          return text.isEmpty ? '请输入学号 / 工号 / 邮箱' : null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        enabled: !submitting,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: '绑定邮箱',
                          prefixIcon: Icon(Icons.email_rounded),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return '请输入绑定邮箱';
                          if (!email.contains('@') ||
                              email.startsWith('@') ||
                              email.endsWith('@')) {
                            return '邮箱格式不正确';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton.icon(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setDialogState(() => submitting = true);
                            try {
                              await widget.authApi.requestPasswordReset(
                                userNo: accountController.text.trim(),
                                email: emailController.text.trim(),
                              );
                              if (!mounted || !dialogContext.mounted) return;
                              Navigator.of(dialogContext).pop();
                              _showMessage('如果账号和邮箱匹配，系统会发送密码找回邮件');
                            } on AuthApiException catch (error) {
                              if (mounted) _showMessage(error.message);
                            } catch (_) {
                              if (mounted) _showMessage('密码找回请求失败，请稍后重试');
                            } finally {
                              if (dialogContext.mounted) {
                                setDialogState(() => submitting = false);
                              }
                            }
                          },
                    icon: submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mark_email_read_rounded),
                    label: const Text('发送邮件'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      accountController.dispose();
      emailController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 760;
    final isCompact = screenWidth < 420;
    final authCard = _AuthCard(
      mode: _mode,
      isCompact: isCompact,
      isSubmitting: _submitting,
      obscurePassword: _obscurePassword,
      formKey: _formKey,
      accountController: _accountController,
      nameController: _nameController,
      passwordController: _passwordController,
      confirmPasswordController: _confirmPasswordController,
      onModeChanged: _switchMode,
      onObscurePasswordChanged: () {
        setState(() => _obscurePassword = !_obscurePassword);
      },
      altchaChallengeUrl: _altchaChallengeUrl,
      altchaKey: ValueKey(_altchaVersion),
      hasAltchaPayload: _altchaPayload.isNotEmpty,
      onAltchaPayloadChanged: (payload) {
        setState(() => _altchaPayload = payload);
      },
      onAltchaError: _showMessage,
      onSubmit: _submitting ? null : _submit,
      onForgotPassword: _showPasswordResetDialog,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 14 : 28,
              vertical: isCompact ? 14 : 28,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: isWide
                  ? SizedBox(
                      height: _isRegister ? 760 : 640,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(
                            flex: 5,
                            child: _BrandPanel(isWide: true),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 4,
                            child: SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: _isRegister ? 760 : 640,
                                ),
                                child: authCard,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: isCompact ? 210 : 280,
                          ),
                          child: const _BrandPanel(isWide: false),
                        ),
                        SizedBox(height: isCompact ? 12 : 16),
                        authCard,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final compact = !isWide && MediaQuery.sizeOf(context).width < 420;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF25332B),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(isWide ? 42 : (compact ? 18 : 24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0B33D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.event_seat_rounded,
                    color: Color(0xFF25332B),
                  ),
                ),
                const SizedBox(width: 14),
                const Text(
                  '自习室预约',
                  style: TextStyle(
                    color: Color(0xFFFFFCF6),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: isWide ? 64 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '预约座位',
                    style:
                        (compact
                                ? Theme.of(context).textTheme.headlineMedium
                                : Theme.of(context).textTheme.displaySmall)
                            ?.copyWith(
                              color: const Color(0xFFFFFCF6),
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                            ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '学生和教师可用学号、工号或邮箱登录，校外人员使用邮箱注册并登录。',
                    style: TextStyle(
                      color: Color(0xFFD6CEC1),
                      fontSize: 16,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
            const Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FeaturePill(icon: Icons.schedule_rounded, label: '分时预约'),
                _FeaturePill(icon: Icons.grid_view_rounded, label: '座位图'),
                _FeaturePill(icon: Icons.fact_check_rounded, label: '签到核验'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF314238),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF465A4E)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: const Color(0xFFE0B33D)),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFFFFCF6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.mode,
    required this.isCompact,
    required this.isSubmitting,
    required this.obscurePassword,
    required this.formKey,
    required this.accountController,
    required this.nameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.onModeChanged,
    required this.onObscurePasswordChanged,
    required this.altchaChallengeUrl,
    required this.altchaKey,
    required this.hasAltchaPayload,
    required this.onAltchaPayloadChanged,
    required this.onAltchaError,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  final AuthMode mode;
  final bool isCompact;
  final bool isSubmitting;
  final bool obscurePassword;
  final GlobalKey<FormState> formKey;
  final TextEditingController accountController;
  final TextEditingController nameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final ValueChanged<AuthMode> onModeChanged;
  final VoidCallback onObscurePasswordChanged;
  final String altchaChallengeUrl;
  final Key altchaKey;
  final bool hasAltchaPayload;
  final ValueChanged<String> onAltchaPayloadChanged;
  final ValueChanged<String> onAltchaError;
  final VoidCallback? onSubmit;
  final VoidCallback onForgotPassword;

  bool get _isRegister => mode == AuthMode.register;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2DACB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1B241F),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 16 : 28),
        child: Align(
          alignment: Alignment.center,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _isRegister
                      ? Icons.person_add_alt_1_rounded
                      : Icons.login_rounded,
                  size: 34,
                  color: const Color(0xFF25332B),
                ),
                const SizedBox(height: 14),
                Text(
                  _isRegister ? '校外人员注册' : '账号登录',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRegister ? '使用邮箱和密码注册，完成邮箱验证后可继续使用。' : '学号、工号或邮箱均可登录。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF6F675A)),
                ),
                SizedBox(height: isCompact ? 18 : 22),
                TextFormField(
                  controller: accountController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _accountLabel,
                    prefixIcon: Icon(_accountIcon),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return '请输入$_accountLabel';
                    }
                    if (_isRegister &&
                        (!text.contains('@') ||
                            text.startsWith('@') ||
                            text.endsWith('@'))) {
                      return '邮箱格式不正确';
                    }
                    return null;
                  },
                ),
                if (_isRegister) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '真实姓名',
                      prefixIcon: Icon(Icons.badge_rounded),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return '请输入真实姓名';
                      }
                      if (text.length > 50) {
                        return '姓名不能超过 50 个字符';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  textInputAction: _isRegister
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_isRegister) {
                      onSubmit?.call();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    suffixIcon: IconButton(
                      tooltip: obscurePassword ? '显示密码' : '隐藏密码',
                      onPressed: onObscurePasswordChanged,
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final text = value ?? '';
                    if (text.isEmpty) {
                      return '请输入密码';
                    }
                    if (_isRegister && text.length < 6) {
                      return '密码至少 6 位';
                    }
                    if (text.length > 64) {
                      return '密码不能超过 64 位';
                    }
                    return null;
                  },
                ),
                if (_isRegister) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmPasswordController,
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => onSubmit?.call(),
                    decoration: const InputDecoration(
                      labelText: '确认密码',
                      prefixIcon: Icon(Icons.verified_user_rounded),
                    ),
                    validator: (value) {
                      if (value != passwordController.text) {
                        return '两次输入的密码不一致';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = (constraints.maxWidth / 300).clamp(0.0, 1.0);
                    return Center(
                      child: SizedBox(
                        width: 300 * scale,
                        height: 80 * scale,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AltchaWidget(
                            key: altchaKey,
                            challengeUrl: altchaChallengeUrl,
                            onPayloadChanged: onAltchaPayloadChanged,
                            onError: onAltchaError,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: isCompact ? 18 : 24),
                FilledButton.icon(
                  onPressed: hasAltchaPayload ? onSubmit : null,
                  icon: isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isRegister
                              ? Icons.person_add_alt_1_rounded
                              : Icons.login_rounded,
                        ),
                  label: Text(
                    isSubmitting ? '提交中' : (_isRegister ? '注册' : '登录'),
                  ),
                ),
                const SizedBox(height: 12),
                if (_isRegister)
                  Center(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        const Text(
                          '已有账号？',
                          style: TextStyle(color: Color(0xFF6F675A)),
                        ),
                        TextButton(
                          onPressed: isSubmitting
                              ? null
                              : () => onModeChanged(AuthMode.login),
                          child: const Text('去登录'),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: [
                      TextButton(
                        onPressed: isSubmitting ? null : onForgotPassword,
                        child: const Text('找回密码'),
                      ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        alignment: WrapAlignment.center,
                        children: [
                          const Text(
                            '没有账号？',
                            style: TextStyle(color: Color(0xFF6F675A)),
                          ),
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => onModeChanged(AuthMode.register),
                            child: const Text('注册'),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _accountLabel {
    if (_isRegister) {
      return '邮箱';
    }
    return '学号 / 工号 / 邮箱';
  }

  IconData get _accountIcon {
    if (_isRegister) {
      return Icons.email_rounded;
    }
    return Icons.account_circle_rounded;
  }
}

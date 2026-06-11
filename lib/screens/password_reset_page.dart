import 'package:flutter/material.dart';

import '../services/auth_api.dart';
import '../widgets/altcha_widget.dart';
import '../widgets/app_notification.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({
    super.key,
    required this.authApi,
  });

  final AuthApi authApi;

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const _altchaChallengeUrl = '$_apiBaseUrl/api/auth/altcha/challenge';

  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _sending = false;
  bool _submitting = false;
  bool _codeSent = false;
  int _altchaVersion = 0;
  String _altchaPayload = '';

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return email.contains('@') &&
        !email.startsWith('@') &&
        !email.endsWith('@');
  }

  bool _isValidVerificationCode(String code) {
    final normalized = code.trim().toUpperCase();
    return RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalized);
  }

  void _resetAltcha() {
    setState(() {
      _altchaPayload = '';
      _altchaVersion++;
    });
  }

  void _showMessage(String message, {String? title}) {
    AppNotification.show(context, title: title, message: message);
  }

  Future<void> _sendCode() async {
    final form = _emailFormKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    if (_altchaPayload.isEmpty) {
      _showMessage('请先完成人机验证');
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.authApi.requestPasswordReset(
        email: _emailController.text.trim(),
        altchaPayload: _altchaPayload,
      );
      if (!mounted) return;
      setState(() => _codeSent = true);
      _showMessage('如果邮箱已绑定账号，系统会发送验证码');
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('验证码发送失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _resetAltcha();
      }
    }
  }

  Future<void> _submitReset() async {
    final form = _resetFormKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    if (_altchaPayload.isEmpty) {
      _showMessage('请先完成人机验证');
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.authApi.confirmPasswordReset(
        email: _emailController.text.trim(),
        code: _codeController.text.trim().toUpperCase(),
        newPassword: _passwordController.text,
        altchaPayload: _altchaPayload,
      );
      if (!mounted) return;
      _showMessage('密码已重置，请使用新密码登录');
      Navigator.of(context).pop();
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('密码重置失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
        _resetAltcha();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('找回密码'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2DACB)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x101B241F),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.all(compact ? 22 : 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_reset_rounded,
                        size: 54,
                        color: Color(0xFFC9A227),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _codeSent ? '输入验证码并设置新密码' : '通过邮箱重置密码',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _codeSent
                            ? '验证码已发送后，在此完成验证并设置新密码。'
                            : '填写绑定邮箱并通过人机验证后，进入验证码重置步骤。',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF6F675A)),
                      ),
                      const SizedBox(height: 24),
                      Form(
                        key: _emailFormKey,
                        child: TextFormField(
                          controller: _emailController,
                          enabled: !_codeSent && !_sending && !_submitting,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: '绑定邮箱',
                            prefixIcon: Icon(Icons.email_rounded),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return '请输入绑定邮箱';
                            if (!_isValidEmail(email)) return '邮箱格式不正确';
                            return null;
                          },
                        ),
                      ),
                      if (_codeSent) ...[
                        const SizedBox(height: 16),
                        Form(
                          key: _resetFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _codeController,
                                      enabled: !_submitting,
                                      keyboardType: TextInputType.visiblePassword,
                                      maxLength: 6,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      decoration: const InputDecoration(
                                        labelText: '验证码',
                                        prefixIcon: Icon(Icons.verified_rounded),
                                        counterText: '',
                                      ),
                                      validator: (value) {
                                        final code = value?.trim() ?? '';
                                        if (code.isEmpty) return '请输入验证码';
                                        if (!_isValidVerificationCode(code)) {
                                          return '请输入 6 位数字或大写字母';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: _sending || _submitting ? null : _sendCode,
                                    child: Text(_sending ? '发送中' : '重新发送验证码'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                enabled: !_submitting,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: '新密码',
                                  prefixIcon: Icon(Icons.lock_rounded),
                                ),
                                validator: (value) {
                                  final text = value ?? '';
                                  if (text.isEmpty) return '请输入新密码';
                                  if (text.length < 6) return '密码至少 6 位';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirmPasswordController,
                                enabled: !_submitting,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: '确认密码',
                                  prefixIcon: Icon(Icons.verified_user_rounded),
                                ),
                                validator: (value) {
                                  return value == _passwordController.text
                                      ? null
                                      : '两次输入的密码不一致';
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Center(
                        child: AltchaWidget(
                          key: ValueKey('password-reset-page-altcha-$_altchaVersion'),
                          challengeUrl: _altchaChallengeUrl,
                          onPayloadChanged: (payload) {
                            setState(() => _altchaPayload = payload);
                          },
                          onError: _showMessage,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (_codeSent)
                        FilledButton.icon(
                          onPressed: _submitting ? null : _submitReset,
                          icon: _submitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_rounded),
                          label: Text(_submitting ? '提交中' : '重置密码'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _sending ? null : _sendCode,
                          icon: _sending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.mark_email_read_rounded),
                          label: Text(_sending ? '发送中' : '下一步'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

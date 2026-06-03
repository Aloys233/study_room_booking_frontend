import 'package:flutter/material.dart';

import '../services/auth_api.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    super.key,
    required this.authApi,
    required this.token,
    required this.onBackToLogin,
  });

  final AuthApi authApi;
  final String token;
  final VoidCallback onBackToLogin;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool _loading = true;
  bool _success = false;
  String _message = '正在验证邮箱';

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    if (widget.token.trim().isEmpty) {
      setState(() {
        _loading = false;
        _success = false;
        _message = '验证链接缺少凭证';
      });
      return;
    }

    try {
      await widget.authApi.verifyEmail(token: widget.token.trim());
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
        _message = '邮箱验证成功，账号已激活';
      });
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _message = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _message = '验证失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F1EA),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: EdgeInsets.all(compact ? 16 : 24),
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
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        _loading
                            ? Icons.mark_email_unread_rounded
                            : (_success
                                  ? Icons.mark_email_read_rounded
                                  : Icons.error_outline_rounded),
                        size: 54,
                        color: _success
                            ? const Color(0xFF27332D)
                            : const Color(0xFFC9A227),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _success ? '验证完成' : '邮箱验证',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF6F675A)),
                      ),
                      const SizedBox(height: 22),
                      if (_loading)
                        const Center(child: CircularProgressIndicator())
                      else
                        FilledButton.icon(
                          onPressed: widget.onBackToLogin,
                          icon: const Icon(Icons.login_rounded),
                          label: const Text('返回登录'),
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

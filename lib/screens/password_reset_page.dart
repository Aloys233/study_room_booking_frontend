import 'package:flutter/material.dart';

import '../services/auth_api.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({
    super.key,
    required this.authApi,
    required this.token,
    required this.onBackToLogin,
  });

  final AuthApi authApi;
  final String token;
  final VoidCallback onBackToLogin;

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _submitting = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (widget.token.trim().isEmpty) {
      setState(() => _error = '重置链接缺少凭证');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.authApi.confirmPasswordReset(
        token: widget.token.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      setState(() => _success = true);
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '密码重置失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2EB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
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
                  child: _success ? _successView(context) : _formView(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _successView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.lock_reset_rounded,
          size: 54,
          color: Color(0xFF27332D),
        ),
        const SizedBox(height: 18),
        Text(
          '密码已重置',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        const Text(
          '请使用新密码重新登录。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF6F675A)),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: widget.onBackToLogin,
          icon: const Icon(Icons.login_rounded),
          label: const Text('返回登录'),
        ),
      ],
    );
  }

  Widget _formView(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.lock_reset_rounded,
            size: 54,
            color: Color(0xFFC9A227),
          ),
          const SizedBox(height: 18),
          Text(
            '设置新密码',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          const Text(
            '请输入新的账号密码。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF6F675A)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8F3D3D)),
            ),
          ],
          const SizedBox(height: 20),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: '新密码',
              prefixIcon: Icon(Icons.lock_rounded),
            ),
            validator: (value) {
              final text = value ?? '';
              if (text.isEmpty) return '请输入新密码';
              if (text.length < 6) return '密码至少 6 位';
              if (text.length > 64) return '密码不能超过 64 位';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '确认新密码',
              prefixIcon: Icon(Icons.verified_user_rounded),
            ),
            validator: (value) {
              return value == _passwordController.text ? null : '两次输入的密码不一致';
            },
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: Text(_submitting ? '提交中' : '重置密码'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _submitting ? null : widget.onBackToLogin,
            child: const Text('返回登录'),
          ),
        ],
      ),
    );
  }
}

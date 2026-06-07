import 'dart:async';

import 'package:flutter/material.dart';

enum AppNotificationKind { info, success, error }

class AppNotification {
  AppNotification._();

  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context, {
    required String message,
    String? title,
    AppNotificationKind? kind,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }

    _currentEntry?.remove();
    _currentEntry = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _NotificationOverlay(
          title: title,
          message: message,
          kind: kind ?? _inferKind(message),
          onClose: () {
            if (_currentEntry == entry) {
              _currentEntry = null;
            }
            entry.remove();
          },
        );
      },
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  static AppNotificationKind _inferKind(String message) {
    if (message.contains('失败') ||
        message.contains('异常') ||
        message.contains('错误') ||
        message.contains('不正确') ||
        message.contains('不一致') ||
        message.contains('请输入') ||
        message.contains('请选择') ||
        message.contains('未通过')) {
      return AppNotificationKind.error;
    }
    if (message.contains('成功') ||
        message.contains('已') ||
        message.contains('完成')) {
      return AppNotificationKind.success;
    }
    return AppNotificationKind.info;
  }
}

class _NotificationOverlay extends StatefulWidget {
  const _NotificationOverlay({
    required this.message,
    required this.kind,
    required this.onClose,
    this.title,
  });

  final String? title;
  final String message;
  final AppNotificationKind kind;
  final VoidCallback onClose;

  @override
  State<_NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<_NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0.12, -0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _timer = Timer(const Duration(seconds: 4), _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 560;
    final top = viewPadding.top + 14;
    final right = compact ? 12.0 : 20.0;
    final left = compact ? 12.0 : null;
    final maxWidth = compact ? width - 24 : 360.0;

    return Positioned(
      top: top,
      right: right,
      left: left,
      child: SafeArea(
        child: IgnorePointer(
          ignoring: false,
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _opacity,
              child: Material(
                color: Colors.transparent,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: _NotificationCard(
                    title: widget.title,
                    message: widget.message,
                    kind: widget.kind,
                    onClose: _close,
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.message,
    required this.kind,
    required this.onClose,
    this.title,
  });

  final String? title;
  final String message;
  final AppNotificationKind kind;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accent = switch (kind) {
      AppNotificationKind.success => const Color(0xFF2F6B4F),
      AppNotificationKind.error => const Color(0xFF9A3D3D),
      AppNotificationKind.info => const Color(0xFFC9A227),
    };
    final icon = switch (kind) {
      AppNotificationKind.success => Icons.check_circle_rounded,
      AppNotificationKind.error => Icons.error_rounded,
      AppNotificationKind.info => Icons.notifications_rounded,
    };
    final effectiveTitle =
        title ??
        switch (kind) {
          AppNotificationKind.success => '操作成功',
          AppNotificationKind.error => '提示',
          AppNotificationKind.info => '通知',
        };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF7FFFCF6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2DACB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x241B241F),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
          BoxShadow(
            color: Color(0x14FFFFFF),
            blurRadius: 1,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    effectiveTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF25332B),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF6F675A),
                      fontSize: 13,
                      height: 1.38,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '关闭',
              onPressed: onClose,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const Icon(Icons.close_rounded, color: Color(0xFF7A7164)),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

class AltchaWidget extends StatefulWidget {
  const AltchaWidget({
    super.key,
    required this.challengeUrl,
    required this.onPayloadChanged,
    required this.onError,
  });

  final String challengeUrl;
  final ValueChanged<String> onPayloadChanged;
  final ValueChanged<String> onError;

  @override
  State<AltchaWidget> createState() => _AltchaWidgetState();
}

class _AltchaWidgetState extends State<AltchaWidget> {
  static const _scriptAsset = 'assets/vendor/altcha.min.js';
  static Future<void>? _scriptLoadFuture;

  late final String _viewType;
  late final web.HTMLDivElement _container;
  late final JSFunction _stateChangeListener;
  web.HTMLElement? _element;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _viewType = 'altcha-${DateTime.now().microsecondsSinceEpoch}';
    _container = (web.document.createElement('div') as web.HTMLDivElement)
      ..style.width = '300px'
      ..style.height = '80px'
      ..style.minHeight = '70px';
    _stateChangeListener = _handleStateChange.toJS;

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _container,
    );

    _loadScript().then(
      (_) {
        if (!_disposed) _renderAltcha();
      },
      onError: (Object error) {
        if (!_disposed) widget.onError('ALTCHA 脚本加载失败：$error');
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _element?.removeEventListener('statechange', _stateChangeListener);
    _element?.remove();
    super.dispose();
  }

  Future<void> _loadScript() async {
    _scriptLoadFuture ??= _injectScript();
    await _scriptLoadFuture;
  }

  Future<void> _injectScript() async {
    final source = await rootBundle.loadString(_scriptAsset);
    final script =
        (web.document.createElement('script') as web.HTMLScriptElement)
          ..type = 'module'
          ..text = source;
    web.document.head!.append(script);
  }

  void _renderAltcha() {
    if (!mounted || widget.challengeUrl.isEmpty || _element != null) return;

    final element =
        web.document.createElement('altcha-widget') as web.HTMLElement
          ..setAttribute('challenge', widget.challengeUrl)
          ..setAttribute('hidefooter', '')
          ..style.width = '300px'
          ..style.height = '80px';
    element.addEventListener('statechange', _stateChangeListener);
    _container.append(element);
    _element = element;
  }

  void _handleStateChange(web.Event event) {
    final detail = (event as JSObject).getProperty('detail'.toJS).dartify();
    if (detail is! Map) return;

    final state = detail['state']?.toString();
    final payload = detail['payload']?.toString();
    if (state == 'verified' && payload != null && payload.isNotEmpty) {
      widget.onPayloadChanged(payload);
    } else if (state == 'error') {
      widget.onPayloadChanged('');
      widget.onError('人机验证失败');
    } else if (state == 'expired' || state == 'unverified') {
      widget.onPayloadChanged('');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 80,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

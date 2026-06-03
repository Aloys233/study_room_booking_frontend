import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
  static const _baseUrl = String.fromEnvironment(
    'ALTCHA_WEBVIEW_BASE_URL',
    defaultValue: 'https://srbf.komira.top',
  );

  late final Future<String> _htmlFuture;

  @override
  void initState() {
    super.initState();
    _htmlFuture = _buildHtml(widget.challengeUrl);
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return FutureBuilder<String>(
        future: _htmlFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const _PlaceholderBox(message: '人机验证加载中');
          }
          return _buildInlineWebView(snapshot.data!);
        },
      );
    }
    return const _PlaceholderBox(message: '当前平台暂不支持人机验证');
  }

  Widget _buildInlineWebView(String html) {
    return SizedBox(
      width: 300,
      height: 80,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: html,
          baseUrl: WebUri(_baseUrl),
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          javaScriptEnabled: true,
          domStorageEnabled: true,
          supportZoom: false,
          disableHorizontalScroll: true,
          disableVerticalScroll: true,
        ),
        onWebViewCreated: (controller) {
          controller.addJavaScriptHandler(
            handlerName: 'FlutterAltcha',
            callback: _handleInAppMessage,
          );
        },
        onConsoleMessage: (controller, message) {
          debugPrint(
            '[ALTCHA WebView] ${message.messageLevel}: ${message.message}',
          );
        },
        onReceivedError: (controller, request, error) {
          debugPrint('[ALTCHA WebView] resource error: ${error.description}');
        },
      ),
    );
  }

  Object? _handleInAppMessage(List<dynamic> args) {
    if (!mounted || args.isEmpty) return null;
    final raw = args.first?.toString() ?? '';
    if (raw.startsWith('payload:')) {
      widget.onPayloadChanged(raw.substring(8));
    } else if (raw == 'expired' || raw == 'unverified') {
      widget.onPayloadChanged('');
    } else if (raw.startsWith('error:')) {
      widget.onPayloadChanged('');
      widget.onError('人机验证失败：${raw.substring(6)}');
    }
    return null;
  }

  static Future<String> _buildHtml(String challengeUrl) async {
    final challengeJson = jsonEncode(challengeUrl);
    final scriptSource = await rootBundle.loadString(_scriptAsset);
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: transparent;
      overflow: hidden;
      height: 100%;
    }
    body {
      display: flex;
      align-items: center;
      justify-content: center;
    }
    altcha-widget {
      width: 300px;
    }
  </style>
  <script type="module">
${_escapeClosingScript(scriptSource)}
  </script>
</head>
<body>
  <altcha-widget id="altcha" challenge=$challengeJson hidefooter></altcha-widget>
  <script>
    $_inAppBridgeJs
    window.addEventListener('load', function() {
      var widget = document.getElementById('altcha');
      if (!widget) {
        postToFlutter('error:widget_not_found');
        return;
      }
      widget.addEventListener('statechange', function(ev) {
        var detail = ev.detail || {};
        if (detail.state === 'verified' && detail.payload) {
          postToFlutter('payload:' + detail.payload);
        } else if (detail.state === 'expired' || detail.state === 'unverified') {
          postToFlutter(detail.state);
        } else if (detail.state === 'error') {
          postToFlutter('error:verify_failed');
        }
      });
    });
  </script>
</body>
</html>''';
  }

  static String _escapeClosingScript(String source) {
    return source.replaceAll('</script>', r'<\/script>');
  }

  static const _inAppBridgeJs = '''
    function postToFlutter(message) {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('FlutterAltcha', message);
      }
    }
  ''';
}

class _PlaceholderBox extends StatelessWidget {
  const _PlaceholderBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      height: 65,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2DACB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF6F675A), fontSize: 12),
      ),
    );
  }
}
